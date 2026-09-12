"""Phase 22+ — Shopkeeper App authentication routes (/shopkeeper/auth/*).

Separate from the customer /auth/* routes so the two apps never share
business flows:
  - Registration assigns the ``shopkeeper`` role and creates NO customer
    profile.
  - Supports both password-based and OTP-based login.
  - OTP is delivered by Firebase Phone Auth (client-side); the backend only
    verifies the Firebase ID token — no Fast2SMS / third-party SMS gateway.
  - Authorization to business data is decided per-shop by association,
    not by role.
"""

from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import AppError, ForbiddenError, UnauthorizedError
from app.core.logging import get_logger
from app.core.observability.metrics import record_auth_result
from app.core.rate_limit import auth_rate_limit
from app.core.responses import error_response, success_response
from app.core.security import hash_password, verify_password
from app.core.shopkeeper_permissions import ensure_shopkeeper_role
from app.database.session import get_db
from app.models.role import Role
from app.models.user import User, UserStatus
from app.schemas.shopkeeper import (
    ShopkeeperFirebaseLoginRequest,
    ShopkeeperForgotPasswordRequest,
    ShopkeeperLoginRequest,
    ShopkeeperLogoutRequest,
    ShopkeeperOTPLoginRequest,
    ShopkeeperRefreshRequest,
    ShopkeeperRegisterRequest,
    ShopkeeperResetPasswordRequest,
    ShopkeeperSendOTPRequest,
)
from app.services import shopkeeper_service
from app.services.auth_service import (
    is_account_allowed,
    issue_tokens,
    logout_session,
)
from app.services.firebase_auth_service import authenticate_with_firebase
from app.services.firebase_verification import (
    FirebaseVerificationError,
    verify_firebase_id_token,
)

logger = get_logger("app.api.shopkeeper_auth")

router = APIRouter(prefix="/shopkeeper/auth", tags=["shopkeeper-auth"])


def _normalize_phone(raw: str) -> str:
    phone = raw.strip()
    return phone if phone.startswith("+") else f"+{phone}"


def _normalize_identifier(identifier: str) -> str:
    """Normalize email or phone identifier."""
    identifier = identifier.strip().lower()
    if "@" in identifier:
        return identifier
    if identifier.startswith("+"):
        return "+" + "".join(c for c in identifier[1:] if c.isdigit())
    return "".join(c for c in identifier if c.isdigit())


def _client_meta(request: Request) -> dict:
    return {
        "ip_address": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
    }


def _build_login_response(user: User, token_data: dict, shops: list) -> dict:
    """Build standardized login response."""
    return {
        "access_token": token_data["access_token"],
        "refresh_token": token_data["refresh_token"],
        "token_type": "bearer",
        "expires_in": token_data.get("expires_in", 1800),
        "session_id": token_data.get("session_id"),
        "user": {
            "id": user.id,
            "name": user.name,
            "phone_number": user.phone_number,
            "email": user.email,
            "status": user.status.value,
            "role": user.role.name if user.role else None,
            "business_id": user.business_id,
        },
        "business_id": user.business_id,
        "shops": shops,
    }


@router.post("/send-otp")
@auth_rate_limit()
async def send_otp(payload: ShopkeeperSendOTPRequest, request: Request):
    """OTP delivery is handled by Firebase Phone Auth on the client.

    This endpoint remains for API-contract compatibility but no longer sends
    an SMS — the Flutter app calls ``firebase_auth`` directly. It simply
    acknowledges the request so older clients do not break.
    """
    record_auth_result("shopkeeper_otp", True, "client_side")
    return success_response(
        message="OTP delivery is handled by Firebase Phone Auth on the client"
    )


def _extract_bearer_token(request: Request) -> str | None:
    """Extract the raw token from an ``Authorization: Bearer <token>`` header."""
    header = request.headers.get("authorization") or ""
    if header.lower().startswith("bearer "):
        token = header[7:].strip()
        return token or None
    return None


