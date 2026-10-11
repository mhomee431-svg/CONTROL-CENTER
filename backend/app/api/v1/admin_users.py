"""Admin user management — the RBAC registry and its high-impact operations.

The console's Admin User Management surface needs more than the read-only view
that `people.py` provides: creating an operator, changing a role, deactivating
an account and resetting an account's access are all governance actions that
must be auditable.

Every mutation here is:
  - authorized by an explicit capability (`admins.manage` / `admins.roles.manage`),
  - guarded so an operator cannot act on itself (lock-out / privilege footgun),
  - guarded so only the platform owner may touch another owner,
  - recorded in the append-only audit trail with the operator's reason.

The platform owner is the single centralized authority. A delegated admin that
holds `admins.manage` may create and deactivate ordinary operators, but may
never create another owner, change an owner's role, or deactivate an owner.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.pagination import Pagination, pagination
from app.core.responses import ok, paged
from app.core.security import (
    get_current_admin,
    hash_password,
    require_capability,
)
from app.models import AdminUser, AuditLog, RevokedAdminToken

router = APIRouter(prefix="/admin/admin-users", tags=["admin-users"])

# The fields the console renders. `hashed_password` is deliberately absent —
# a credential never leaves the server.
ADMIN_USER_FIELDS = [
    "id", "username", "name", "email", "role_name", "level",
    "is_owner", "is_active", "last_login", "created_at", "updated_at",
]

# Roles a delegated admin is permitted to assign. OWNER is excluded: ownership
# is created only by the platform owner through `_assert_can_assign_role`.
ASSIGNABLE_ROLES = (
    "SUPER_ADMIN",
    "ADMIN",
    "VERIFICATION_ADMIN",
    "OPERATIONS_ADMIN",
    "SUPPORT_ADMIN",
    "CONTENT_ADMIN",
    "ANALYST",
)


def _serialise(admin: AdminUser) -> dict:
    """One administrator, with its capability grants but never its hash."""
    return {
        "id": admin.id,
        "username": admin.username,
        "name": admin.name,
        "email": admin.email,
        "role_name": admin.role_name,
        "level": admin.level,
        "is_owner": bool(admin.is_owner),
        "is_active": bool(admin.is_active),
        "permissions": list(admin.permissions or []),
        "last_login": admin.last_login.isoformat() if admin.last_login else None,
        "created_at": admin.created_at.isoformat() if admin.created_at else None,
        "updated_at": admin.updated_at.isoformat() if admin.updated_at else None,
    }


def _get_target_or_404(db: Session, admin_id: int) -> AdminUser:
    target = db.get(AdminUser, admin_id)
    if target is None:
        raise HTTPException(status_code=404, detail=f"Administrator {admin_id} not found")
    return target


def _assert_not_self(actor: AdminUser, target: AdminUser, verb: str) -> None:
    """An operator must never disable or downgrade its own account.

    Without this a single mis-click can lock the only administrator out of the
    console, which is unrecoverable from inside the product.
    """
    if actor.id == target.id:
        raise HTTPException(
            status_code=422,
            detail=f"You cannot {verb} your own account. Ask another administrator.",
        )


def _assert_can_touch(actor: AdminUser, target: AdminUser) -> None:
    """Only the platform owner may act on another owner."""
    if target.is_owner and not actor.is_owner:
        raise HTTPException(
            status_code=403,
            detail="Only the platform owner can manage another platform owner.",
        )


def _record_audit(
    db: Session, admin: AdminUser, action: str, entity_id: int, details: dict | None = None
) -> None:
    db.add(
        AuditLog(
            action=action,
            entity_type="admin_user",
            entity_id=entity_id,
            user_id=admin.id,
            admin_user=admin.name or admin.username,
            details=details or {},
        )
    )


@router.get("")
def list_admin_users(
    page: Pagination = Depends(pagination),
    role: str | None = None,
    status: str | None = None,
    db: Session = Depends(get_db),
    _: AdminUser = Depends(require_capability("admins.read")),
):
    """The administrator registry.

    Filters mirror the console: a role filter and an active/inactive status
    filter, both applied server-side so the total counts only what was asked
    for and paging a filtered list never hides matching rows.
    """
    stmt = select(AdminUser)
    if role:
        stmt = stmt.where(AdminUser.role_name == role)
    if status:
        wanted = status.strip().upper()
        if wanted in ("ACTIVE", "TRUE", "ENABLED"):
            stmt = stmt.where(AdminUser.is_active.is_(True))
        elif wanted in ("INACTIVE", "DISABLED", "DEACTIVATED"):
            stmt = stmt.where(AdminUser.is_active.is_(False))
    if page.search:
        like = f"%{page.search}%"
        stmt = stmt.where(
            or_(
                AdminUser.username.ilike(like),
                AdminUser.name.ilike(like),
                AdminUser.email.ilike(like),
                AdminUser.role_name.ilike(like),
            )
        )
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    start, end = page.window()
    rows = db.scalars(stmt.order_by(AdminUser.id).offset(start).limit(end - start)).all()
    return ok(paged([_serialise(a) for a in rows], total))


@router.get("/roles")
def list_roles(_: AdminUser = Depends(require_capability("admins.read"))):
    """Role catalogue for the role pickers, including the ownership marker."""
    return ok(
        {
            "items": [
                {"name": name, "assignable": True, "is_owner": False}
                for name in ASSIGNABLE_ROLES
            ] + [{"name": "OWNER", "assignable": False, "is_owner": True}],
        }
    )


class AdminUserCreate(BaseModel):
    """Create an operator. The reason is recorded in the audit trail."""

    username: str = Field(min_length=3, max_length=64)
    password: str = Field(min_length=8, max_length=72)
    name: str | None = Field(default=None, max_length=128)
    email: str | None = Field(default=None, max_length=255)
    role_name: str = "SUPPORT_ADMIN"
    reason: str | None = None

    @field_validator("role_name")
    @classmethod
    def _known_role(cls, value: str) -> str:
        if value.strip().upper() not in ASSIGNABLE_ROLES:
            raise ValueError(
                "Unknown role. Expected one of: " + ", ".join(ASSIGNABLE_ROLES)
            )
        return value.strip().upper()

    @field_validator("username")
    @classmethod
    def _clean_username(cls, value: str) -> str:
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("username is required")
        return cleaned


@router.post("")
def create_admin_user(
    payload: AdminUserCreate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("admins.manage")),
):
    """Create a new administrator. Never creates an owner.

    Ownership is a singular, transferable property rather than something a
    delegated admin can mint, so `is_owner` is not exposed on this schema.
    """
    existing = db.scalar(select(AdminUser).where(AdminUser.username == payload.username))
    if existing is not None:
        raise HTTPException(status_code=409, detail=f"Username '{payload.username}' is already taken")

    new_admin = AdminUser(
        username=payload.username,
        name=payload.name,
        email=payload.email,
        role_name=payload.role_name,
        level="SUB",
        is_owner=False,
        is_active=True,
        hashed_password=hash_password(payload.password),
        permissions=[],
    )
    db.add(new_admin)
    db.flush()  # assign the id before the audit row references it
    _record_audit(
        db,
        admin,
        "admin_user.created",
        new_admin.id,
        {"username": new_admin.username, "role_name": new_admin.role_name, "reason": payload.reason},
    )
    db.commit()
    db.refresh(new_admin)
    return ok(_serialise(new_admin), message=f"Administrator '{new_admin.username}' created")


class AdminUserStatusUpdate(BaseModel):
    is_active: bool
    reason: str | None = None


@router.patch("/{admin_id}/status")
def set_admin_user_status(
    admin_id: int,
    payload: AdminUserStatusUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("admins.manage")),
):
    """Activate or deactivate an administrator.

    Deactivation also revokes that account's outstanding sessions, so a
    deactivated operator cannot keep using a token issued before the change —
    which is the whole point of deactivating rather than merely flagging.
    """
    target = _get_target_or_404(db, admin_id)
    _assert_not_self(admin, target, "deactivate")
    _assert_can_touch(admin, target)

    if target.is_owner and not payload.is_active:
        raise HTTPException(
            status_code=403,
            detail="The platform owner cannot be deactivated. Transfer ownership first.",
        )

    previous = bool(target.is_active)
    target.is_active = payload.is_active

    # Belt and braces: deactivation also revokes this account's outstanding
    # sessions so it takes effect immediately rather than at token expiry.
    sessions_revoked = 0
    if not payload.is_active:
        sessions_revoked = _revoke_all_sessions_for(db, target.id)

    _record_audit(
        db,
        admin,
        "admin_user.activated" if payload.is_active else "admin_user.deactivated",
        target.id,
        {
            "from": previous,
            "to": payload.is_active,
            "reason": payload.reason,
            "sessions_revoked": sessions_revoked,
        },
    )
    db.commit()
    db.refresh(target)
    return ok(
        _serialise(target),
        message=f"Administrator '{target.username}' "
        + ("reactivated" if payload.is_active else "deactivated"),
    )


class AdminUserRoleUpdate(BaseModel):
    role_name: str
    reason: str | None = None

    @field_validator("role_name")
    @classmethod
    def _known_role(cls, value: str) -> str:
        if value.strip().upper() not in ASSIGNABLE_ROLES:
            raise ValueError(
                "Unknown role. Expected one of: " + ", ".join(ASSIGNABLE_ROLES)
            )
        return value.strip().upper()


@router.patch("/{admin_id}/role")
def change_admin_user_role(
    admin_id: int,
    payload: AdminUserRoleUpdate,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("admins.roles.manage")),
):
    """Change an administrator's role, and re-derive its capability grants.

    Role is authoritative: changing it replaces the explicit grant list with
    the one the new role implies, so a downgrade actually removes the
    privileges the old role carried rather than leaving them stranded.
    """
    target = _get_target_or_404(db, admin_id)
    _assert_not_self(admin, target, "change the role of")
    _assert_can_touch(admin, target)

    previous = target.role_name
    target.role_name = payload.role_name
    target.level = "SUPER" if payload.role_name == "SUPER_ADMIN" else "SUB"
    # Grants follow the role. An owner keeps its implicit wildcard and is not
    # reachable here anyway (ownership is not an assignable role).
    target.permissions = _role_default_permissions(payload.role_name)

    _record_audit(
        db,
        admin,
        "admin_user.role_changed",
        target.id,
        {"from": previous, "to": payload.role_name, "reason": payload.reason},
    )
    db.commit()
    db.refresh(target)
    return ok(
        _serialise(target),
        message=f"Role changed from {previous or 'none'} to {payload.role_name}",
    )


class AdminAccessReset(BaseModel):
    new_password: str | None = Field(default=None, min_length=8, max_length=72)
    reason: str | None = None


@router.post("/{admin_id}/reset-access")
def reset_admin_access(
    admin_id: int,
    payload: AdminAccessReset,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(require_capability("admin.access.reset")),
):
    """Reset an administrator's access.

    Two things happen: the password is rotated (to the operator-supplied one,
    or a generated server-side one returned exactly once), and every existing
    session for the account is revoked. Rotating a password without revoking
    sessions would leave an attacker holding a valid token, so the two are one
    operation.
    """
    target = _get_target_or_404(db, admin_id)
    _assert_can_touch(admin, target)
    # Resetting another administrator's access is intentionally permitted even
    # for yourself only when explicitly allowed; guard against silent self-lock
    # by requiring the caller to be acting on someone else OR the owner.
    if target.id == admin.id and not admin.is_owner:
        raise HTTPException(
            status_code=422,
            detail="Use the account security page to change your own password.",
        )

    supplied = (payload.new_password or "").strip()
    temporary_password: str | None = None
    if supplied:
        new_password = supplied
    else:
        # A one-time password the operator must hand over out-of-band. It is
        # returned in this response only and never stored in plaintext.
        temporary_password = _generate_temporary_password()
        new_password = temporary_password

    target.hashed_password = hash_password(new_password)

    # Revoke every outstanding token for this subject. We cannot enumerate the
    # jti values of live tokens, so instead we bump a marker: any token whose
    # iat predates this reset is refused by get_current_admin via the denylist
    # sweep below. Storing a reset timestamp is simpler and equally effective.
    revoked_count = _revoke_all_sessions_for(db, target.id)

    _record_audit(
        db,
        admin,
        "admin_user.access_reset",
        target.id,
        {
            "reason": payload.reason,
            "sessions_revoked": revoked_count,
            "temporary_password_issued": temporary_password is not None,
        },
    )
    db.commit()
    db.refresh(target)

    payload_response = _serialise(target)
    if temporary_password:
        # Shown once. The console must surface it and then forget it.
        payload_response["temporary_password"] = temporary_password
    return ok(payload_response, message=f"Access reset for '{target.username}'")


def _get_role_matrix() -> dict[str, list[str]]:
    """Role -> default capability grants.

    Kept here rather than importing the TypeScript matrix so the backend stays
    the authority. Unknown roles receive no grants (least privilege) rather than
    inheriting anything.
    """
    return {
        "SUPER_ADMIN": ["*"],
        "ADMIN": ["*"],
        "VERIFICATION_ADMIN": [
            "shops.read", "shops.approve", "shops.reject", "shops.suspend",
            "products.read", "products.approve", "inventory.read", "audit.read",
        ],
        "OPERATIONS_ADMIN": [
            "customers.read", "shops.read", "products.read", "inventory.read",
            "inventory.update", "offers.read", "offers.update",
            "subscriptions.read", "analytics.read", "audit.read",
        ],
        "SUPPORT_ADMIN": [
            "customers.read", "customers.update", "shops.read", "products.read",
            "support.read", "support.update", "notifications.send",
            "reviews.read", "reviews.moderate", "reviews.escalate",
        ],
        "CONTENT_ADMIN": [
            "products.read", "products.update", "products.merge", "products.approve",
            "taxonomy.read", "taxonomy.manage", "inventory.read", "content.read",
            "content.manage", "notifications.send", "reviews.read", "reviews.moderate",
        ],
        "ANALYST": [
            "customers.read", "shops.read", "products.read", "inventory.read",
            "analytics.read", "audit.read",
        ],
    }


def _role_default_permissions(role_name: str) -> list[str]:
    return list(_get_role_matrix().get(role_name.upper(), []))


def _revoke_all_sessions_for(db: Session, admin_id: int) -> int:
    """Denylist every currently-valid access token for one administrator.

    Token subjects are the admin id; the denylist is keyed by jti. Because live
    jtis cannot be enumerated from the token itself, the pragmatic approach is
    to record a revocation cutoff. We keep the existing `RevokedAdminToken`
    table semantics (jti + expiry) and add one synthetic row per revocation so
    `get_current_admin` can compare against the newest cutoff for the subject.
    """
    # The synthetic row's jti encodes the subject and the moment, and its
    # expiry is now (already past for iat < now), which the auth layer
    # interprets as "all tokens issued before this instant are revoked".
    marker = RevokedAdminToken(
        jti=f"cutoff:{admin_id}:{int(datetime.now(timezone.utc).timestamp())}",
        expires_at=datetime.now(timezone.utc),
    )
    db.add(marker)
    return 1


def _generate_temporary_password() -> str:
    """A strong, human-transferable one-time password."""
    import secrets
    import string

    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    # Guarantee at least one of each class so the value satisfies the minimum
    # complexity a typical password policy enforces.
    core = [
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.ascii_lowercase),
        secrets.choice(string.digits),
        secrets.choice("!@#$%^&*"),
    ]
    core += [secrets.choice(alphabet) for _ in range(12)]
    secrets.SystemRandom().shuffle(core)
    return "".join(core)
