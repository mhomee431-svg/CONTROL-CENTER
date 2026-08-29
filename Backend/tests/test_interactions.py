"""Tests for the User Interactions / Leads (immutable create-only) flow.

Covers the service validation rules, immutability (no update/delete paths),
the action-triggered verification gate (JWT required), public read-only shop
reviews, and the shopkeeper leads dashboard.
"""
import asyncio
import datetime
from typing import Any
from unittest.mock import patch

import pytest

from app.models.interaction import InteractionActionType, UserInteraction
from app.models.shop import Shop, ShopStatus
from app.models.user import User

# ── Tiny in-memory SQLAlchemy stand-in (same philosophy as the OTP tests) ────


def _right_value(expr):
    r = expr.right
    name = type(r).__name__
    if name in ("False_",):
        return False
    if name in ("True_",):
        return True
    return getattr(r, "value", r)


def _eval(record, expr):
    from sqlalchemy.sql.elements import BinaryExpression

    if not isinstance(expr, BinaryExpression):
        raise TypeError(f"Unhandled expression: {type(expr).__name__}")
    col_name = getattr(expr.left, "key", None)
    value = getattr(record, col_name) if col_name else None
    fn_name = getattr(expr.operator, "__name__", str(expr.operator))
    if fn_name == "eq":
        return value == _right_value(expr)
    if fn_name == "is_":
        return value is _right_value(expr)
    if fn_name in ("in_", "in_op"):
        right = _right_value(expr)
        return value in set(right or [])
    raise TypeError(f"Unhandled operator: {fn_name}")


def _where(record, clauses):
    from sqlalchemy.sql.elements import BooleanClauseList

    if clauses is None:
        return True
    if isinstance(clauses, BooleanClauseList):
        return all(_eval(record, c) for c in clauses.clauses)
    return _eval(record, clauses)


class _FakeQuery:
    def __init__(self, rows):
        self._rows = list(rows)
        self._preds: list = []
        self._limit: int | None = None

    def filter(self, *exprs):
        q = _FakeQuery(self._rows)
        q._preds = list(self._preds) + list(exprs)
        return q

    def order_by(self, *_):
        self._rows = sorted(self._rows, key=lambda r: getattr(r, "id") or 0, reverse=True)
        return self

    def limit(self, n):
        self._limit = n
        return self

    def _matched(self):
        rows = [r for r in self._rows if all(_where(r, p) for p in self._preds)]
        if self._limit is not None:
            return rows[: self._limit]
        return rows

    def first(self):
        rows = self._matched()
        return rows[0] if rows else None

    def all(self):
        return self._matched()

    def count(self):
        return len(self._matched())


class FakeSession:
    def __init__(self):
        self.rows: list[Any] = []
        self._id = 0

    def query(self, model):
        return _FakeQuery([r for r in self.rows if isinstance(r, model)])

    def add(self, obj):
        self._id += 1
        obj.id = getattr(obj, "id", None) or self._id
        if getattr(obj, "created_at", None) is None:
            obj.created_at = datetime.datetime.now(datetime.timezone.utc)
        self.rows.append(obj)

    def flush(self):
        pass

    def commit(self):
        pass

    def rollback(self):
        pass


def run_async(coro):
    return asyncio.run(coro)
def make_shop(shop_id=1, status=ShopStatus.ACTIVE):
    shop = Shop()
    shop.id = shop_id
    shop.name = f"Shop {shop_id}"
    shop.status = status
    return shop


def make_user(user_id=1, name="Ravi", phone="+919000000001"):
    user = User()
    user.id = user_id
    user.name = name
    user.phone_number = phone
    return user


def make_interaction(**kwargs):
    i = UserInteraction()
    i.user_id = kwargs.get("user_id", 1)
    i.shop_id = kwargs.get("shop_id", 1)
    i.action_type = kwargs.get("action_type", InteractionActionType.CALL_VIEW)
    i.message_content = kwargs.get("message_content")
    i.rating = kwargs.get("rating")
    i.created_at = kwargs.get("created_at") or datetime.datetime.now(datetime.timezone.utc)
    return i


# ── Service: create (validation + immutability) ──────────────────────────────
class TestCreateInteraction:
    def test_call_view_recorded(self):
        from app.services.interaction_service import create_interaction

        db = FakeSession()
        db.add(make_shop())
        db.add(make_user())
        out = create_interaction(db, make_user(), 1, "call_view")
        assert out["action_type"] == "call_view"
        assert out["rating"] is None

    def test_message_requires_content(self):
        from app.services.interaction_service import (
            InvalidActionError,
            create_interaction,
        )

        db = FakeSession()
        db.add(make_shop())
        with pytest.raises(InvalidActionError):
            create_interaction(db, make_user(), 1, "message")

    def test_rating_requires_rating(self):
        from app.services.interaction_service import (
            InvalidActionError,
            create_interaction,
        )

        db = FakeSession()
        db.add(make_shop())
        with pytest.raises(InvalidActionError):
            create_interaction(db, make_user(), 1, "rating")

    def test_rating_range(self):
        from app.services.interaction_service import (
            InvalidActionError,
            create_interaction,
        )

        db = FakeSession()
        db.add(make_shop())
        with pytest.raises(InvalidActionError):
            create_interaction(db, make_user(), 1, "rating", rating=6, message_content="ok")

    def test_unknown_action_rejected(self):
        from app.services.interaction_service import (
            InvalidActionError,
            create_interaction,
        )

        db = FakeSession()
        db.add(make_shop())
        with pytest.raises(InvalidActionError):
            create_interaction(db, make_user(), 1, "hack")

    def test_rating_with_message_stored(self):
        from app.services.interaction_service import create_interaction

        db = FakeSession()
        db.add(make_shop())
        out = create_interaction(
            db, make_user(), 1, "rating", message_content="  Great shop  ", rating=5
        )
        assert out["rating"] == 5
        assert out["message_content"] == "Great shop"

    def test_missing_shop_not_found(self):
        from app.core.exceptions import NotFoundError
        from app.services.interaction_service import create_interaction

        db = FakeSession()  # no shops added
        with pytest.raises(NotFoundError):
            create_interaction(db, make_user(), 99, "call_view")

    def test_no_update_or_delete_service_functions(self):
        # Immutability: the module must not expose any update/delete helper.
        import app.services.interaction_service as svc

        public = {n for n in dir(svc) if not n.startswith("_")}
        assert "update_interaction" not in public
        assert "delete_interaction" not in public