@router.post("/verify-phone")
@auth_rate_limit()
async def verify_phone(
    request: Request,
    db: Session = Depends(get_db),
):
    """Verify a Firebase ID token and return the login payload or a new-user
    handoff (shopkeeper scope).

    The Flutter app completes the phone-OTP flow client-side with
    ``firebase_auth`` and forwards the resulting Firebase ID token in the
    ``Authorization: Bearer <token>`` header. We verify it to extract the
    stable ``firebase_uid`` and the phone number, then:

      - If a shopkeeper user with that ``firebase_uid`` (or phone) exists and
        is active → issue JWT session tokens (login).
      - Otherwise → return ``is_new_user`` so the client can collect the
        profile (name) and call ``/register``.
    """
    token = _extract_bearer_token(request)
    if not token:
        record_auth_result("shopkeeper_verify_phone", False, "missing_token")
        return error_response(
            "Authorization header with a Firebase ID token is required",
            "TOKEN_REQUIRED",
            401,
        )

    try:
        firebase_uid, phone = verify_firebase_id_token(token)
    except FirebaseVerificationError as exc:
        record_auth_result("shopkeeper_verify_phone", False, "token_invalid")
        return error_response(exc.message, exc.error_code, exc.status_code)

    user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
    if user is None and phone:
        user = db.query(User).filter(User.phone_number == phone).first()

    if user is None:
        record_auth_result("shopkeeper_verify_phone", True, "new_user")
        return success_response(
            data={
                "is_new_user": True,
                "firebase_uid": firebase_uid,
                "phone_number": phone,
            },
            message="New user — complete your profile to register",
        )

    if not is_account_allowed(user):
        record_auth_result("shopkeeper_verify_phone", False, "account_inactive")
        return error_response(
            "Account is not active", "ACCOUNT_NOT_ACTIVE", 403
        )

    meta = _client_meta(request)
    token_data = issue_tokens(
        user,
        db,
        ip_address=meta["ip_address"],
        user_agent=meta["user_agent"],
    )
    db.commit()
    shops = shopkeeper_service.list_authorized_shops(db, user)
    record_auth_result("shopkeeper_verify_phone", True, "login_success")
    return success_response(
        data={
            **token_data,
            "shops": shops,
            "is_new_user": False,
        },
        message="Login successful",
    )


