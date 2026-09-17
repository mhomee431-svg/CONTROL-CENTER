from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from typing import Optional

from app.core.dependencies import get_current_session_id, get_current_user
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
from app.services import shopkeeper_service
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


def _extract_bearer_token(request: Request) -> str | None:
    """Extract the raw token from an ``Authorization: Bearer <token>`` header."""
    header = request.headers.get("authorization") or ""
    if header.lower().startswith("bearer "):
        token = header[7:].strip()
        return token or None
    return None


def _create_account_by_role(
    db: Session,
    *,
    firebase_uid: str,
    phone: str,
    name: str,
    role: str,
) -> User:
    """Create a new user (+ profile) for ``role`` with ``firebase_uid`` set."""
    if role == "shopkeeper":
        user = shopkeeper_service.create_shopkeeper_account(
            db, phone_number=phone, name=name
        )
        user.firebase_uid = firebase_uid
        db.flush()
        return user

    return _create_customer_account(db, phone, name, firebase_uid=firebase_uid)


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


def _create_customer_account(
    db: Session, phone: str, name: str | None, firebase_uid: str | None = None
) -> User:
    """Create a new customer user (+ profile) with the default 'customer' role."""
    default_role = _default_role(db)
    user = User(
        phone_number=phone,
        firebase_uid=firebase_uid,
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


@router.post("/verify-phone")
@auth_rate_limit()
async def verify_phone(
    request: Request,
    db: Session = Depends(get_db),
):
    """Verify a Firebase ID token and return the login payload or a new-user
    handoff.

    The Flutter app completes the phone-OTP flow client-side with
    ``firebase_auth`` and forwards the resulting Firebase ID token in the
    ``Authorization: Bearer <token>`` header. We verify it to extract the
    stable ``firebase_uid`` and the phone number, then:

      - If a user with that ``firebase_uid`` (or phone) exists and is active →
        issue JWT session tokens (login).
      - Otherwise → return ``is_new_user`` so the client can collect the
        profile (name + role) and call ``/register``.
    """
    token = _extract_bearer_token(request)
    if not token:
        record_auth_result("verify_phone", False, "missing_token")
        return error_response(
            "Authorization header with a Firebase ID token is required",
            "TOKEN_REQUIRED",
            401,
        )

    try:
        firebase_uid, phone = verify_firebase_id_token(token)
    except FirebaseVerificationError as exc:
        record_auth_result("verify_phone", False, "token_invalid")
        return error_response(exc.message, exc.error_code, exc.status_code)

    user = db.query(User).filter(User.firebase_uid == firebase_uid).first()
    if user is None and phone:
        user = db.query(User).filter(User.phone_number == phone).first()

    if user is None:
        record_auth_result("verify_phone", True, "new_user")
        return success_response(
            data={
                "is_new_user": True,
                "firebase_uid": firebase_uid,
                "phone_number": phone,
            },
            message="New user — complete your profile to register",
        )

    if not is_account_allowed(user):
        record_auth_result("verify_phone", False, "account_inactive")
        return error_response(
            "Account is not active", "ACCOUNT_NOT_ACTIVE", 403
        )

    meta = _get_client_meta(request)
    token_data = issue_tokens(
        user,
        db,
        ip_address=meta["ip_address"],
        user_agent=meta["user_agent"],
    )
    db.commit()
    record_auth_result("verify_phone", True, "login_success")
    return success_response(data=token_data, message="Login successful")


@router.post("/register")
@auth_rate_limit()
async def register_endpoint(
    payload: CustomerFirebaseAuthRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Register a new account (customer or shopkeeper) after phone verification.

    The Flutter app calls ``/verify-phone`` first; when it reports a new user,
    the client collects the profile (name + role) and calls this endpoint.

    Security: the Firebase ID token is verified server-side (Bearer header or
    ``firebase_id_token`` in the body) and the claimed ``firebase_uid`` /
    ``phone_number`` must match the verified token — clients cannot spoof an
    identity. The chosen ``role`` (``customer`` or ``shopkeeper``) decides which
    kind of account is created.
    """
    # Resolve the ID token: Bearer header preferred, body fallback.
    token = _extract_bearer_token(request) or payload.firebase_id_token
    if not token:
        record_auth_result("customer_register", False, "missing_token")
        return error_response(
            "Firebase ID token required (Authorization header or firebase_id_token)",
            "TOKEN_REQUIRED",
            401,
        )

    try:
        firebase_uid, phone = verify_firebase_id_token(token)
    except FirebaseVerificationError as exc:
        record_auth_result("customer_register", False, "token_invalid")
        return error_response(exc.message, exc.error_code, exc.status_code)

    # Cross-check any identity claims from the body against the verified token.
    if payload.firebase_uid and payload.firebase_uid != firebase_uid:
        record_auth_result("customer_register", False, "uid_mismatch")
        return error_response(
            "firebase_uid does not match the verified token",
            "IDENTITY_MISMATCH",
            403,
        )
    if payload.phone_number and payload.phone_number != phone:
        record_auth_result("customer_register", False, "phone_mismatch")
        return error_response(
            "phone_number does not match the verified token",
            "IDENTITY_MISMATCH",
            403,
        )

    role = (payload.requested_role or "customer").strip().lower()
    if role not in ("customer", "shopkeeper"):
        record_auth_result("customer_register", False, "invalid_role")
        return error_response(
            "role must be 'customer' or 'shopkeeper'",
            "INVALID_ROLE",
            400,
        )

    name = (payload.name or "").strip()
    if not name:
        record_auth_result("customer_register", False, "name_required")
        return error_response(
            "Name is required for registration",
            "NAME_REQUIRED",
            400,
        )

    # Reject existing accounts — they should sign in instead.
    existing = db.query(User).filter(
        (User.firebase_uid == firebase_uid) | (User.phone_number == phone)
    ).first()
    if existing is not None:
        record_auth_result("customer_register", False, "account_exists")
        return error_response(
            message="Account already exists. Please sign in instead.",
            error_code="ACCOUNT_EXISTS",
            status_code=409,
        )

    user = _create_account_by_role(
        db,
        firebase_uid=firebase_uid,
        phone=phone,
        name=name,
        role=role,
    )

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
    token_session_id: Optional[str] = Depends(get_current_session_id),
    db: Session = Depends(get_db),
):
    """Revoke the current session (or specify session_id / revoke_all).

    Falls back to the session named by the bearer token's ``session_id`` claim,
    so a client that sends no ``session_id`` still gets a real revocation.
    """
    try:
        if payload.revoke_all:
            result = logout_session(db, current_user, revoke_all=True)
        else:
            result = logout_session(
                db,
                current_user,
                session_id=payload.session_id or token_session_id,
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