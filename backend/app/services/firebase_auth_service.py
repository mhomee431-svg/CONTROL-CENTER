"""Firebase Authentication service ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â user provisioning and session management.

This service handles the full Firebase authentication flow:
1. Verify Firebase ID token (via Firebase Admin SDK)
2. Extract firebase_uid and phone_number
3. Find or create the application user
4. Return user context with role and permissions

This replaces the dual-token system with Firebase as the single source of truth
for authentication, while PostgreSQL remains the source of truth for
authorization (roles, permissions, business memberships).
"""
import logging
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy.orm import Session

from app.core.exceptions import ForbiddenError, UnauthorizedError
from app.core.logging import get_logger
from app.models.role import Role
from app.models.user import User, UserStatus
from app.services.firebase_verification import (
    FirebaseVerificationError,
    verify_firebase_id_token,
)

logger = get_logger("app.services.firebase_auth")


class FirebaseAuthResult:
    """Result of a successful Firebase authentication."""

    def __init__(
        self,
        user: User,
        firebase_uid: str,
        phone_number: str,
        is_new_user: bool = False,
    ):
        self.user = user
        self.firebase_uid = firebase_uid
        self.phone_number = phone_number
        self.is_new_user = is_new_user

    def to_context_dict(self) -> dict:
        """Convert to API response dict."""
        return {
            "user": {
                "id": self.user.id,
                "firebase_uid": self.firebase_uid,
                "phone_number": self.phone_number,
                "name": self.user.name,
                "email": self.user.email,
                "status": self.user.status.value,
                "role": self.user.role.name if self.user.role else None,
            },
            "is_new_user": self.is_new_user,
        }


def _get_or_create_role(db: Session, role_name: str) -> Optional[Role]:
    """Get a role by name, creating it if it doesn't exist."""
    role = db.query(Role).filter(Role.name == role_name).first()
    if role is None:
        role = Role(name=role_name, description=f"{role_name} role")
        db.add(role)
        db.flush()
        logger.info("Created role: %s", role_name)
    return role


def _find_user_by_firebase_uid(db: Session, firebase_uid: str) -> Optional[User]:
    """Find a user by their Firebase UID."""
    return db.query(User).filter(User.firebase_uid == firebase_uid).first()


def _find_user_by_phone(db: Session, phone_number: str) -> Optional[User]:
    """Find a user by their phone number (legacy lookup for migration)."""
    if not phone_number:
        return None
    return db.query(User).filter(User.phone_number == phone_number).first()


def _create_user(
    db: Session,
    firebase_uid: str,
    phone_number: str,
    name: Optional[str] = None,
    role_name: str = "customer",
) -> User:
    """Create a new application user with the given Firebase UID."""
    role = _get_or_create_role(db, role_name)

    user = User(
        firebase_uid=firebase_uid,
        phone_number=phone_number,
        name=name,
        role_id=role.id if role else None,
        status=UserStatus.ACTIVE,
        is_active=True,
    )
    db.add(user)
    db.flush()

    # Create customer profile for customer role
    if role_name == "customer":
        from app.models.customer import Customer

        customer = Customer(user_id=user.id)
        db.add(customer)
        db.flush()

    logger.info(
        "Created new user: id=%s, firebase_uid=%s, role=%s",
        user.id,
        firebase_uid,
        role_name,
    )
    return user


def _update_user_login_metadata(user: User, ip_address: Optional[str] = None) -> None:
    """Update user's last login metadata."""
    user.last_login_at = datetime.now(timezone.utc)
    user.last_login_ip = ip_address


# ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ Self-service roles a client may request at sign-up ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬ÃƒÂ¢Ã¢â‚¬ÂÃ¢â€šÂ¬
#
# Anything NOT in this set is downgraded to "customer". Notably absent:
# "admin", "superadmin", "super_admin", "staff" ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â those are granted by an
# authenticated admin action, never by a signup payload.
SELF_SERVICE_ROLES: frozenset[str] = frozenset(
    {
        "customer",
        "shopkeeper",
        "shop_owner",
        "shop_manager",
    }
)

DEFAULT_ROLE = "customer"


