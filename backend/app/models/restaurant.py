"""Restaurant discovery models — Master Spec §27 (Rule 4: a restaurant
is a business/service discovery domain and must never be forced into the normal
product-inventory model).

Discovery-only by design: ``restaurants`` reuses ``shops`` for location / hours /
verification / notifications / search; menu items carry display price only — there
is NO menu-item stock, cart, checkout or delivery semantics anywhere (the
platform never becomes a food/grocery delivery application).
"""

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Float,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.session import Base
from app.models.base import SoftDeleteMixin, TimestampMixin


class Restaurant(Base, TimestampMixin, SoftDeleteMixin):
    """A 1:1 discovery profile for a ``shops`` row that is a restaurant."""

    __tablename__ = "restaurants"
    __table_args__ = (
        UniqueConstraint("shop_id", name="uq_restaurants_shop_id"),
        CheckConstraint("rating >= 0 AND rating <= 5", name="ck_restaurants_rating_range"),
        CheckConstraint("review_count >= 0", name="ck_restaurants_review_count_non_negative"),
        CheckConstraint("avg_cost_for_two >= 0", name="ck_restaurants_avg_cost_non_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    shop_id: Mapped[int] = mapped_column(
        ForeignKey("shops.id", ondelete="CASCADE"), nullable=False
    )
    cuisine_types: Mapped[dict | None] = mapped_column(JSON)  # ["North Indian", "Chinese"]
    dining_available: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    takeaway_available: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    avg_cost_for_two: Mapped[float | None] = mapped_column(Numeric(12, 2))
    is_open_now_calc: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    rating: Mapped[float | None] = mapped_column(Float)
    review_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    veg_only: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    licence_fssai: Mapped[str | None] = mapped_column(String(50))

    # No back_populates on Shop: shop.py stays untouched (uncommitted owner work).)
    shop = relationship("Shop")
    menu_categories = relationship(
        "RestaurantMenuCategory", back_populates="restaurant", cascade="all, delete-orphan"
    )
    menu_items = relationship(
        "RestaurantMenuItem", back_populates="restaurant", cascade="all, delete-orphan"
    )


class RestaurantMenuCategory(Base, TimestampMixin):
    """Menu taxonomy per restaurant (cuisine sections)."""

    __tablename__ = "restaurant_menu_categories"
    __table_args__ = (
        UniqueConstraint(
            "restaurant_id", "name", name="uq_restaurant_menu_categories_restaurant_name"
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    restaurant_id: Mapped[int] = mapped_column(
        ForeignKey("restaurants.id", ondelete="CASCADE"), index=True, nullable=False
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")

    restaurant = relationship("Restaurant", back_populates="menu_categories")
    items = relationship(
        "RestaurantMenuItem", back_populates="menu_category", cascade="all, delete-orphan"
    )


class RestaurantMenuItem(Base, TimestampMixin, SoftDeleteMixin):

    __tablename__ = "restaurant_menu_items"
    __table_args__ = (
        CheckConstraint("price >= 0", name="ck_restaurant_menu_items_price_non_negative"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    restaurant_id: Mapped[int] = mapped_column(
        ForeignKey("restaurants.id", ondelete="CASCADE"), index=True, nullable=False
    )
    menu_category_id: Mapped[int | None] = mapped_column(
        ForeignKey("restaurant_menu_categories.id", ondelete="SET NULL"), index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    price: Mapped[float | None] = mapped_column(Numeric(12, 2))  # display only
    veg: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    spicy: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    is_available_today: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")

    restaurant = relationship("Restaurant", back_populates="menu_items")
    menu_category = relationship("RestaurantMenuCategory", back_populates="items")