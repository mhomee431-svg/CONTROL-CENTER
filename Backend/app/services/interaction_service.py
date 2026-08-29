"""User-interaction / leads service (immutable, create-only).

Drives the "Public Browse + Action-Triggered Verification" model:

  * Browsing shops/products is fully public (existing shop/product/search
    routes require no auth).
  * Restricted customer actions (view contact / call now, send a message /
    chat, give a rating & review) are gated here: creating an interaction
    requires an authenticated, verified user.
  * **Immutability**: an interaction record is created once and can NEVER be
    updated or deleted by the customer. This service intentionally exposes NO
    update/delete functions, and no such routes exist in the API.

Shopkeepers read only the leads tied to shops they own/manage, and cannot
alter customer-submitted reviews either.
"""
from typing import Any

from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, ValidationError
from app.core.logging import get_logger
from app.models.interaction import InteractionActionType, UserInteraction
from app.models.shop import Shop, ShopStatus
from app.models.user import User
from app.services import shopkeeper_service

logger = get_logger("app.services.interaction")

ALLOWED_ACTIONS = {a.value for a in InteractionActionType}

# Action → (message required?, rating required?)
_ACTION_REQUIREMENTS: dict[str, tuple[bool, bool]] = {
    InteractionActionType.CALL_VIEW.value: (False, False),
    InteractionActionType.MESSAGE.value: (True, False),
    InteractionActionType.RATING.value: (False, True),
}

# Message limits (anti-spam length caps).
MAX_MESSAGE_LENGTH = 2000


class InvalidActionError(ValidationError):
    """Raised when an interaction payload violates action rules."""


def _active_shop(db: Session, shop_id: int) -> Shop:
    """Return a browsable shop or raise 404."""
    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop is None:
        raise NotFoundError("Shop not found")
    if shop.status in (ShopStatus.SUSPENDED, ShopStatus.CLOSED, ShopStatus.REJECTED):
        raise NotFoundError("Shop not found")
    return shop


def create_interaction(
    db: Session,
    user: User,
    shop_id: int,
    action_type: str,
    message_content: str | None = None,
    rating: int | None = None,
) -> dict[str, Any]:
    """Record a restricted customer action as a verified lead.

    Create-only: once written, a customer can never edit or delete it.
    """
    action = (action_type or "").strip().lower()
    if action not in ALLOWED_ACTIONS:
        raise InvalidActionError(
            f"action_type must be one of: {', '.join(sorted(ALLOWED_ACTIONS))}"
        )

    shop = _active_shop(db, shop_id)

    message_required, rating_required = _ACTION_REQUIREMENTS[action]
    if message_required and not (message_content or "").strip():
        raise InvalidActionError("message_content is required for this action")
    if message_content and len(message_content) > MAX_MESSAGE_LENGTH:
        raise InvalidActionError(
            f"message_content must be at most {MAX_MESSAGE_LENGTH} characters"
        )
    if rating_required and rating is None:
        raise InvalidActionError("rating is required for this action")
    if rating is not None and not (1 <= rating <= 5):
        raise InvalidActionError("rating must be between 1 and 5")

    interaction = UserInteraction(
        user_id=user.id,
        shop_id=shop.id,
        action_type=InteractionActionType(action),
        message_content=(
            (message_content or "").strip() or None
            if action in ("message", "rating")
            else None
        ),
        rating=rating if action == "rating" else None,
    )
    db.add(interaction)
    db.flush()

    logger.info("Interaction recorded user=%s shop=%s action=%s", user.id, shop.id, action)
    return {
        "id": interaction.id,
        "shop_id": shop.id,
        "action_type": action,
        "message_content": interaction.message_content,
        "rating": interaction.rating,
        "created_at": interaction.created_at.isoformat() if interaction.created_at else None,
    }
def list_customer_interactions(db: Session, user: User) -> list[dict[str, Any]]:
    """Read-only list of a customer's own interactions."""
    rows = (
        db.query(UserInteraction)
        .filter(UserInteraction.user_id == user.id)
        .order_by(UserInteraction.id.desc())
        .all()
    )
    return [_serialize(i) for i in rows]


def list_shop_reviews(db: Session, shop_id: int, limit: int = 50) -> dict[str, Any]:
    """Public, read-only list of a shop's ratings & reviews (for browsable UI)."""
    _active_shop(db, shop_id)
    rows = (
        db.query(UserInteraction)
        .filter(
            UserInteraction.shop_id == shop_id,
            UserInteraction.action_type == InteractionActionType.RATING,
        )
        .order_by(UserInteraction.id.desc())
        .limit(max(1, min(limit, 200)))
        .all()
    )
    ratings = [r.rating for r in rows if r.rating is not None]
    average = round(sum(ratings) / len(ratings), 2) if ratings else None
    return {
        "shop_id": shop_id,
        "average_rating": average,
        "rating_count": len(ratings),
        "reviews": [_serialize_public(r) for r in rows],
    }


def list_shopkeeper_leads(db: Session, user: User) -> list[dict[str, Any]]:
    """All verified customer leads tied to shops the user owns/manages.

    Read-only for the shopkeeper — they can see the lead/inquiry/rating but
    can never delete or edit the customer's submission.
    """
    shops = shopkeeper_service.list_authorized_shops(db, user)
    shop_ids = [int(s["id"]) for s in shops] if shops else []
    if not shop_ids:
        return []
    leads = (
        db.query(UserInteraction)
        .filter(UserInteraction.shop_id.in_(shop_ids))
        .order_by(UserInteraction.id.desc())
        .all()
    )
    shop_name_by_id = {int(s["id"]): s.get("name") for s in shops}
    return [_serialize_lead(i, shop_name_by_id.get(i.shop_id)) for i in leads]


def _serialize(i: UserInteraction) -> dict[str, Any]:
    return {
        "id": i.id,
        "shop_id": i.shop_id,
        "action_type": i.action_type.value,
        "message_content": i.message_content,
        "rating": i.rating,
        "created_at": i.created_at.isoformat() if i.created_at else None,
    }


def _serialize_public(i: UserInteraction) -> dict[str, Any]:
    # Public reviews never expose the customer's identity or phone.
    return {
        "id": i.id,
        "rating": i.rating,
        "message_content": i.message_content,
        "created_at": i.created_at.isoformat() if i.created_at else None,
    }


def _serialize_lead(i: UserInteraction, shop_name: str | None) -> dict[str, Any]:
    return {
        "id": i.id,
        "shop_id": i.shop_id,
        "shop_name": shop_name,
        "action_type": i.action_type.value,
        "message_content": i.message_content,
        "rating": i.rating,
        "customer_name": i.user.name if i.user else None,
        "customer_phone": _mask_phone(i.user.phone_number)
        if (i.user and i.user.phone_number)
        else None,
        "created_at": i.created_at.isoformat() if i.created_at else None,
    }


def _mask_phone(phone: str) -> str:
    """Mask a phone number for the leads list (e.g. +91********01)."""
    plus = "+" if phone.startswith("+") else ""
    digits = "".join(ch for ch in phone if ch.isdigit())
    if len(digits) <= 4:
        return plus + "****"
    return plus + digits[:2] + "*" * (len(digits) - 4) + digits[-2:]