@router.post("/register")
@auth_rate_limit()
async def register(
    payload: ShopkeeperRegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Register a NEW shopkeeper account.

    NOTE: Firebase phone-OTP verification is currently DISABLED (commented
    out below) for the interim simple-login phase. Registration now takes
    phone_number + password directly. Re-enable the Firebase block when the
    OTP flow is switched back on.
    """
    client_ip = request.client.host if request.client else None

    phone = (payload.phone_number or "").strip()
    name = (payload.name or "").strip()

    if not phone:
        record_auth_result("shopkeeper_register", False, "phone_required")
        return error_response(
            "Phone number is required", "PHONE_REQUIRED", 400
        )
    if not name:
        record_auth_result("shopkeeper_register", False, "name_required")
        return error_response(
            "Name is required for registration", "NAME_REQUIRED", 400
        )
    if not payload.password:
        record_auth_result("shopkeeper_register", False, "password_required")
        return error_response(
            "Password is required for registration", "PASSWORD_REQUIRED", 400
        )

    # ─────────────────────────────────────────────────────────────────────
    # TODO(Firebase): re-enable phone-OTP verification when ready. The block
    # below verifies the Firebase ID token server-side and cross-checks the
    # claimed firebase_uid / phone_number against the verified token so
    # clients cannot spoof an identity.
    # ─────────────────────────────────────────────────────────────────────
    # token = _extract_bearer_token(request) or payload.firebase_id_token
    # if not token:
    #     record_auth_result("shopkeeper_register", False, "missing_token")
    #     return error_response(
    #         "Firebase ID token required (Authorization header or firebase_id_token)",
    #         "TOKEN_REQUIRED", 401,
    #     )
    # try:
    #     firebase_uid, phone = verify_firebase_id_token(token)
    # except FirebaseVerificationError as exc:
    #     record_auth_result("shopkeeper_register", False, "token_invalid")
    #     return error_response(exc.message, exc.error_code, exc.status_code)
    # if payload.firebase_uid and payload.firebase_uid != firebase_uid:
    #     record_auth_result("shopkeeper_register", False, "uid_mismatch")
    #     return error_response(
    #         "firebase_uid does not match the verified token",
    #         "IDENTITY_MISMATCH", 403,
    #     )
    # if payload.phone_number and payload.phone_number != phone:
    #     record_auth_result("shopkeeper_register", False, "phone_mismatch")
    #     return error_response(
    #         "phone_number does not match the verified token",
    #         "IDENTITY_MISMATCH", 403,
    #     )
    # phone = phone or payload.phone_number or ""
    firebase_uid: str | None = None

    # Reject existing accounts — they should sign in instead.
    existing = db.query(User).filter(User.phone_number == phone).first()
    if existing is not None:
        record_auth_result("shopkeeper_register", False, "account_exists")
        return error_response(
            message="Phone number already registered. Please login.",
            error_code="PHONE_ALREADY_REGISTERED",
            status_code=400,
        )

    user = shopkeeper_service.create_shopkeeper_account(
        db,
        phone_number=phone,
        name=name,
        email=payload.email,
        password_hash=hash_password(payload.password),
    )
    # Unique Business ID mapped to the phone number (e.g. SHOP_919000000011).
    user.business_id = shopkeeper_service.generate_business_id(db, phone)
    if firebase_uid:
        user.firebase_uid = firebase_uid
    db.flush()

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

    # Load shops for response
    shops = shopkeeper_service.list_authorized_shops(db, user)

    record_auth_result("shopkeeper_register", True, "register_success")
    return success_response(
        data={
            **token_data,
            "user": {
                "id": user.id,
                "firebase_uid": user.firebase_uid,
                "phone_number": user.phone_number,
                "name": user.name,
                "email": user.email,
                "status": user.status.value,
                "role": user.role.name if user.role else None,
                "business_id": user.business_id,
            },
            "business_id": user.business_id,
            "shops": shops,
            "is_new_user": True,
        },
        message="Registration successful",
        status_code=201,
    )


@router.post("/login")
@auth_rate_limit()
async def login(
    payload: ShopkeeperLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Password-based login for shopkeeper (identifier can be email or phone).
    
    Security: Does not reveal whether identifier exists through error messages.
    """
    identifier = _normalize_identifier(payload.identifier)
    
    # Find user by email or phone
    user = (
        db.query(User).filter(
            (User.email == identifier) | (User.phone_number == identifier)
        ).first()
    )
    
    # Generic error message — don't reveal if user exists
    if user is None:
        record_auth_result("shopkeeper_login", False, "invalid_credentials")
        return error_response(
            message="Invalid credentials",
            error_code="INVALID_CREDENTIALS",
            status_code=401,
        )
    
    # Check account status
    if not user.is_active or user.status in (UserStatus.SUSPENDED, UserStatus.BANNED):
        record_auth_result("shopkeeper_login", False, "account_inactive")
        return error_response(
            message="Account is not active. Please contact support.",
            error_code="ACCOUNT_NOT_ACTIVE",
            status_code=403,
        )
    
    # Verify password
    if not user.password_hash:
        record_auth_result("shopkeeper_login", False, "no_password")
        return error_response(
            message="No password set. Please use OTP login or reset your password.",
            error_code="NO_PASSWORD_SET",
            status_code=400,
        )
    
    if not verify_password(payload.password, user.password_hash):
        record_auth_result("shopkeeper_login", False, "invalid_password")
        return error_response(
            message="Invalid credentials",
            error_code="INVALID_CREDENTIALS",
            status_code=401,
        )
    
    # Backfill the Unique Business ID for legacy accounts that predate the
    # phone+password phase (business_id was NULL until now).
    if not user.business_id:
        user.business_id = shopkeeper_service.generate_business_id(
            db, user.phone_number
        )
        db.flush()

    # Issue tokens
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
    record_auth_result("shopkeeper_login", True, "success")
    
    shops = shopkeeper_service.list_authorized_shops(db, user)
    return success_response(
        data=_build_login_response(user, token_data, shops),
        message="Login successful",
    )


@router.post("/verify-otp")
@auth_rate_limit()
async def verify_otp_login(
    payload: ShopkeeperOTPLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Firebase-phone-OTP login for an EXISTING account via the Shopkeeper App.

    The Flutter app completes the OTP flow client-side with ``firebase_auth``
    and sends the resulting Firebase ID token here. We verify it to extract
    the phone number and look up the user.
    """
    try:
        phone = verify_firebase_id_token(payload.firebase_id_token)
    except FirebaseVerificationError as exc:
        record_auth_result("shopkeeper_login", False, "firebase_verification_failed")
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )

    user = db.query(User).filter(User.phone_number == phone).first()
    if user is None:
        record_auth_result("shopkeeper_otp", False, "account_not_found")
        return error_response(
            message="No account found. Please register first.",
            error_code="ACCOUNT_NOT_FOUND",
            status_code=404,
        )
    if not user.is_active or user.status in (UserStatus.SUSPENDED, UserStatus.BANNED):
        record_auth_result("shopkeeper_otp", False, "account_inactive")
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
    record_auth_result("shopkeeper_otp", True, "login_success")

    shops = shopkeeper_service.list_authorized_shops(db, user)
    return success_response(
        data=_build_login_response(user, token_data, shops),
        message="Login successful",
    )


@router.post("/firebase-login")
@auth_rate_limit()
async def firebase_login(
    payload: ShopkeeperFirebaseLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Combined Firebase login-or-register endpoint.

    The Flutter app completes the phone-OTP flow client-side with
    ``firebase_auth`` and sends the resulting Firebase ID token here.

    Flow:
      1. Verify the Firebase ID token (confirms the phone belongs to the user).
      2. Extract the phone number from the verified token.
      3. Look up the shopkeeper by phone in PostgreSQL.
      4. If found and active → issue JWT session tokens (login).
      5. If not found → auto-register a new shopkeeper account, then login.
         (``name`` is required when auto-registering.)

    This "login on first use" pattern is the standard for phone-auth apps —
    users don't need a separate registration step.
    """
    # 1. Verify Firebase ID token → extract phone number
    try:
        phone = verify_firebase_id_token(payload.firebase_id_token)
    except FirebaseVerificationError as exc:
        record_auth_result("shopkeeper_firebase_login", False, "firebase_verification_failed")
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )

    # 2. Look up existing shopkeeper by phone
    user = db.query(User).filter(User.phone_number == phone).first()

    # 3. Auto-register if not found
    if user is None:
        if not payload.name or not payload.name.strip():
            return error_response(
                message="Name is required for new account registration",
                error_code="NAME_REQUIRED",
                status_code=400,
            )
        # Create new shopkeeper account (no password — phone-auth only)
        user = shopkeeper_service.create_shopkeeper_account(
            db,
            phone_number=phone,
            name=payload.name.strip(),
        )
        is_new_account = True
        record_auth_result("shopkeeper_firebase_login", True, "auto_registered")
    else:
        is_new_account = False
        # Check account status
        if not user.is_active or user.status in (UserStatus.SUSPENDED, UserStatus.BANNED):
            record_auth_result("shopkeeper_firebase_login", False, "account_inactive")
            return error_response(
                message="Account is not active. Please contact support.",
                error_code="ACCOUNT_NOT_ACTIVE",
                status_code=403,
            )
        record_auth_result("shopkeeper_firebase_login", True, "login_success")

    # 4. Issue JWT access + refresh tokens
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
    return success_response(
        data={
            **_build_login_response(user, token_data, shops),
            "is_new_account": is_new_account,
        },
        message="Login successful" if not is_new_account else "Account created and logged in",
    )


@router.post("/forgot-password")
@auth_rate_limit()
async def forgot_password(
    payload: ShopkeeperForgotPasswordRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Request a password reset link/token.
    
    Security: Always returns success to prevent email/phone enumeration.
    """
    try:
        result = request_password_reset(db, payload.identifier)
        record_auth_result("shopkeeper_forgot_password", True, "requested")
        return success_response(data=result, message="If an account exists, a reset link has been sent")
    except AppError as exc:
        # Even on error, don't reveal if account exists
        record_auth_result("shopkeeper_forgot_password", False, exc.error_code)
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )


@router.post("/reset-password")
@auth_rate_limit()
async def reset_password_endpoint(
    payload: ShopkeeperResetPasswordRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Reset password using a valid reset token."""
    try:
        result = reset_password(db, payload.token, payload.new_password)
        record_auth_result("shopkeeper_reset_password", True, "success")
        return success_response(data=result, message="Password has been reset successfully")
    except AppError as exc:
        record_auth_result("shopkeeper_reset_password", False, exc.error_code)
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )


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
        record_auth_result("shopkeeper_refresh", False, "invalid_refresh")
        return error_response(
            message=exc.message, error_code=exc.error_code, status_code=exc.status_code
        )
    db.commit()
    record_auth_result("shopkeeper_refresh", True, "success")
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