def sanitise_requested_role(requested_role: Optional[str]) -> str:
    """Reduce an untrusted client-supplied role to a permitted self-service tier.

    Returns [DEFAULT_ROLE] for anything unrecognised rather than raising: a bad
    or hostile value should not be able to *break* sign-up, only fail to
    escalate. Logging the attempt is deliberate ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â a client repeatedly asking for
    "admin" is a signal worth having.
    """
    if not requested_role:
        return DEFAULT_ROLE

    candidate = str(requested_role).strip().lower()
    if candidate in SELF_SERVICE_ROLES:
        return candidate

    logger.warning(
        "Rejected client-requested role %r at sign-up; downgraded to %r",
        requested_role,
        DEFAULT_ROLE,
    )
    return DEFAULT_ROLE


def authenticate_with_firebase(
    db: Session,
    firebase_id_token: str,
    ip_address: Optional[str] = None,
    requested_role: Optional[str] = None,
    name: Optional[str] = None,
) -> FirebaseAuthResult:
    """Authenticate a user with a Firebase ID token.

    This is the main entry point for Firebase authentication. It:
    1. Verifies the Firebase ID token cryptographically
    2. Extracts firebase_uid and phone_number
    3. Finds or creates the application user
    4. Validates account status
    5. Returns the user context

    Args:
        db: Database session
        firebase_id_token: The Firebase ID token from the client
        ip_address: Client IP for audit logging
        requested_role: Role to assign for new users (default: 'customer')
        name: Display name for new users

    Returns:
        FirebaseAuthResult with user context

    Raises:
        UnauthorizedError: If token is invalid or user not found/created
        ForbiddenError: If user account is suspended/banned
    """
    # Step 1: Verify Firebase ID token
    try:
        firebase_uid, phone_number = verify_firebase_id_token(firebase_id_token)
    except FirebaseVerificationError as exc:
        raise UnauthorizedError(
            message=exc.message,
            code=exc.error_code,
        ) from exc

    # Step 2: Find existing user by firebase_uid
    user = _find_user_by_firebase_uid(db, firebase_uid)

    is_new_user = False

    if user is None:
        # Step 3a: Migration path ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â try to find by phone number
        # This handles existing users who authenticated before firebase_uid was added
        if phone_number:
            user = _find_user_by_phone(db, phone_number)
            if user:
                # Link the Firebase UID to the existing user
                user.firebase_uid = firebase_uid
                db.flush()
                logger.info(
                    "Linked firebase_uid %s to existing user %s (matched by phone)",
                    firebase_uid,
                    user.id,
                )

        # Step 3b: Still no user ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â create a new one
        if user is None:
            # SECURITY: `requested_role` arrives in the request body, i.e. from
            # the client, and is therefore UNTRUSTED INPUT. It is NOT a
            # request for elevated access ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â it only lets the client say which
            # self-service tier it wants (a shopkeeper signing up for their own
            # shop is legitimate). Any role outside the self-service set is
            # silently downgraded to "customer".
            #
            # Without this allowlist, anyone could POST
            # {"firebase_id_token": "<valid token>", "requested_role": "admin"}
            # and be handed a fresh admin account: full privilege escalation
            # from an unauthenticated sign-up. Elevated roles are granted by an
            # admin action, never by a field in a request body.
            role_name = sanitise_requested_role(requested_role)
            user = _create_user(
                db=db,
                firebase_uid=firebase_uid,
                phone_number=phone_number,
                name=name,
                role_name=role_name,
            )
            is_new_user = True

    # Step 4: Validate account status
    if not user.is_active or user.status in (
        UserStatus.SUSPENDED,
        UserStatus.BANNED,
        UserStatus.INACTIVE,
    ):
        raise ForbiddenError(
            message="Account is not active",
            code="ACCOUNT_NOT_ACTIVE",
        )

    # Step 5: Update login metadata
    _update_user_login_metadata(user, ip_address)

    db.commit()

    return FirebaseAuthResult(
        user=user,
        firebase_uid=firebase_uid,
        phone_number=phone_number,
        is_new_user=is_new_user,
    )


def get_user_by_firebase_uid(db: Session, firebase_uid: str) -> Optional[User]:
    """Get a user by Firebase UID (for dependency injection)."""
    return _find_user_by_firebase_uid(db, firebase_uid)
