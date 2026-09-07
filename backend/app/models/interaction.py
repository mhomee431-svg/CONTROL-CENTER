"""UserInteraction (Leads) model — action-triggered verified customer leads.

Records every restricted action a *verified* customer takes on a shop:

    CALL_VIEW  → the customer revealed the shop's contact (View Contact / Call Now)
    MESSAGE    → a chat / contact inquiry message
    RATING     → a numeric rating (1–5) plus an optional review message

Immutable Actions Rule: an interaction is **create-only**. There are no
update/delete routes (or service functions) for customers anywhere in the
platform, so a submitted rating / review / message can never be silently
edited or removed by the customer (anti-spam / anti-fraud tamper protection).
"""
from datetime import datetime
import enum

from sqlalchemy import (
    String,
    DateTime,
    ForeignKey,
    Enum,
    Text,
    Integer,
    CheckConstraint,
    Index,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import TimestampMixin


class InteractionActionType(str, enum.Enum):
    CALL_VIEW = "call_view"
    MESSAGE = "message"
    RATING = "rating"


class UserInteraction(Base, TimestampMixin):
    __tablename__ = "user_interactions"
    __table_args__ = (
        CheckConstraint("rating >= 1 AND rating <= 5", name="ck_interactions_rating_range"),
        Index("ix_user_interactions_shop_created", "shop_id", "created_at"),
        Index("ix_user_interactions_user_created", "user_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    shop_id: Mapped[int] = mapped_column(
        ForeignKey("shops.id", ondelete="CASCADE"), nullable=False, index=True
    )
    action_type: Mapped[InteractionActionType] = mapped_column(
        Enum(
            InteractionActionType,
            name="interaction_action_type",
            native_enum=False,  # project pattern: VARCHAR + CHECK, no PG type dep
        ),
        nullable=False,
        index=True,
        default=InteractionActionType.CALL_VIEW,
    )
    # Inquiry / review text. REQUIRED for `message`; expected for `rating`
    # (the review message); optional/ignored for `call_view`.
    message_content: Mapped[str | None] = mapped_column(Text)
    rating: Mapped[int | None] = mapped_column(Integer, nullable=True)

    user = relationship("User", back_populates="interactions")
    shop = relationship("Shop")