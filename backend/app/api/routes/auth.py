from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import UnauthorizedError
from app.core.logging import get_logger
from app.core.observability.metrics import record_auth_result
from app.core.rate_limit import auth_rate_limit
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.customer import Customer
from app.models.role import Role
from app.models.user import User, UserStatus
from app.schemas.auth import (
    CustomerFirebaseAuthRequest,
    LogoutRequest,
    RefreshTokenRequest,
    SendOTPRequest,
)
from app.services.auth_service import (
    get_account_status,
    get_active_sessions,
    issue_tokens,
    is_account_allowed,
    logout_session,
    refresh_session,
    revoke_session_by_id,
)
from app.services.firebase_verification import (
    FirebaseVerificationError,
    verify_firebase_id_token,
)

logger = get_logger("app.api.auth")

router = APIRouter(prefix="/auth", tags=["auth"])


def _verify_customer_firebase_token(payload: CustomerFirebaseAuthRequest, operation: str):
    """Verify the Firebase ID token → return (phone, None) or (None, error_response)."""
    try:
        phone = verify_firebase_id_token(payload.firebase_id_token)
    except FirebaseVerificationError as exc:
        record_auth_result(operation, False, "firebase_verification_failed")
        return None, error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )
    return phone, None


def _default_role(db: Session) -> Role | None:
    """Return the default 'customer' role for new signups."""
    return db.query(Role).filter(Role.name == "customer").first()


def _get_client_meta(request: Request) -> dict:
    """Extract device / request metadata."""
    return {
        "ip_address": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
    }


@router.post("/send-otp")
@auth_rate_limit()
async def send_otp(
    payload: SendOTPRequest,
    request: Request,
):
    """Acknowledge an OTP request.

    OTP delivery is handled by Firebase Phone Auth on the client — the Flutter
    app calls ``firebase_auth`` directly and Google sends the SMS. This endpoint
    remains for API-contract compatibility so older clients do not break; it
    simply acknowledges the request (no third-party SMS gateway involved).
    """
    record_auth_result("otp", True, "firebase_client_delivery")
    return success_response(
        data={"delivered_by": "firebase"},
        message="OTP delivery is handled by Firebase Phone Auth",
    )


def _create_customer_account(db: Session, phone: str, name: str | None) -> User:
    """Create a new customer user (+ profile) with the default 'customer' role."""
    default_role = _default_role(db)
    user = User(
        phone_number=phone,
        name=(name.strip() if name and name.strip() else None),
        role_id=default_role.id if default_role else None,
        status=UserStatus.ACTIVE,
        is_active=True,
    )
    db.add(user)
    db.flush()

    # Create customer profile
    customer = Customer(user_id=user.id)
    db.add(customer)
    db.flush()
    return user


def _issue_customer_tokens(
    db: Session,
    user: User,
    payload: CustomerFirebaseAuthRequest,
    request: Request,
) -> dict:
    """Issue access + refresh tokens bound to a new session."""
    meta = _get_client_meta(request)
    return issue_tokens(
        user,
        db,
        device_id=payload.device_id,
        device_name=payload.device_name,
        device_type=payload.device_type,
        platform=payload.platform,
        app_version=payload.app_version,
        ip_address=meta["ip_address"],
        user_agent=meta["user_agent"],
    )


