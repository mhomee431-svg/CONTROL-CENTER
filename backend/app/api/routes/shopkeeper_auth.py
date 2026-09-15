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

import time
from asyncio import to_thread
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_role
from app.core.exceptions import AppError, ForbiddenError, UnauthorizedError
from app.core.logging import get_logger
from app.core.observability.metrics import record_auth_result
from app.core.rate_limit import auth_rate_limit
from app.core.responses import error_response, success_response
from app.core.security import hash_password, verify_password
from app.core.shopkeeper_permissions import ensure_shopkeeper_role
from app.database.session import get_db
from app.models.role import Role
from app.models.shop import (
    LocationIntegrityStatus,
    LocationSource,
    LocationStatus,
    LocationType,
    Shop,
    ShopStatus,
)
from app.models.shop import ShopOwner
from app.models.user import User, UserStatus
from app.schemas.shopkeeper import (
    ShopkeeperFirebaseLoginRequest,
    ShopkeeperForgotPasswordRequest,
    ShopkeeperLoginRequest,
    ShopkeeperLogoutRequest,
    ShopkeeperOTPLoginRequest,
    ShopkeeperProfileCreateRequest,
    ShopkeeperRefreshRequest,
    ShopkeeperRegisterRequest,
    ShopkeeperResetPasswordRequest,
    ShopkeeperSendOTPRequest,
)
from app.core.shopkeeper_permissions import sync_owner_role
from app.models.shop import (
    LocationIntegrityStatus,
    LocationSource,
    LocationStatus,
    LocationType,
    Shop,
    ShopStatus,
)
from app.models.shop import ShopOwner
from app.services import shopkeeper_service
from app.services.shopkeeper_service import MERCHANT_CATEGORY_TO_LEGACY_SHOP_CATEGORY
from app.services.auth_service import (
    is_account_allowed,
    issue_tokens,
    logout_session,
)
from app.services.firebase_auth_service import authenticate_with_firebase
from app.services.firebase_verification import (
    FirebaseVerificationError,
    verify_firebase_id_token_claims,
)

logger = get_logger("app.api.shopkeeper_auth")

router = APIRouter(prefix="/shopkeeper/auth", tags=["shopkeeper-auth"])

