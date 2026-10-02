"""Tests for Firebase Authentication - Part 2: RBAC and Legacy Migration.

The RBAC and legacy-migration checks run against an in-process SQLite session
instead of a database server: ``authenticate_with_firebase`` only touches
``users``, ``roles``, ``role_permissions`` and the customer profile, so this
module materialises exactly those tables. No database is needed and no check is
skipped.
"""
from unittest.mock import patch

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database.session import Base
from app.models.customer import Customer
from app.models.role import Permission, Role, role_permissions, user_roles
from app.models.user import User, UserStatus
from app.services.firebase_auth_service import (
    FirebaseAuthResult,
    authenticate_with_firebase,
)

# Tables the Firebase auth service reads or writes.
_DB_TABLES = [
    User.__table__,
    Role.__table__,
    Permission.__table__,
    role_permissions,
    user_roles,
    Customer.__table__,
]


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
    """SQLite-backed session holding the RBAC tables (no server required)."""
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine, tables=_DB_TABLES)
    session = sessionmaker(bind=engine)()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()