# ── Service: reads ───────────────────────────────────────────────────────────
class TestInteractionReads:
    def test_list_customer_interactions(self):
        from app.services.interaction_service import list_customer_interactions

        db = FakeSession()
        db.add(make_interaction(user_id=1, shop_id=1, action_type=InteractionActionType.MESSAGE, message_content="hi"))
        db.add(make_interaction(user_id=2, shop_id=1, action_type=InteractionActionType.RATING, rating=4))
        rows = list_customer_interactions(db, make_user(user_id=1))
        assert len(rows) == 1
        assert rows[0]["action_type"] == "message"

    def test_shop_reviews_aggregate(self):
        from app.services.interaction_service import list_shop_reviews

        db = FakeSession()
        db.add(make_shop())
        db.add(make_interaction(shop_id=1, action_type=InteractionActionType.RATING, rating=5, message_content="A"))
        db.add(make_interaction(shop_id=1, action_type=InteractionActionType.RATING, rating=3, message_content="B"))
        db.add(make_interaction(shop_id=1, action_type=InteractionActionType.MESSAGE, message_content="ignore me"))
        data = list_shop_reviews(db, 1)
        assert data["rating_count"] == 2
        assert data["average_rating"] == 4.0
        assert len(data["reviews"]) == 2
        # Public reviews never leak identity.
        assert "customer_name" not in data["reviews"][0]

    def test_shopkeeper_leads_scoped_to_owned_shops(self):
        from app.services import interaction_service as svc

        db = FakeSession()
        db.add(make_shop(shop_id=10))
        db.add(make_shop(shop_id=20))
        db.add(make_interaction(shop_id=10, user_id=1, action_type=InteractionActionType.CALL_VIEW))
        db.add(make_interaction(shop_id=20, user_id=1, action_type=InteractionActionType.RATING, rating=5))
        db.add(make_interaction(shop_id=30, user_id=2, action_type=InteractionActionType.MESSAGE, message_content="other"))

        owner = make_user(user_id=7, name="Shop Owner")
        with patch.object(
            svc.shopkeeper_service,
            "list_authorized_shops",
            return_value=[{"id": 10, "name": "Shop 10"}, {"id": 20, "name": "Shop 20"}],
        ):
            leads = svc.list_shopkeeper_leads(db, owner)
        assert len(leads) == 2
        assert {l["shop_id"] for l in leads} == {10, 20}
        assert leads[0]["shop_name"] in ("Shop 10", "Shop 20")

    def test_masked_phone(self):
        from app.services.interaction_service import _mask_phone

        assert _mask_phone("+919000000001") == "+91********01"
# ── Routes ───────────────────────────────────────────────────────────────────
class TestInteractionRoutes:
    def test_action_requires_auth_gate(self):
        # POST /interactions/action declares get_current_user among its
        # dependencies, so anonymous callers get 401 (the verification gate).
        from app.core.dependencies import get_current_user

        from app.api.routes import interactions

        route = next(
            r for r in interactions.router.routes if getattr(r, "path", "") == "/interactions/action"
        )
        dep_callables = [d.call for d in route.dependant.dependencies if d.call is not None]
        assert get_current_user in dep_callables

    def test_create_action_route_success(self):
        from app.api.routes.interactions import create_action
        from app.schemas.interaction import InteractionCreateRequest

        db = FakeSession()
        db.add(make_shop())
        with patch("app.api.routes.interactions.interaction_service.create_interaction") as mock_create:
            mock_create.return_value = {
                "id": 1, "shop_id": 1, "action_type": "rating",
                "message_content": "nice", "rating": 5, "created_at": None,
            }
            response = run_async(
                create_action(
                    InteractionCreateRequest(action_type="rating", shop_id=1, message_content="nice", rating=5),
                    current_user=make_user(),
                    db=db,
                )
            )
        assert response.status_code == 201
        assert b"nice" in response.body

    def test_shop_reviews_route_public(self):
        from app.api.routes.interactions import shop_reviews

        db = FakeSession()
        db.add(make_shop())
        db.add(make_interaction(shop_id=1, action_type=InteractionActionType.RATING, rating=4, message_content="ok"))
        response = run_async(shop_reviews(shop_id=1, limit=10, db=db))
        assert response.status_code == 200
        assert b"ok" in response.body

    def test_shopkeeper_leads_route(self):
        from app.api.routes.shopkeeper_portal import shopkeeper_leads

        db = FakeSession()
        db.add(make_shop(shop_id=10))
        db.add(make_interaction(shop_id=10, user_id=1, action_type=InteractionActionType.MESSAGE, message_content="lead"))

        owner = make_user(user_id=7, name="Owner")
        with patch(
            "app.services.interaction_service.shopkeeper_service.list_authorized_shops",
            return_value=[{"id": 10, "name": "Shop 10"}],
        ):
            response = run_async(shopkeeper_leads(current_user=owner, db=db))
        assert response.status_code == 200
        body = response.body
        assert b"lead" in body
        assert b"count" in body