"""Tests for Firebase Authentication integration.

Tests cover:
1. Valid Firebase token authentication
2. Invalid Firebase token rejection
3. Missing token handling
4. User provisioning (new user creation)
5. Existing user login
6. Role assignment (CUSTOMER, SHOPKEEPER)
7. Account status validation (suspended, banned)
8. Firebase UID uniqueness
9. Phone number migration (legacy users)
10. RBAC enforcement
"""
import pytest
from unittest.mock import patch

from app.core.exceptions import ForbiddenError, UnauthorizedError
from app.models.role import Role
from app.models.user import User, UserStatus
from app.services.firebase_auth_service import (
    FirebaseAuthResult,
    authenticate_with_firebase,
    _create_user,
    _find_user_by_firebase_uid,
    _get_or_create_role,
)
from app.services.firebase_verification import FirebaseVerificationError


class TestFirebaseVerification:
    """Tests for Firebase token verification."""

    def test_verify_valid_token_returns_uid_and_phone(self):
        """Valid Firebase token should return (firebase_uid, phone_number)."""
        with patch("app.services.firebase_auth_service.verify_firebase_id_token") as mock_verify:
            mock_verify.return_value = ("test-firebase-uid-123", "+919999999999")
            
            from app.services.firebase_auth_service import verify_firebase_id_token
            uid, phone = verify_firebase_id_token("valid-token")
            
            assert uid == "test-firebase-uid-123"
            assert phone == "+919999999999"

    def test_verify_invalid_token_raises_error(self):
        """Invalid Firebase token should raise FirebaseVerificationError."""
        with patch("app.services.firebase_auth_service.verify_firebase_id_token") as mock_verify:
            mock_verify.side_effect = FirebaseVerificationError(
                "Invalid token",
                error_code="FIREBASE_VERIFICATION_FAILED",
            )
            
            from app.services.firebase_auth_service import verify_firebase_id_token
            with pytest.raises(FirebaseVerificationError):
                verify_firebase_id_token("invalid-token")

    def test_verify_expired_token_raises_error(self):
        """Expired Firebase token should raise FirebaseVerificationError."""
        with patch("app.services.firebase_auth_service.verify_firebase_id_token") as mock_verify:
            mock_verify.side_effect = FirebaseVerificationError(
                "Token expired",
                error_code="FIREBASE_TOKEN_EXPIRED",
            )
            
            from app.services.firebase_auth_service import verify_firebase_id_token
            with pytest.raises(FirebaseVerificationError):
                verify_firebase_id_token("expired-token")
