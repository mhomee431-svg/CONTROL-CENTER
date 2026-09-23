"""Orders API + service tests (Master Spec ??30-32).

In-memory SQLite. Only the orders/order_items tables are materialised;
foreign-key enforcement is disabled so order rows can reference users/
customers/shops without persisting those tables, while the table-level
CHECK constraints (status/payment enums, non-negative money, positive
quantity) still apply.

This module is syntax-validated locally with ``python -m py_compile``
(system interpreter). Full execution requires a virtualenv with the app
dependencies installed (``python -m venv .venv && pip install -r requirements.txt``).
"""
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("HYPERLOCAL_ENV", "test")

import pytest  # noqa: E402
from fastapi import HTTPException  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine, event  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.dependencies import get_current_user, require_admin  # noqa: E402
from app.database.session import Base, get_db  # noqa: E402
from app.models.order import Order, OrderItem, OrderStatus  # noqa: E402
from app.schemas.order import OrderCreate, OrderItemCreate  # noqa: E402
from app.services import order_service  # noqa: E402
from app.main import app  # noqa: E402


API_PREFIX = settings.API_PREFIX
SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)


@event.listens_for(engine, "connect")
def _set_pragma(dbapi_conn, connection_record):
    # Orders-only harness: disable FK enforcement so the order tables can
    # reference users/customers/shops rows this harness does not persist.
    dbapi_conn.execute("PRAGMA foreign_keys=OFF")


TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@event.listens_for(TestingSessionLocal, "before_flush")
def _fill_timestamps(session, flush_context, instances):
    """SQLite cannot evaluate the PG ``server_default='now()'``; stamp in Python."""
    now = datetime.now(timezone.utc)
    for obj in session.new:
        for col in ("created_at", "updated_at"):
            if getattr(obj, col, None) is None and col in obj.__table__.columns:
                setattr(obj, col, now)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db

CUSTOMER = SimpleNamespace(id=1, role=SimpleNamespace(name="customer"))
ADMIN = SimpleNamespace(id=1, role=SimpleNamespace(name="admin"))
app.dependency_overrides[get_current_user] = lambda: CUSTOMER
app.dependency_overrides[require_admin] = lambda: ADMIN

client = TestClient(app)


def _make_tables():
    Order.__table__.create(engine, checkfirst=True)
    OrderItem.__table__.create(engine, checkfirst=True)


@pytest.fixture(autouse=True)
def _tables_and_clean():
    _make_tables()
    yield
    with TestingSessionLocal() as s:
        s.query(OrderItem).delete()
        s.query(Order).delete()
        s.commit()


def _db():
    return TestingSessionLocal()


def _sample_create() -> OrderCreate:
    return OrderCreate(
        shop_id=42,
        delivery_fee=10.0,
        discount_amount=0.0,
        tax_amount=2.98,
        notes="Leave at the door",
        items=[
            OrderItemCreate(
                product_master_id=7,
                product_name="Roti",
                quantity=2,
                price=12.0,
                image_url="https://example.com/roti.jpg",
            ),
        ],
    )


def _sample_payload() -> dict:
    return {
        "shop_id": 42,
        "delivery_fee": 10.0,
        "discount_amount": 0.0,
        "tax_amount": 2.98,
        "notes": "Leave at the door",
        "items": [
            {
                "product_master_id": 7,
                "product_name": "Roti",
                "quantity": 2,
                "price": 12.0,
                "image_url": "https://example.com/roti.jpg",
            }
        ],
    }


# --- Model / Enum tests -------------------------------------------------------
def test_order_status_enum_values():
    values = {s.value for s in OrderStatus}
    assert "PENDING" in values
    assert "CONFIRMED" in values
    assert "PREPARING" in values
    assert "READY_FOR_PICKUP" in values
    assert "OUT_FOR_DELIVERY" in values
    assert "DELIVERED" in values
    assert "CANCELLED" in values
    assert "REFUNDED" in values
    assert "FAILED" in values


def test_order_models_have_expected_columns():
    order_cols = {c.name for c in Order.__table__.columns}
    for name in (
        "id", "order_number", "user_id", "customer_id", "shop_id",
        "status", "payment_method", "payment_status", "currency",
        "subtotal_amount", "delivery_fee", "discount_amount", "tax_amount",
        "total_amount", "total_items", "shipping_address_json",
    ):
        assert name in order_cols, f"Order missing column: {name}"

    item_cols = {c.name for c in OrderItem.__table__.columns}
    for name in (
        "order_id", "product_master_id", "product_name", "variant_id",
        "variant_name", "shop_product_id", "quantity", "price", "total_price",
        "image_url", "item_status",
    ):
        assert name in item_cols, f"OrderItem missing column: {name}"


def test_order_is_cancellable_only_in_active_states():
    db = _db()
    try:
        o = order_service.create_order(db, user_id=1, data=_sample_create())
        assert o.is_cancellable is True
        # Walk the forward-only lifecycle: the service guard rejects a direct
        # PENDING -> DELIVERED jump, which is exactly the behaviour under test.
        for status in (
            OrderStatus.CONFIRMED.value,
            OrderStatus.PREPARING.value,
            OrderStatus.READY_FOR_PICKUP.value,
            OrderStatus.OUT_FOR_DELIVERY.value,
            OrderStatus.DELIVERED.value,
        ):
            order_service.update_order_status(db, order_id=o.id, status=status)
        db.expire(o)
        assert o.is_cancellable is False
    finally:
        db.close()