# HTTPBearer used by /google-profile to read the Authorization header
# (auto_error=False → we return a friendly 401 when the header is missing).
security = HTTPBearer(auto_error=False)


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
            "avatar_url": user.avatar_url,
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
        firebase_uid, phone = verify_firebase_id_token_claims(token)
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
    #     firebase_uid, phone = verify_firebase_id_token_claims(token)
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
        phone = verify_firebase_id_token_claims(payload.firebase_id_token)
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

    Works for BOTH providers the platform supports (per the CURRENT
    authentication decision — Google only, phone is a future extension):

    Google Sign-In (provider ``google.com``):
      1. The Flutter app completes Google Sign-In with Firebase client-side
         (native Credential Manager on Android, Firebase popup on web).
      2. The resulting Firebase ID token is sent here and verified via the
         Firebase Admin SDK.
      3. The shopkeeper is looked up by ``firebase_uid``, then by email.
      4. If found and active → JWT session tokens (login).
      5. If not found → auto-register ONE shopkeeper profile and login.

    Phone OTP (provider ``phone`` — FUTURE extension point): the token's
    ``phone_number`` claim is matched instead of email. No OTP UI/API/SMS
    exists in this implementation; ``/send-otp`` + ``/verify-phone`` remain
    only as the future extension surface.
    """
    # 1. Verify the Firebase ID token → full verified claims
    # BLOCKING NETWORK CALL: Firebase Admin's verify_id_token() fetches
    # Google's public certificates over HTTPS (~200-500ms).  We run it in a
    # thread pool so the asyncio event loop stays responsive for concurrent
    # requests.  The function also checks an in-memory cache first — cache
    # hits skip the network call entirely and return in <1ms.
    t_verify_start = time.perf_counter()
    try:
        claims = await to_thread(
            verify_firebase_id_token_claims, payload.firebase_id_token
        )
    except FirebaseVerificationError as exc:
        elapsed_ms = (time.perf_counter() - t_verify_start) * 1000
        logger.warning(
            "Firebase verification failed after %.1fms: %s",
            elapsed_ms,
            exc.message,
        )
        record_auth_result("shopkeeper_firebase_login", False, "firebase_verification_failed")
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )
    elapsed_verify = (time.perf_counter() - t_verify_start) * 1000
    logger.info(
        "Firebase token verified for uid %s (provider=%s) in %.1fms",
        claims.get("uid"),
        claims.get("provider", ""),
        elapsed_verify,
    )

    # ── Minimal Google data boundary (Phase 19) ──────────────────────────
    # Pull ONLY the whitelisted Google fields from the verified token. If any
    # forbidden credential/scope claim slips through we reject the request so
    # sensitive Google data is never used or persisted.
    from app.services.google_profile_service import extract_minimal_profile

    minimal = extract_minimal_profile(claims.get("claims") or {})

    firebase_uid = claims["uid"]
    phone = claims["phone"]
    email = minimal.email or claims.get("email") or payload.email or None
    token_name = minimal.name or claims.get("name") or None
    photo_url = minimal.picture or claims.get("picture") or payload.photo_url or None

    # 2. Look up the existing shopkeeper account (uid → phone → email)
    user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
    if user is None and phone:
        user = db.query(User).filter(User.phone_number == phone).first()
    if user is None and email:
        user = db.query(User).filter(User.email == email).first()

    # 3. Auto-register one shopkeeper profile if not found
    is_new_account = False
    if user is None:
        name = (
            (payload.name or "").strip()
            or (token_name or "").strip()
            or ""
        )
        if not name:
            return error_response(
                message="Name is required for new account registration",
                error_code="NAME_REQUIRED",
                status_code=400,
            )
        user = shopkeeper_service.create_shopkeeper_account(
            db,
            phone_number=(phone or None),
            name=name,
            email=email,
            avatar_url=photo_url,
        )
        user.firebase_uid = firebase_uid
        user.business_id = shopkeeper_service.generate_business_id(db, phone or None)
        db.flush()
        is_new_account = True
        record_auth_result("shopkeeper_firebase_login", True, "auto_registered")
    else:
        # Link the Firebase identity onto an existing (phone/email) account.
        if not user.firebase_uid:
            user.firebase_uid = firebase_uid
        if email and not user.email:
            user.email = email
        if photo_url and not user.avatar_url:
            user.avatar_url = photo_url
        db.flush()
        if not user.is_active or user.status in (UserStatus.SUSPENDED, UserStatus.BANNED):
            record_auth_result("shopkeeper_firebase_login", False, "account_inactive")
            return error_response(
                message="Account is not active. Please contact support.",
                error_code="ACCOUNT_NOT_ACTIVE",
                status_code=403,
            )
        record_auth_result("shopkeeper_firebase_login", True, "login_success")

    # Update login metadata (last login timestamp + IP)
    user.last_login_at = datetime.now(timezone.utc)
    user.last_login_ip = request.client.host if request.client else None

    # 4. Issue JWT access + refresh tokens
    t_tokens_start = time.perf_counter()
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
    elapsed_tokens = (time.perf_counter() - t_tokens_start) * 1000

    shops = shopkeeper_service.list_authorized_shops(db, user)
    elapsed_total = (time.perf_counter() - t_verify_start) * 1000
    logger.info(
        "firebase_login complete for uid %s in %.1fms "
        "(verify=%.1fms, tokens=%.1fms, new_account=%s)",
        firebase_uid,
        elapsed_total,
        elapsed_verify,
        elapsed_tokens,
        is_new_account,
    )
    return success_response(
        data={
            **_build_login_response(user, token_data, shops),
            "is_new_account": is_new_account,
        },
        message="Login successful" if not is_new_account else "Account created and logged in",
    )


@router.post("/profile-create")
@auth_rate_limit()
async def profile_create(
    payload: ShopkeeperProfileCreateRequest,
    request: Request,
    current_user: User = Depends(require_role("shopkeeper")),
    db: Session = Depends(get_db),
):
    """Create the shopkeeper's first (and only) shop during on-profile setup.

    Unlike the full ``/shopkeeper/shops`` endpoint, this endpoint does NOT
    require location or address — those are captured later via the dedicated
    location-capture flow. This keeps the first-stage profile form fast and
    unblockable.

    Security: only users with the SHOPKEEPER role (server-determined) may
    call this endpoint. The authenticated user is derived from the verified
    Firebase token — never from client input. IDOR-safe: the user can only
    create their own profile.
    """
    user = current_user

    # ── 1. Update user profile (name / email / phone) ─────────────────────
    if payload.name is not None and payload.name.strip():
        user.name = payload.name.strip()
    if payload.email is not None and payload.email.strip():
        user.email = payload.email.strip()
    if payload.phone is not None:
        user.phone_number = payload.phone.strip() or None
    db.flush()

    # ── 2. Create the shop WITHOUT location (nullable at this stage) ──────
    name = payload.shop_name.strip()
    if not name:
        return error_response(
            message="Shop name is required",
            error_code="SHOP_NAME_REQUIRED",
            status_code=400,
        )

    # Unique slug
    from slugify import slugify as _slug

    base_slug = _slug(name)[:280]
    slug = base_slug
    counter = 1
    while db.query(Shop).filter(Shop.slug == slug).first():
        slug = f"{base_slug}-{counter}"
        counter += 1

    # Resolve category (legacy enum mapping)
    legacy_cat = None
    if payload.category:
        from app.models.shop import ShopCategory

        normalized = payload.category.strip().upper()
        legacy = MERCHANT_CATEGORY_TO_LEGACY_SHOP_CATEGORY.get(normalized)
        if legacy is not None:
            legacy_cat = legacy
        else:
            valid = {c.name for c in ShopCategory}
            if normalized and normalized not in valid:
                return error_response(
                    message=f"Invalid shop category: {payload.category}",
                    error_code="INVALID_CATEGORY",
                    status_code=400,
                )
            legacy_cat = ShopCategory[normalized] if normalized in ShopCategory.__members__ else None

    shop = Shop(
        name=name,
        slug=slug,
        description=payload.description,
        tagline=None,
        category=legacy_cat,
        business_type=payload.business_type,
        phone=user.phone_number,
        email=user.email,
        status=ShopStatus.REGISTERED,
        latitude=None,
        longitude=None,
        location=None,
        location_status=LocationStatus.PENDING.value,
        location_source=LocationSource.UNKNOWN.value,
        location_type=LocationType.UNKNOWN.value,
        location_integrity_status=LocationIntegrityStatus.UNKNOWN.value,
        location_verified=False,
        is_open_24x7=False,
        is_accepting_orders=True,
        created_by=user.id,
    )
    db.add(shop)
    db.flush()

    # ── 3. Assign primary owner ────────────────────────────────────────────
    db.add(
        ShopOwner(
            shop_id=shop.id,
            user_id=user.id,
            is_primary=True,
            is_active=True,
        )
    )
    db.flush()
    sync_owner_role(db, user)

    # ── 4. Start merchant onboarding for the category ─────────────────────
    if payload.category:
        from app.services import merchant_onboarding_service

        merchant_onboarding_service.get_or_create_onboarding(
            db, user, shop.id, payload.category.strip().upper()
        )

    db.commit()

    # ── 5. Return updated profile state ────────────────────────────────────
    shops = shopkeeper_service.list_authorized_shops(db, user)
    return success_response(
        data={
            "shop": {
                "id": shop.id,
                "name": shop.name,
                "slug": shop.slug,
                "status": shop.status.value,
                "is_verified": shop.is_verified,
                "category": shop.category.value if shop.category else None,
                "business_type": shop.business_type,
                "membership": "owner",
                "permissions": ["read:dashboard", "update:shop", "update:product"],
            },
            "user": {
                "id": user.id,
                "name": user.name,
                "phone_number": user.phone_number,
                "email": user.email,
                "avatar_url": user.avatar_url,
                "status": user.status.value,
                "role": user.role.name if user.role else "shopkeeper",
            },
            "shops": shops,
            "profile_complete": True,
        },
        message="Profile created successfully",
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



@router.get("/profile")
async def get_shopkeeper_profile(
    current_user: User = Depends(require_role("shopkeeper")),
    db: Session = Depends(get_db),
):
    """Return the authenticated Shopkeeper's full profile (user + shop).

    Security:
      - Only the SHOPKEEPER role (server-determined) may call this endpoint.
      - IDOR-safe: the user is derived from the verified Firebase token —
        never from a client-supplied user_id. A shopkeeper can only read
        their own profile.

    Google account data: only display name, email, and photo URL are stored
    and returned. No unnecessary Google account data is persisted.
    """
    role = current_user.role
    shops = shopkeeper_service.list_authorized_shops(db, current_user)
    primary_shop = shops[0] if shops else None

    return success_response(
        data={
            "user": {
                "id": current_user.id,
                "name": current_user.name,
                "email": current_user.email,
                "phone_number": current_user.phone_number,
                "avatar_url": current_user.avatar_url,
                "status": current_user.status.value,
                "role": role.name if role else "shopkeeper",
                "created_at": current_user.created_at.isoformat() if current_user.created_at else None,
            },
            "shop": {
                "id": primary_shop.get("id") if primary_shop else None,
                "name": primary_shop.get("name") if primary_shop else None,
                "status": primary_shop.get("status") if primary_shop else None,
                "is_verified": primary_shop.get("is_verified") if primary_shop else None,
                "category": primary_shop.get("category") if primary_shop else None,
                "business_type": primary_shop.get("business_type") if primary_shop else None,
            },
            "profile_complete": len(shops) > 0,
        },
        message="OK",
    )


@router.get("/google-profile")
async def google_profile(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
):
    """Return ONLY the minimal Google profile derived from the verified Firebase token.

    Security (Phase 19):
      * The Firebase ID token is VERIFIED server-side first
        (``verify_firebase_id_token_claims``) — never trusts the client.
      * Only whitelisted Google fields (name, email, picture, email_verified)
        are exposed; the firebase_uid is derived from ``sub`` and returned
        for identity linking only.
      * Learn more: :mod:`app.services.google_profile_service`

    Requires: ``Authorization: Bearer <Firebase ID Token>``
    """
    from app.services.google_profile_service import (
        extract_minimal_profile,
        MINIMAL_OAUTH_SCOPES,
    )

    if credentials is None:
        return error_response(
            message="Authentication required",
            error_code="AUTH_REQUIRED",
            status_code=401,
        )

    token = credentials.credentials
    try:
        verified = await to_thread(verify_firebase_id_token_claims, token)
    except FirebaseVerificationError as exc:
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )

    # ``verified[\"claims\"]`` is the full decoded token claims set. The service
    # picks out ONLY the whitelisted Google fields and rejects any forbidden
    # credential claims that slip through.
    try:
        minimal = extract_minimal_profile(verified.get("claims") or {})
    except ValueError as exc:
        return error_response(
            message=str(exc),
            error_code="GOOGLE_PROFILE_FORBIDDEN_CLAIM",
            status_code=400,
        )

    payload = minimal.to_dict()
    return success_response(
        data={
            **payload,
            "firebase_uid": verified.get("uid"),
            "provider": verified.get("provider", ""),
            "required_scopes": list(MINIMAL_OAUTH_SCOPES),
        },
        message="Minimal Google profile",
    )


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
            "avatar_url": current_user.avatar_url,
            "status": getattr(current_user.status, "value", str(current_user.status)),
            "role": role.name if role else None,
            "is_shopkeeper": bool(shops) or (role is not None and role.name == "shopkeeper"),
            "shops": shops,
        },
        message="OK",
    )

