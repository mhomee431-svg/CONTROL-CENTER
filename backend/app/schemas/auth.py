from pydantic import BaseModel, Field


class SendOTPRequest(BaseModel):
    """Acknowledgment-only payload.

    OTP delivery is handled client-side by Firebase Phone Auth; the backend
    never sends an SMS. This schema is kept for API-contract compatibility.
    """

    phone_number: str = Field(..., min_length=10, max_length=15, description="User's phone number")


class SendOTPResponse(BaseModel):
    message: str = "OTP delivery is handled by Firebase Phone Auth"


class CustomerFirebaseAuthRequest(BaseModel):
    """Firebase Phone Auth payload for the Customer App.

    The Flutter app completes the phone-OTP flow client-side with
    ``firebase_auth`` and sends the resulting Firebase ID token. The token can
    arrive in the ``Authorization: Bearer`` header (preferred) or — for
    backward compatibility — in the body as ``firebase_id_token``.

    For the new ``verify-phone`` → ``register`` flow the client may also send
    the verified ``firebase_uid`` / ``phone_number`` and the desired ``role``.
    """

    firebase_id_token: str | None = Field(
        None,
        min_length=20,
        description="Firebase ID token from the client phone-OTP sign-in (body fallback)",
    )
    firebase_uid: str | None = Field(
        None,
        max_length=128,
        description="Verified Firebase UID (cross-checked against the token)",
    )
    phone_number: str | None = Field(
        None,
        max_length=20,
        description="Verified phone number (cross-checked against the token)",
    )
    requested_role: str | None = Field(
        None,
        description="Role to assign for new users (customer, shopkeeper)",
    )
    name: str | None = Field(
        None,
        max_length=100,
        description="Display name (required when creating a new account)",
    )
    device_id: str | None = Field(None, description="Stable device identifier")
    device_name: str | None = None
    device_type: str | None = Field(None, description="android, ios, web")
    platform: str | None = Field(None, description="OS version / platform info")
    app_version: str | None = None


class RefreshTokenRequest(BaseModel):
    refresh_token: str
    device_id: str | None = None


class LogoutRequest(BaseModel):
    refresh_token: str | None = None
    session_id: str | None = None
    revoke_all: bool = False


class AuthUserInfo(BaseModel):
    id: int
    phone_number: str
    name: str | None = None
    role: str | None = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    session_id: str
    user: AuthUserInfo


class SessionInfo(BaseModel):
    session_id: str
    device_name: str | None = None
    device_type: str | None = None
    platform: str | None = None
    app_version: str | None = None
    ip_address: str | None = None
    last_activity_at: str | None = None
    created_at: str | None = None
    expires_at: str | None = None


class SessionsResponse(BaseModel):
    sessions: list[SessionInfo]


class AccountStatusResponse(BaseModel):
    is_active: bool
    status: str
    last_login_at: str | None = None


class FirebaseAuthRequest(BaseModel):
    """Firebase Authentication request payload.

    The Flutter app completes the phone-OTP flow client-side with
    ``firebase_auth`` and sends the resulting Firebase ID token.
    The backend verifies the token to extract firebase_uid and phone_number.
    """
    firebase_id_token: str = Field(
        ...,
        min_length=20,
        description="Firebase ID token from the client phone-OTP sign-in",
    )
    requested_role: str | None = Field(
        None,
        description="Role to assign for new users (customer, shopkeeper)",
    )
    name: str | None = Field(
        None,
        max_length=100,
        description="Display name for new users",
    )


class FirebaseRegisterRequest(BaseModel):
    """Firebase Registration request payload for first-time users."""
    firebase_id_token: str = Field(
        ...,
        min_length=20,
        description="Firebase ID token from the client phone-OTP sign-in",
    )
    requested_role: str | None = Field(
        "customer",
        description="Role to assign (customer, shopkeeper)",
    )
    name: str = Field(
        ...,
        max_length=100,
        description="Display name for the new user",
    )