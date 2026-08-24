"""Phase 22 — Shopkeeper App authentication routes (/shopkeeper/auth/*).

Separate from the customer /auth/* routes so the two apps never share
business flows:
  - Registration assigns the ``shopkeeper`` role and creates NO customer
    profile.
  - Login is OTP-based for existing accounts of any role (an account may
    be both a customer and a shopkeeper); authorization to business data
    is decided per-shop by association, not by role.
"""

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import AppError
from app.core.rate_limit import auth_rate_limit
from app.core.responses import error_response, success_response
from app.core.shopkeeper_permissions import SHOPKEEPER_PERMISSIONS
from app.database.session import get_db
from app.models.role import Role
from app.models.user import User, UserStatus
from app.schemas.shopkeeper import (
    ShopkeeperLoginRequest,
    ShopkeeperLogoutRequest,
    ShopkeeperRefreshRequest,
    ShopkeeperRegisterRequest,
    ShopkeeperSendOTPRequest,
)
from app.services import shopkeeper_service
from app.services.auth_service import issue_tokens, logout_session, refresh_session
from app.services.otp_service import (
    OTPCooldownError,
    OTPLimitExceeded,
    generate_otp,
    verify_otp,
)

router = APIRouter(prefix="/shopkeeper/auth", tags=["shopkeeper-auth"])


def _normalize_phone(raw: str) -> str:
    phone = raw.strip()
    return phone if phone.startswith("+") else f"+{phone}"


def _client_meta(request: Request) -> dict:
    return {
        "ip_address": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
    }


@router.post("/send-otp")
@auth_rate_limit()
async def send_otp(payload: ShopkeeperSendOTPRequest, request: Request):
    """Send a login/registration OTP to the shopkeeper's phone."""
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
    return success_response(data=result, message="OTP sent successfully")


@router.post("/register")
@auth_rate_limit()
async def register(
    payload: ShopkeeperRegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Register a NEW shopkeeper account (phone + OTP + name)."""
    if not verify_otp(payload.phone_number, payload.otp):
        return error_response(
            message="Invalid or expired OTP",
            error_code="INVALID_OTP",
            status_code=400,
        )

    phone = _normalize_phone(payload.phone_number)
    existing = db.query(User).filter(User.phone_number == phone).first()
    if existing is not None:
        return error_response(
            message="Account already exists. Please sign in instead.",
            error_code="ACCOUNT_EXISTS",
            status_code=409,
        )

    user = shopkeeper_service.create_shopkeeper_account(
        db, phone_number=phone, name=payload.name, email=payload.email
    )

    meta = _client_meta(request)
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
        data={
            **token_data,
            "shops": [],
            "permissions": sorted(f"{a}:{r}" for r, a in SHOPKEEPER_PERMISSIONS),
        },
        message="Shopkeeper registration successful",
    )


@router.post("/login")
@auth_rate_limit()
async def login(
    payload: ShopkeeperLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Sign an EXISTING account into the Shopkeeper App via OTP."""
    if not verify_otp(payload.phone_number, payload.otp):
        return error_response(
            message="Invalid or expired OTP",
            error_code="INVALID_OTP",
            status_code=400,
        )

    phone = _normalize_phone(payload.phone_number)
    user = db.query(User).filter(User.phone_number == phone).first()
    if user is None:
        return error_response(
            message="No account found. Please register first.",
            error_code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )
    if not user.is_active or user.status in (UserStatus.SUSPENDED, UserStatus.BANNED):
        return error_response(
            message="Account is not active",
            error_code="ACCOUNT_NOT_ACTIVE",
            status_code=403,
        )

    meta = _client_meta(request)
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

    shops = shopkeeper_service.list_authorized_shops(db, user)
    return success_response(data={**token_data, "shops": shops}, message="Login successful")



@router.post("/refresh")
async def refresh_token(
    payload: ShopkeeperRefreshRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Rotate refresh token (same secure rotation as the customer flow)."""
    try:
        token_data = refresh_session(db, payload.refresh_token, device_id=payload.device_id)
    except AppError as exc:
        db.rollback()
        return error_response(
            message=exc.message, error_code=exc.error_code, status_code=exc.status_code
        )
    db.commit()
    return success_response(data=token_data, message="Token refreshed")


@router.post("/logout")
async def logout(
    payload: ShopkeeperLogoutRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke the current session (or all sessions with revoke_all)."""
    result = logout_session(
        db,
        current_user,
        session_id=payload.session_id,
        revoke_all=payload.revoke_all,
    )
    db.commit()
    return success_response(data=result, message="Logged out successfully")


@router.get("/me")
async def me(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Current shopkeeper identity, authorized shops and permissions."""
    role = current_user.role
    shops = shopkeeper_service.list_authorized_shops(db, current_user)
    return success_response(
        data={
            "id": current_user.id,
            "name": current_user.name,
            "phone_number": current_user.phone_number,
            "email": current_user.email,
            "status": getattr(current_user.status, "value", str(current_user.status)),
            "role": role.name if role else None,
            "is_shopkeeper": bool(shops) or (role is not None and role.name == "shopkeeper"),
            "shops": shops,
        },
        message="OK",
    )

