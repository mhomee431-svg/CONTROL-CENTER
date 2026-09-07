from pydantic import BaseModel, Field


class SendOTPRequest(BaseModel):
    phone_number: str = Field(..., min_length=10, max_length=15, description="User's phone number")


class SendOTPResponse(BaseModel):
    message: str = "OTP sent successfully"
    expires_in: int
    dev_otp: str | None = None  # Only returned in OTP_DEV_MODE


class VerifyOTPRequest(BaseModel):
    phone_number: str = Field(..., min_length=10, max_length=15)
    otp: str = Field(..., min_length=4, max_length=8)
    device_id: str | None = Field(None, description="Stable device identifier")
    device_name: str | None = None
    device_type: str | None = Field(None, description="android, ios, web")
    platform: str | None = Field(None, description="OS version / platform info")
    app_version: str | None = None


class RegisterRequest(BaseModel):
    """Explicit first-time registration with a display name.

    The customer app sends this after the OTP screen when the user is new.
    Behaves like verify-otp but also persists the chosen display name and
    rejects accounts that already exist (those should sign in instead).
    """

    phone_number: str = Field(..., min_length=10, max_length=15)
    otp: str = Field(..., min_length=4, max_length=8)
    name: str = Field(..., min_length=1, max_length=100)
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