@router.post("/firebase-login")
@auth_rate_limit()
async def firebase_login(
    payload: CustomerFirebaseAuthRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Combined Firebase login-or-register endpoint for the Customer App.

    The Flutter app completes the phone-OTP flow client-side with
    ``firebase_auth`` and sends the resulting Firebase ID token here.

    Flow:
      1. Verify the Firebase ID token (confirms the phone belongs to the user).
      2. Extract the phone number from the verified token.
      3. Look up the user by phone in PostgreSQL.
      4. If found and active → issue JWT session tokens (login).
      5. If not found → auto-register a new customer account, then login.
         (``name`` is required when auto-registering.)

    This "login on first use" pattern is the standard for phone-auth apps.
    """
    phone, err = _verify_customer_firebase_token(payload, "customer_firebase_login")
    if err is not None:
        return err

    user = db.query(User).filter(User.phone_number == phone).first()

    if user is None:
        if not payload.name or not payload.name.strip():
            return error_response(
                message="Name is required for new account registration",
                error_code="NAME_REQUIRED",
                status_code=400,
            )
        user = _create_customer_account(db, phone, payload.name)
        is_new_account = True
        record_auth_result("customer_firebase_login", True, "auto_registered")
    else:
        is_new_account = False
        if not is_account_allowed(user):
            record_auth_result("customer_firebase_login", False, "account_inactive")
            return error_response(
                message="Account is not active",
                error_code="ACCOUNT_NOT_ACTIVE",
                status_code=403,
            )
        # Refresh profile on re-login
        if user.customer_profile is None:
            db.add(Customer(user_id=user.id))
            db.flush()
        record_auth_result("customer_firebase_login", True, "login_success")

    token_data = _issue_customer_tokens(db, user, payload, request)
    db.commit()

    return success_response(
        data={
            **token_data,
            "is_new_account": is_new_account,
        },
        message="Account created and logged in" if is_new_account else "Login successful",
    )


@router.post("/verify-otp")
@auth_rate_limit()
async def verify_otp_endpoint(
    payload: CustomerFirebaseAuthRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Firebase-phone-OTP login for an EXISTING account via the Customer App.

    The Flutter app completes the OTP flow client-side with ``firebase_auth``
    and sends the resulting Firebase ID token here. We verify it to extract
    the phone number and look up the user. New users must register via
    /register or /firebase-login instead.
    """
    phone, err = _verify_customer_firebase_token(payload, "customer_login")
    if err is not None:
        return err

    user = db.query(User).filter(User.phone_number == phone).first()

    if user is None:
        record_auth_result("customer_login", False, "account_not_found")
        return error_response(
            message="Account not found. Please register first.",
            error_code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )

    if not is_account_allowed(user):
        record_auth_result("customer_login", False, "account_inactive")
        return error_response(
            message="Account is not active",
            error_code="ACCOUNT_NOT_ACTIVE",
            status_code=403,
        )

    # Refresh profile on re-login
    if user.customer_profile is None:
        db.add(Customer(user_id=user.id))
        db.flush()

    token_data = _issue_customer_tokens(db, user, payload, request)
    db.commit()

    record_auth_result("customer_login", True, "success")
    return success_response(
        data=token_data,
        message="Login successful",
    )


@router.post("/register")
@auth_rate_limit()
async def register_endpoint(
    payload: CustomerFirebaseAuthRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Register a new customer account with a display name.

    Verifies the Firebase ID token, creates the user (with the chosen name)
    and the customer profile, then issues access + refresh tokens. Existing
    accounts are rejected — they must sign in via /verify-otp instead.
    """
    phone, err = _verify_customer_firebase_token(payload, "customer_register")
    if err is not None:
        return err

    user = db.query(User).filter(User.phone_number == phone).first()
    if user is not None:
        record_auth_result("customer_register", False, "account_exists")
        return error_response(
            message="Account already exists. Please sign in instead.",
            error_code="ACCOUNT_EXISTS",
            status_code=409,
        )

    if not payload.name or not payload.name.strip():
        return error_response(
            message="Name is required for registration",
            error_code="NAME_REQUIRED",
            status_code=400,
        )

    user = _create_customer_account(db, phone, payload.name)

    token_data = _issue_customer_tokens(db, user, payload, request)
    db.commit()

    record_auth_result("customer_register", True, "register_success")
    return success_response(
        data=token_data,
        message="Registration successful",
    )


@router.post("/resend-otp")
@auth_rate_limit()
async def resend_otp_endpoint(
    payload: SendOTPRequest,
    request: Request,
):
    """Acknowledge an OTP resend request.

    Resend throttling is enforced by Firebase Phone Auth on the client; the
    backend no longer sends any SMS.
    """
    return success_response(
        data={"delivered_by": "firebase"},
        message="OTP delivery is handled by Firebase Phone Auth",
    )


@router.post("/refresh")
@auth_rate_limit()
async def refresh_token(
    payload: RefreshTokenRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Rotate refresh token and issue new access + refresh tokens.

    Implements:
      - Token rotation
      - Reuse detection (replayed tokens revoke the session)
      - Session / expiry validation
    """
    try:
        token_data = refresh_session(
            db,
            payload.refresh_token,
            device_id=payload.device_id,
        )
    except UnauthorizedError as exc:
        db.rollback()
        record_auth_result("refresh_token", False, "invalid_refresh")
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )

    db.commit()
    record_auth_result("refresh_token", True, "success")
    return success_response(
        data=token_data,
        message="Token refreshed",
    )


@router.post("/logout")
async def logout(
    payload: LogoutRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke the current session (or specify session_id / revoke_all)."""
    try:
        if payload.revoke_all:
            result = logout_session(db, current_user, revoke_all=True)
        else:
            result = logout_session(
                db,
                current_user,
                session_id=payload.session_id,
            )
    except UnauthorizedError as exc:
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )

    db.commit()
    return success_response(data=result, message="Logged out successfully")


# ── Session management ──────────────────────────────────────────────────
@router.get("/sessions")
async def list_sessions(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List all active sessions for the current user."""
    sessions = get_active_sessions(db, current_user.id)
    return success_response(data={"sessions": sessions})


@router.delete("/sessions/{session_id}")
async def revoke_session(
    session_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke a specific session (device) for the current user."""
    revoked = revoke_session_by_id(db, current_user.id, session_id)
    if not revoked:
        return error_response(
            message="Session not found",
            error_code="SESSION_NOT_FOUND",
            status_code=404,
        )
    db.commit()
    return success_response(data={"revoked": True}, message="Session revoked")


@router.delete("/sessions")
async def revoke_all_sessions(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke all sessions for the current user."""
    result = logout_session(db, current_user, revoke_all=True)
    db.commit()
    return success_response(data=result, message="All sessions revoked")


# ── Account status ──────────────────────────────────────────────────────
@router.get("/account-status")
async def account_status(
    current_user: User = Depends(get_current_user),
):
    """Get the current user's account status."""
    return success_response(data=get_account_status(current_user))