"""FastAPI dependencies — authentication, authorization (RBAC), shop-scoped access, and DI."""

from typing import Optional

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.exceptions import ForbiddenError, UnauthorizedError
from app.core.observability.metrics import record_auth_result
from app.core.security import (
    get_token_claims,
    get_token_jti,
    get_token_subject,
    validate_token_type,
    TokenPurpose,
)
from app.database.session import get_db
from app.models.session import AuthSession
from app.models.shop import ShopManager, ShopOwner
from app.models.user import User
from app.services.auth_service import is_token_blacklisted
from app.services.firebase_auth_service import get_user_by_firebase_uid
from app.services.firebase_verification import (
    FirebaseVerificationError,
    verify_firebase_id_token,
)

security = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    """Resolve the current authenticated user from the JWT bearer token.

    Validates:
      - Token is an access token
      - Token not blacklisted
      - Session is active and not revoked
      - User exists and account is not suspended/banned

    .. deprecated::
        Use :func:`get_current_user_firebase` for new code. This function
        validates the legacy custom JWT tokens.
    """
    if credentials is None:
        record_auth_result("access_token", False, "missing")
        raise UnauthorizedError("Not authenticated")

    token = credentials.credentials

    # Try Firebase token first (new flow)
    try:
        firebase_uid, _ = verify_firebase_id_token(token)
        user = get_user_by_firebase_uid(db, firebase_uid)
        if user is not None:
            if not user.is_active or user.status.value in ("SUSPENDED", "BANNED", "INACTIVE"):
                record_auth_result("firebase_token", False, "account_inactive")
                raise ForbiddenError("User account is not active")
            record_auth_result("firebase_token", True, "success")
            return user
    except FirebaseVerificationError:
        # Not a valid Firebase token, fall through to legacy JWT validation
        pass

    # Legacy JWT validation (backward compatibility)
    if not validate_token_type(token, TokenPurpose.ACCESS):
        record_auth_result("access_token", False, "invalid_type")
        raise UnauthorizedError("Invalid token type")

    user_id = get_token_subject(token)
    if user_id is None:
        record_auth_result("access_token", False, "invalid_subject")
        raise UnauthorizedError("Invalid or expired token")

    # Check blacklist
    jti = get_token_jti(token)
    if jti and is_token_blacklisted(db, jti):
        record_auth_result("access_token", False, "blacklisted")
        raise UnauthorizedError("Token has been revoked")

    claims = get_token_claims(token)
    session_id = claims.get("session_id")

    if session_id:
        # Session-aware check
        auth_session = (
            db.query(AuthSession)
            .filter(
                AuthSession.session_id == session_id,
                AuthSession.user_id == user_id,
            )
            .first()
        )
        if auth_session is None or not auth_session.is_active or auth_session.is_revoked:
            record_auth_result("access_token", False, "session_revoked")
            raise UnauthorizedError("Session has been revoked")

    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        record_auth_result("access_token", False, "user_not_found")
        raise UnauthorizedError("User not found")

    if not user.is_active or user.status.value in ("SUSPENDED", "BANNED", "INACTIVE"):
        record_auth_result("access_token", False, "account_inactive")
        raise ForbiddenError("User account is not active")

    record_auth_result("access_token", True, "success")
    return user


