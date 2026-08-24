from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import UnauthorizedError
from app.core.logging import get_logger
from app.core.rate_limit import auth_rate_limit
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.customer import Customer
from app.models.role import Role
from app.models.user import User, UserStatus
from app.schemas.auth import (
    LogoutRequest,
    RefreshTokenRequest,
    RegisterRequest,
    SendOTPRequest,
    VerifyOTPRequest,
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
from app.services.otp_service import (
    OTPCooldownError,
    OTPLimitExceeded,
    clear_otp,
    generate_otp,
    verify_otp,
)

logger = get_logger("app.api.auth")

router = APIRouter(prefix="/auth", tags=["auth"])


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
async def send_otp(payload: SendOTPRequest, request: Request):
    """Send OTP to the user's phone number with retry/cooldown limits."""
    try:
        result = generate_otp(payload.phone_number)
    except OTPCooldownError as exc:
        return error_response(
            message=exc.message,
            error_code="OTP_COOLDOWN",
            status_code=429,
            data={"retry_after_seconds": exc.retry_after_seconds},
        )
    except OTPLimitExceeded as exc:
        return error_response(
            message=exc.message,
            error_code="OTP_RESEND_LIMIT_REACHED",
            status_code=429,
        )

    return success_response(
        data=result,
        message="OTP sent successfully",
    )


@router.post("/verify-otp")
@auth_rate_limit()
async def verify_otp_endpoint(
    payload: VerifyOTPRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Verify OTP and issue access + refresh tokens.

    Creates a new user if one doesn't exist (phone-based registration).
    Assigns the default 'customer' role to new signups.
    """
    # Verify OTP (handles expiry, max attempts, correct/incorrect)
    if not verify_otp(payload.phone_number, payload.otp):
        return error_response(
            message="Invalid or expired OTP",
            error_code="INVALID_OTP",
            status_code=400,
        )

    # Normalize phone for lookup (matches OTP service normalization)
    phone = payload.phone_number.strip()
    if not phone.startswith("+"):
        phone = "+" + phone

    user = db.query(User).filter(User.phone_number == phone).first()

    if user is None:
        # ── Phone-based registration ──────────────────────────────────────
        default_role = _default_role(db)
        user = User(
            phone_number=phone,
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
    else:
        # ── Existing user ─────────────────────────────────────────────────
        if not is_account_allowed(user):
            clear_otp(phone)  # Invalidate OTP
            return error_response(
                message="Account is not active",
                error_code="ACCOUNT_NOT_ACTIVE",
                status_code=403,
            )

        # Refresh profile on re-login
        if user.customer_profile is None:
            customer = Customer(user_id=user.id)
            db.add(customer)
            db.flush()

    # Issue tokens with session
    meta = _get_client_meta(request)
    token_data = issue_tokens(
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

    db.commit()

    return success_response(
        data=token_data,
        message="Login successful",
    )


@router.post("/register")
@auth_rate_limit()
async def register_endpoint(
    payload: RegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Register a new customer account with a display name.

    Verifies the OTP, creates the user (with the chosen name) and the
    customer profile, then issues access + refresh tokens. Existing
    accounts are rejected — they must sign in via /verify-otp instead.
    """
    # Verify OTP (handles expiry, max attempts, correct/incorrect)
    if not verify_otp(payload.phone_number, payload.otp):
        return error_response(
            message="Invalid or expired OTP",
            error_code="INVALID_OTP",
            status_code=400,
        )

    # Normalize phone for lookup (matches OTP service normalization)
    phone = payload.phone_number.strip()
    if not phone.startswith("+"):
        phone = "+" + phone

    user = db.query(User).filter(User.phone_number == phone).first()

    if user is not None:
        clear_otp(phone)  # OTP was consumed; invalidate it either way
        return error_response(
            message="Account already exists. Please sign in instead.",
            error_code="ACCOUNT_EXISTS",
            status_code=409,
        )

    # ── Create the account with the provided display name ────────────────
    default_role = _default_role(db)
    user = User(
        phone_number=phone,
        name=payload.name.strip(),
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

    # Issue tokens with session
    meta = _get_client_meta(request)
    token_data = issue_tokens(
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

    db.commit()

    return success_response(
        data=token_data,
        message="Registration successful",
    )


@router.post("/resend-otp")
@auth_rate_limit()
async def resend_otp_endpoint(payload: SendOTPRequest, request: Request):
    """Resend OTP with cooldown and resend-limit enforcement."""
    try:
        result = generate_otp(payload.phone_number)
    except OTPCooldownError as exc:
        return error_response(
            message=exc.message,
            error_code="OTP_COOLDOWN",
            status_code=429,
            data={"retry_after_seconds": exc.retry_after_seconds},
        )
    except OTPLimitExceeded as exc:
        return error_response(
            message=exc.message,
            error_code="OTP_RESEND_LIMIT_REACHED",
            status_code=429,
        )

    return success_response(
        data=result,
        message="OTP resent successfully",
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
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )

    db.commit()
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