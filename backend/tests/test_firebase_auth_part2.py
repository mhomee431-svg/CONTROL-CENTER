"""Tests for Firebase Authentication - Part 2: RBAC and Legacy Migration."""
import pytest
from .test_database_schema import requires_db
from unittest.mock import patch

from app.core.exceptions import ForbiddenError, UnauthorizedError
from app.models.role import Role
from app.models.user import User, UserStatus
from app.services.firebase_auth_service import (
    FirebaseAuthResult,
    authenticate_with_firebase,
)
from app.services.firebase_verification import FirebaseVerificationError


class TestFirebaseAuthResult:
    """Tests for FirebaseAuthResult class."""

    def test_to_context_dict(self):
        """to_context_dict should return correct structure."""
        user = User(
            id=1,
            firebase_uid="test-uid",
            phone_number="+919999999999",
            name="Test User",
            email="test@example.com",
            status=UserStatus.ACTIVE,
        )
        user.role = Role(name="customer")
        
        result = FirebaseAuthResult(
            user=user,
            firebase_uid="test-uid",
            phone_number="+919999999999",
            is_new_user=True,
        )
        
        context = result.to_context_dict()
        
        assert context["user"]["id"] == 1
        assert context["user"]["firebase_uid"] == "test-uid"
        assert context["user"]["phone_number"] == "+919999999999"
        assert context["user"]["name"] == "Test User"
        assert context["user"]["email"] == "test@example.com"
        assert context["user"]["status"] == "ACTIVE"
        assert context["user"]["role"] == "customer"
        assert context["is_new_user"] is True


class TestRoleBasedAccessControl:
    """Tests for RBAC enforcement."""

    @requires_db
    def test_customer_cannot_access_shopkeeper_routes(self, db_session):
        """Customer role should not have shopkeeper permissions."""
        with patch("app.services.firebase_auth_service.verify_firebase_id_token") as mock_verify:
            mock_verify.return_value = ("customer-uid", "+919999999999")
            
            result = authenticate_with_firebase(
                db=db_session,
                firebase_id_token="valid-token",
                requested_role="customer",
            )
            
            assert result.user.role.name == "customer"
            # Customer should not have shopkeeper permissions
            permission_names = [p.name for p in result.user.role.permissions]
            assert "create:shop" not in permission_names

    @requires_db
    def test_shopkeeper_has_shop_permissions(self, db_session):
        """Shopkeeper role should have shop-related permissions."""
        with patch("app.services.firebase_auth_service.verify_firebase_id_token") as mock_verify:
            mock_verify.return_value = ("shopkeeper-uid", "+919999999999")
            
            result = authenticate_with_firebase(
                db=db_session,
                firebase_id_token="valid-token",
                requested_role="shopkeeper",
            )
            
            assert result.user.role.name == "shopkeeper"


class TestLegacyMigration:
    """Tests for legacy user migration (phone number linking)."""

    @requires_db
    def test_legacy_user_linked_by_phone(self, db_session):
        """Existing user without firebase_uid should be linked by phone."""
        # Create legacy user without firebase_uid
        legacy_user = User(
            phone_number="+919999999999",
            name="Legacy User",
            status=UserStatus.ACTIVE,
            is_active=True,
        )
        db_session.add(legacy_user)
        db_session.commit()
        
        # Authenticate with Firebase token for same phone
        with patch("app.services.firebase_auth_service.verify_firebase_id_token") as mock_verify:
            mock_verify.return_value = ("new-firebase-uid", "+919999999999")
            
            result = authenticate_with_firebase(
                db=db_session,
                firebase_id_token="valid-token",
            )
            
            # Should link to existing user
            assert result.user.id == legacy_user.id
            assert result.user.firebase_uid == "new-firebase-uid"
            assert result.is_new_user is False


# Fixtures
@pytest.fixture
def db_session():
    """Create a test database session."""
    from app.database.session import SessionLocal
    
    db = SessionLocal()
    try:
        yield db
    finally:
        db.rollback()
        db.close()