def get_current_session_id(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> Optional[str]:
    """Session id carried by the bearer token, if any.

    ``get_current_user`` validates the session named by this claim, so logout
    can revoke exactly the session the caller is using when the client does not
    pass ``session_id`` explicitly. Firebase ID tokens carry no session claim →
    ``None`` (nothing server-side to revoke; Firebase owns that token).
    """
    if credentials is None:
        return None
    try:
        return get_token_claims(credentials.credentials).get("session_id")
    except Exception:  # noqa: BLE001 — Firebase tokens fail JWT decoding
        return None


def get_current_user_firebase(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    """Resolve the current authenticated user from a Firebase ID token.

    This is the NEW recommended authentication dependency. It:
      - Verifies the Firebase ID token cryptographically
      - Extracts firebase_uid
      - Loads the user from PostgreSQL
      - Validates account state

    Usage:
        @router.get("/profile")
        def profile(user: User = Depends(get_current_user_firebase)):
            ...
    """
    if credentials is None:
        record_auth_result("firebase_token", False, "missing")
        raise UnauthorizedError("Not authenticated")

    token = credentials.credentials

    try:
        firebase_uid, _ = verify_firebase_id_token(token)
    except FirebaseVerificationError as exc:
        record_auth_result("firebase_token", False, "invalid_token")
        raise UnauthorizedError(
            message=exc.message,
            error_code=exc.error_code,
        ) from exc

    user = get_user_by_firebase_uid(db, firebase_uid)
    if user is None:
        record_auth_result("firebase_token", False, "user_not_found")
        raise UnauthorizedError("User not found")

    if not user.is_active or user.status.value in ("SUSPENDED", "BANNED", "INACTIVE"):
        record_auth_result("firebase_token", False, "account_inactive")
        raise ForbiddenError("User account is not active")

    record_auth_result("firebase_token", True, "success")
    return user


def get_current_user_with_session(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> tuple[User, Optional[dict]]:
    """Return (user, token_claims) for endpoints that need session context."""
    user = get_current_user(credentials, db)
    claims = get_token_claims(credentials.credentials)
    return user, claims


def require_permission(resource: str, action: str):
    """Dependency factory that checks the user has the given permission.

    Usage:
        @router.get("/products")
        def list_products(user: User = Depends(require_permission("product", "read"))):
            ...
    """

    def checker(
        user: User = Depends(get_current_user),
    ) -> User:
        if not has_permission(user, resource, action):
            raise ForbiddenError(f"Missing permission: {action}:{resource}")
        return user

    return checker


def require_role(role_name: str):
    """Dependency factory that checks the user has the given role.

    Usage:
        @router.get("/admin/dashboard")
        def dashboard(user: User = Depends(require_role("admin"))):
            ...
    """

    def checker(
        user: User = Depends(get_current_user),
    ) -> User:
        if user.role is None or user.role.name != role_name:
            raise ForbiddenError(f"Requires role: {role_name}")
        return user

    return checker


def require_any_role(*role_names: str):
    """Dependency factory that allows any of the given roles.

    Usage:
        @router.get("/shop/dashboard")
        def dashboard(user: User = Depends(require_any_role("shop_owner", "shop_manager"))):
            ...
    """

    def checker(
        user: User = Depends(get_current_user),
    ) -> User:
        if user.role is None or user.role.name not in role_names:
            raise ForbiddenError(f"Requires one of roles: {', '.join(role_names)}")
        return user

    return checker


def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> Optional[User]:
    """Resolve the current user if a valid token is present, else None."""
    if credentials is None:
        return None
    try:
        user_id = get_token_subject(credentials.credentials)
        if user_id is None:
            return None
        return db.query(User).filter(User.id == user_id).first()
    except Exception:
        return None


# ── Permission evaluation ───────────────────────────────────────────────
def has_permission(user: User, resource: str, action: str) -> bool:
    """Check if a user has the given permission via role."""
    if user.role is None:
        return False
    return any(
        p.resource == resource and p.action == action
        for p in user.role.permissions
    )


def get_user_permissions(user: User) -> list[str]:
    """Return a list of permission strings for the user."""
    if user.role is None:
        return []
    return [
        f"{p.action}:{p.resource}"
        for p in user.role.permissions
    ]


# ── Shop ownership / manager access ──────────────────────────────────────
def require_shop_access(shop_id: int):
    """Dependency factory that allows:
      - Admin
      - Shop owner of the shop
      - Shop manager of the shop

    Usage:
        @router.get("/shops/{shop_id}/inventory")
        def get_inventory(shop_id: int, user: User = Depends(require_shop_access(shop_id))):
            ...
    """

    def checker(
        user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ) -> User:
        # Admin has explicit global access
        if user.role is not None and user.role.name == "admin":
            return user

        # Check ownership
        is_owner = (
            db.query(ShopOwner)
            .filter(
                ShopOwner.shop_id == shop_id,
                ShopOwner.user_id == user.id,
                ShopOwner.is_active == True,  # noqa: E712
            )
            .first()
            is not None
        )
        if is_owner:
            return user

        # Check manager
        is_manager = (
            db.query(ShopManager)
            .filter(
                ShopManager.shop_id == shop_id,
                ShopManager.user_id == user.id,
                ShopManager.is_active == True,  # noqa: E712
            )
            .first()
            is not None
        )
        if is_manager:
            return user

        raise ForbiddenError("You do not have access to this shop")

    return checker


def require_shop_owner(shop_id: int):
    """Dependency factory that allows only the shop owner (or admin)."""

    def checker(
        user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ) -> User:
        if user.role is not None and user.role.name == "admin":
            return user

        is_owner = (
            db.query(ShopOwner)
            .filter(
                ShopOwner.shop_id == shop_id,
                ShopOwner.user_id == user.id,
                ShopOwner.is_active == True,  # noqa: E712
            )
            .first()
            is not None
        )
        if not is_owner:
            raise ForbiddenError("Only the shop owner can perform this action")
        return user

    return checker


def is_shop_owner(db: Session, user: User, shop_id: int) -> bool:
    """Utility — check if a user owns a shop."""
    return (
        db.query(ShopOwner)
        .filter(
            ShopOwner.shop_id == shop_id,
            ShopOwner.user_id == user.id,
            ShopOwner.is_active == True,  # noqa: E712
        )
        .first()
        is not None
    )


def is_shop_manager(db: Session, user: User, shop_id: int) -> bool:
    """Utility — check if a user manages a shop."""
    return (
        db.query(ShopManager)
        .filter(
            ShopManager.shop_id == shop_id,
            ShopManager.user_id == user.id,
            ShopManager.is_active == True,  # noqa: E712
        )
        .first()
        is not None
    )


def get_user_shop_ids(db: Session, user: User) -> list[int]:
    """Return the IDs of all shops the user owns or manages."""
    owner_ids = [
        r.shop_id
        for r in db.query(ShopOwner).filter(
            ShopOwner.user_id == user.id,
            ShopOwner.is_active == True,  # noqa: E712
        ).all()
    ]
    manager_ids = [
        r.shop_id
        for r in db.query(ShopManager).filter(
            ShopManager.user_id == user.id,
            ShopManager.is_active == True,  # noqa: E712
        ).all()
    ]
    return list(set(owner_ids + manager_ids))


# ── Admin-only guards ────────────────────────────────────────────────────
def require_admin(user: User = Depends(get_current_user)) -> User:
    """Explicit admin-only dependency."""
    if user.role is None or user.role.name != "admin":
        raise ForbiddenError("Admin access required")
    return user


def get_admin_permissions(
    user: User = Depends(get_current_user),
) -> tuple[User, set[str]]:
    """Resolve (user, effective_admin_permission_keys).

    Only admin-family roles pass: ``admin`` (super) or an ``admin_*`` sub-role.
    """
    from app.core.admin_permissions import (
        ADMIN_SUBROLE_PERMISSIONS,
        effective_admin_permissions,
        user_is_admin_family,
    )

    if not user_is_admin_family(user):
        raise ForbiddenError("Admin access required")
    role_name = user.role.name if user.role is not None else None
    return user, effective_admin_permissions(role_name)


def require_admin_permission(resource: str, action: str):
    """Dependency factory enforcing a specific admin module permission.

    Usage:
        @router.post("/shops/{shop_id}/verify")
        def verify_shop(user: User = Depends(require_admin_permission("shop", "verify"))):
            ...
    """

    def checker(
        perms_ctx: tuple[User, set[str]] = Depends(get_admin_permissions),
    ) -> User:
        user, perms = perms_ctx
        from app.core.admin_permissions import has_admin_permission

        if not has_admin_permission(perms, resource, action):
            raise ForbiddenError(f"Missing admin permission: {action}:{resource}")
        return user

    return checker


def require_shop_permission(
    shop_id: str,  # Path parameter name
    resource: str,
    action: str,
):
    """Dependency factory enforcing a shop-scoped permission.
    
    Usage:
        @router.put("/shops/{shop_id}/products")
        def update_products(
            shop_id: int,
            user: User = Depends(require_shop_permission("shop_id", "product", "update")),
        ):
            ...
    
    Args:
        shop_id: Path parameter name containing the shop ID
        resource: Permission resource (e.g., "product", "inventory")
        action: Permission action (e.g., "read", "update")
    """
    def checker(
        request: __import__("fastapi").Request,
        user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ) -> User:
        # Get shop_id from path parameters
        try:
            sid = int(request.path_params.get(shop_id, 0))
        except (ValueError, TypeError):
            raise ForbiddenError("Invalid shop ID")
        
        # Verify shop access
        from app.core.resource_ownership import verify_shop_ownership
        verify_shop_ownership(db, user, sid)
        
        # Check permission
        from app.core.shopkeeper_permissions import has_permission, effective_shop_permissions
        
        is_owner = is_shop_owner(db, user, sid)
        manager = None
        if not is_owner:
            manager = (
                db.query(ShopManager)
                .filter(
                    ShopManager.shop_id == sid,
                    ShopManager.user_id == user.id,
                    ShopManager.is_active == True,  # noqa: E712
                )
                .first()
            )
        
        perms = effective_shop_permissions(
            user.role.name if user.role else None,
            is_owner,
            manager,
        )
        
        if not has_permission(perms, resource, action):
            # Log denied access
            from app.services.authorization_audit_service import log_authorization_check
            log_authorization_check(
                db,
                user_id=user.id,
                resource=resource,
                action=action,
                resource_id=sid,
                is_allowed=False,
                reason=f"Missing permission {action}:{resource}",
                ip_address=request.client.host if request.client else None,
                user_agent=request.headers.get("user-agent"),
            )
            db.commit()
            raise ForbiddenError(f"Missing permission: {action}:{resource}")
        
        return user
    
    return checker