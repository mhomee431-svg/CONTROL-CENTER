"""Restaurant Discovery - Master Spec §27 (Rule 4: discovery-only domain).

Revision ID: 0015
Revises: 0014
Create Date: 2026-09-01

Delivers the first proposed domain from DATABASE SCHEMA DESIGN.txt (Domain 14:

- ``restaurants``  : a 1:1 discovery profile for a ``shops`` row that is a
  restaurant. Reuses shops.location / shop_hours / shop_verifications /
  search / reviews / notifications. Profile/metadata ONLY: cuisine, dining/
  takeaway flags, avg cost, display rating, FSSAI licence. NO inventory,
  cart, checkout or delivery semantics anywhere (Rule 4: this must never
  become a food/grocery delivery application).
- ``restaurant_menu_categories`` : menu taxonomy per restaurant.


- ``restaurant_menu_items`` : discovery menu items; ``price`` is display-only
  and carries CHECK (>= 0).

Conventions: project pattern since 0012 -- enums are VARCHAR + CHECK (avoid
ALTER TYPE lock pain); every table carries created_at/updated_at timestamps;
domain tables that may be soft-deleted by ownership changes carry is_deleted/deleted_at.


The migration chain must remain linear (0014 -> 0015 -> ...); do NOT fork it.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "0015"
down_revision: Union[str, None] = "0014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _timestamps() -> list[sa.Column]:
    return [
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    ]


def _soft_delete() -> list[sa.Column]:
    return [
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    ]


def upgrade() -> None:
    # --- restaurants: 1:1 discovery profile with shops ---------------
    op.create_table(
        "restaurants",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("shops.id", ondelete="CASCADE"), nullable=False),
        sa.Column("cuisine_types", sa.JSON(), nullable=True),
        sa.Column("dining_available", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("takeaway_available", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("avg_cost_for_two", sa.Numeric(12, 2), nullable=True),
        sa.Column("is_open_now_calc", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("rating", sa.Float(), nullable=True),
        sa.Column("review_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("veg_only", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("licence_fssai", sa.String(50), nullable=True),
        *_soft_delete(),
        *_timestamps(),
        sa.UniqueConstraint("shop_id", name="uq_restaurants_shop_id"),
        sa.CheckConstraint("rating >= 0 AND rating <= 5", name="ck_restaurants_rating_range"),
        sa.CheckConstraint("review_count >= 0", name="ck_restaurants_review_count_non_negative"),
        sa.CheckConstraint("avg_cost_for_two >= 0", name="ck_restaurants_avg_cost_non_negative"),
    )

    # --- restaurant_menu_categories: menu taxonomy per restaurant -----------
    op.create_table(
        "restaurant_menu_categories",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("restaurant_id", sa.Integer(), sa.ForeignKey("restaurants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        *_timestamps(),
        sa.UniqueConstraint("restaurant_id", "name", name="uq_restaurant_menu_categories_restaurant_name"),
    )
    op.create_index("ix_restaurant_menu_categories_restaurant_id", "restaurant_menu_categories", ["restaurant_id"])

    # --- restaurant_menu_items: discovery menu items (display price only) ---
    op.create_table(
        "restaurant_menu_items",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("restaurant_id", sa.Integer(), sa.ForeignKey("restaurants.id", ondelete="CASCADE"), nullable=False),
        sa.Column("menu_category_id", sa.Integer(), sa.ForeignKey("restaurant_menu_categories.id", ondelete="SET NULL"), nullable=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("price", sa.Numeric(12, 2), nullable=True),
        sa.Column("veg", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("spicy", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_available_today", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        *_soft_delete(),
        *_timestamps(),
        sa.CheckConstraint("price >=0", name="ck_restaurant_menu_items_price_non_negative"),
    )
    op.create_index("ix_restaurant_menu_items_restaurant_id", "restaurant_menu_items", ["restaurant_id"])
    op.create_index("ix_restaurant_menu_items_menu_category_id", "restaurant_menu_items", ["menu_category_id"])


def downgrade() -> None:
    op.drop_table("restaurant_menu_items")
    op.drop_table("restaurant_menu_categories")
    op.drop_table("restaurants")