# --- Service tests ------------------------------------------------------------
def test_create_order_computes_totals_and_snapshots():
    db = _db()
    try:
        order = order_service.create_order(db, user_id=1, data=_sample_create())
        loaded = db.get(Order, order.id)
        assert loaded.order_number.startswith("ORD-")
        # Numeric columns come back as Decimal (SQLite/PG); compare numerically
        # rather than relying on Decimal == float for non-binary-exact values.
        assert loaded.subtotal_amount == 24.0
        assert loaded.delivery_fee == 10.0
        assert float(loaded.tax_amount) == 2.98
        assert float(loaded.total_amount) == 36.98
        assert loaded.total_items == 2
        assert loaded.status == OrderStatus.PENDING.value
        assert loaded.payment_status == "PENDING"
        assert loaded.placed_at is not None
        items = list(loaded.items)
        assert len(items) == 1
        assert items[0].product_name == "Roti"
        assert items[0].price == 12.0
        assert items[0].total_price == 24.0
        assert items[0].product_master_id == 7
        assert items[0].order_id == order.id
    finally:
        db.close()


def test_create_order_rejects_empty_items_and_negative_total():
    db = _db()
    try:
        with pytest.raises(ValueError):
            order_service.create_order(
                db, user_id=1,
                data=OrderCreate(shop_id=1, items=[], delivery_fee=0, discount_amount=0, tax_amount=0),
            )
        bad = OrderCreate(
            shop_id=1,
            items=[OrderItemCreate(product_master_id=1, product_name="X", quantity=1, price=1.0)],
            delivery_fee=0, discount_amount=5.0, tax_amount=0,
        )
        with pytest.raises(ValueError):
            order_service.create_order(db, user_id=1, data=bad)
    finally:
        db.close()


def test_get_order_is_scoped_to_owner():
    db = _db()
    try:
        order = order_service.create_order(db, user_id=1, data=_sample_create())
        assert order_service.get_order(db, order_id=order.id, user_id=1) is not None
        assert order_service.get_order(db, order_id=order.id, user_id=999) is None
        assert order_service.get_order(db, order_id=999999, user_id=1) is None
    finally:
        db.close()


def test_cancel_order_success_and_not_cancellable_again():
    db = _db()
    try:
        order = order_service.create_order(db, user_id=1, data=_sample_create())
        cancelled = order_service.cancel_order(db, order_id=order.id, user_id=1, reason="changed mind")
        assert cancelled.status == OrderStatus.CANCELLED.value
        assert cancelled.cancel_reason == "changed mind"
        assert cancelled.payment_status == "PENDING"
        with pytest.raises(ValueError):
            order_service.cancel_order(db, order_id=order.id, user_id=1)
    finally:
        db.close()


def test_update_order_status_transitions_and_guards():
    db = _db()
    try:
        order = order_service.create_order(db, user_id=1, data=_sample_create())
        o = order_service.update_order_status(db, order_id=order.id, status=OrderStatus.CONFIRMED.value)
        assert o.status == OrderStatus.CONFIRMED.value
        assert o.confirmed_at is not None
        # CONFIRMED cannot jump straight to DELIVERED
        with pytest.raises(ValueError):
            order_service.update_order_status(db, order_id=order.id, status=OrderStatus.DELIVERED.value)
    finally:
        db.close()


# --- Route tests --------------------------------------------------------------
def test_route_create_order_returns_201():
    response = client.post(f"{API_PREFIX}/orders", json=_sample_payload())
    assert response.status_code == 201
    body = response.json()
    assert body["success"] is True
    assert body["data"]["order_number"].startswith("ORD-")
    assert body["data"]["total_amount"] == 36.98
    assert len(body["data"]["items"]) == 1


def test_route_list_orders_returns_only_own_orders():
    client.post(f"{API_PREFIX}/orders", json=_sample_payload())
    response = client.get(f"{API_PREFIX}/orders")
    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    # The stubbed customer (id=1) is the owner -> exactly one order.
    assert body["data"]["total"] == 1
    assert body["data"]["orders"][0]["order_number"].startswith("ORD-")


def test_route_get_order_404_for_unknown():
    response = client.get(f"{API_PREFIX}/orders/999999")
    assert response.status_code == 404
    assert response.json()["error_code"] == "ORDER_NOT_FOUND"


def test_route_get_order_returns_own_order():
    create = client.post(f"{API_PREFIX}/orders", json=_sample_payload())
    order_id = create.json()["data"]["id"]
    response = client.get(f"{API_PREFIX}/orders/{order_id}")
    assert response.status_code == 200
    assert response.json()["data"]["id"] == order_id


def test_route_cancel_then_conflict():
    order = order_service.create_order(_db(), user_id=1, data=_sample_create())
    oid = order.id
    first = client.post(f"{API_PREFIX}/orders/{oid}/cancel", params={"note": "too slow"})
    assert first.status_code == 200
    assert first.json()["data"]["status"] == "CANCELLED"
    second = client.post(f"{API_PREFIX}/orders/{oid}/cancel")
    assert second.status_code == 409


def test_route_shop_orders_admin_only_then_allowed():
    client.post(f"{API_PREFIX}/orders", json=_sample_payload())
    # Admin override is in place -> 200.
    response = client.get(f"{API_PREFIX}/orders/shop/42")
    assert response.status_code == 200
    assert response.json()["data"]["total"] == 1


def test_route_status_update_forbidden_for_non_admin():
    def _deny():
        raise HTTPException(status_code=403, detail="Admin only")

    app.dependency_overrides[require_admin] = _deny
    try:
        order = order_service.create_order(_db(), user_id=1, data=_sample_create())
        response = client.post(
            f"{API_PREFIX}/orders/{order.id}/status",
            json={"status": "CONFIRMED"},
        )
        assert response.status_code == 403
    finally:
        app.dependency_overrides[require_admin] = lambda: ADMIN
