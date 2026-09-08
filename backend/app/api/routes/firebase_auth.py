"""Firebase Authentication endpoints — the single source of truth for auth.

These endpoints implement the correct architecture:
    Flutter → Firebase Phone OTP → Firebase ID Token → FastAPI → PostgreSQL

No custom JWT tokens are issued. Firebase manages the session/authentication
state. FastAPI verifies the Firebase ID token on every request and enforces
authorization based on PostgreSQL roles/permissions.

Endpoints:
    POST /api/v1/auth/firebase — Authenticate with Firebase ID token
    POST /api/v1/auth/firebase/register — Register with Firebase ID token
"""
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import UnauthorizedError
from app.core.logging import get_logger
from app.core.observability.metrics import record_auth_result
from app.core.rate_limit import auth_rate_limit
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.auth import (
    FirebaseAuthRequest,
    FirebaseRegisterRequest,
)
from app.services.firebase_auth_service import authenticate_with_firebase

logger = get_logger("app.api.firebase_auth")

router = APIRouter(prefix="/auth", tags=["firebase-auth"])


@router.post("/firebase")
@auth_rate_limit()
async def authenticate(
    payload: FirebaseAuthRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Authenticate with a Firebase ID token.

    This is the primary authentication endpoint. The client:
    1. Performs Firebase Phone OTP sign-in
    2. Obtains a Firebase ID token
    3. Sends it here for verification

    The backend:
    1. Verifies the Firebase ID token cryptographically
    2. Extracts firebase_uid and phone_number
    3. Finds or creates the application user
    4. Returns user context (no custom tokens — Firebase manages session)
    """
    client_ip = request.client.host if request.client else None

    try:
        result = authenticate_with_firebase(
            db=db,
            firebase_id_token=payload.firebase_id_token,
            ip_address=client_ip,
            requested_role=payload.requested_role,
            name=payload.name,
        )
    except (UnauthorizedError, Exception) as exc:
        record_auth_result("firebase_auth", False, "authentication_failed")
        if isinstance(UnauthorizedError, type(exc)):
            return error_response(
                message=exc.message,
                error_code=exc.error_code,
                status_code=exc.status_code,
            )
        logger.exception("Firebase authentication failed")
        return error_response(
            message="Authentication failed",
            error_code="AUTHENTICATION_FAILED",
            status_code=500,
        )

    record_auth_result("firebase_auth", True, "success")

    context = result.to_context_dict()
    context["message"] = "Authentication successful"

    return success_response(
        data=context,
        message="Authentication successful",
    )


@router.post("/firebase/register")
@auth_rate_limit()
async def register(
    payload: FirebaseRegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """Register a new user with Firebase ID token.

    This endpoint is for first-time users who need to provide additional
    information (name, role) during registration.
    """
    client_ip = request.client.host if request.client else None

    try:
        result = authenticate_with_firebase(
            db=db,
            firebase_id_token=payload.firebase_id_token,
            ip_address=client_ip,
            requested_role=payload.requested_role or "customer",
            name=payload.name,
        )
    except (UnauthorizedError, Exception) as exc:
        record_auth_result("firebase_register", False, "registration_failed")
        if isinstance(UnauthorizedError, type(exc)):
            return error_response(
                message=exc.message,
                error_code=exc.error_code,
                status_code=exc.status_code,
            )
        logger.exception("Firebase registration failed")
        return error_response(
            message="Registration failed",
            error_code="REGISTRATION_FAILED",
            status_code=500,
        )

    record_auth_result("firebase_register", True, "success")

    context = result.to_context_dict()
    context["message"] = "Registration successful"

    return success_response(
        data=context,
        message="Registration successful",
    )


@router.get("/me")
async def get_current_user_info(
    current_user: User = Depends(get_current_user),
):
    """Get current authenticated user information.

    This endpoint requires a valid Firebase ID token in the Authorization header.
    The get_current_user dependency verifies the token and loads the user.
    """
    return success_response(
        data={
            "id": current_user.id,
            "firebase_uid": current_user.firebase_uid,
            "phone_number": current_user.phone_number,
            "name": current_user.name,
            "email": current_user.email,
            "status": current_user.status.value,
            "role": current_user.role.name if current_user.role else None,
        },
        message="OK",
    )
