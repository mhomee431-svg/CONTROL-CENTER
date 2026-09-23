"""Create orders and order_items tables (Master Spec ??30-32).

Adds the customer checkout/payment order header and its immutable,
price-snapshotted line items. Status/payments use CHECK constraints
(string enums) rather than DB-native enums, matching the Review model
convention so the migration is portable across PostgreSQL and SQLite dev.
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "0026"
down_revision: str = "0025"
branch_labels: str | None = None
depends_on: str | None = None


_ORDER_STATUSES = "'PENDING','CONFIRMED','PREPARING','READY_FOR_PICKUP','OUT_FOR_DELIVERY','DELIVERED','CANCELLED','REFUNDED','FAILED'"
_ITEM_STATUSES = "'PENDING','CONFIRMED','PREPARING','READY','CANCELLED'"
_PAYMENT_STATUSES = "'PENDING','PAID','FAILED','REFUNDED','PARTIALLY_REFUNDED'"


def upgrade() -> None:
    op.create_table(
        "orders",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("order_number", sa.String(32), nullable=False, unique=True),
        sa.Column("user_id", sa.Integer, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("customer_id", sa.Integer, sa.ForeignKey("customers.id"), nullable=True),
        sa.Column("shop_id", sa.Integer, sa.ForeignKey("shops.id"), nullable=False),
        sa.Column("shipping_address_json", sa.Text, nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="PENDING"),
        sa.Column("payment_method", sa.String(30), nullable=True),
        sa.Column("payment_status", sa.String(20), nullable=False, server_default="PENDING"),
        sa.Column("currency", sa.String(3), nullable=False, server_default="INR"),
        sa.Column("subtotal_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("delivery_fee", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("discount_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("tax_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("total_amount", sa.Numeric(12, 2), nullable=False, server_default="0"),
        sa.Column("total_items", sa.Integer, nullable=False, server_default="1"),
        sa.Column("notes", sa.Text, nullable=True),
        sa.Column("placed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("confirmed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("preparing_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("ready_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("out_for_delivery_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("delivered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancelled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cancelled_by", sa.Integer, sa.ForeignKey("users.id"), nullable=True),
        sa.Column("cancel_reason", sa.Text, nullable=True),
        sa.Column("failed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_reason", sa.Text, nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default="now()"),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default="now()"),
        sa.Column("is_deleted", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(f"status IN ({_ORDER_STATUSES})", name="ck_orders_status"),
        sa.CheckConstraint(f"payment_status IN ({_PAYMENT_STATUSES})", name="ck_orders_payment_status"),
        sa.CheckConstraint("total_amount >= 0", name="ck_orders_total_non_negative"),
        sa.CheckConstraint("subtotal_amount >= 0", name="ck_orders_subtotal_non_negative"),
        sa.CheckConstraint("total_items >= 1", name="ck_orders_total_items_positive"),
    )
    op.create_index("ix_orders_user", "orders", ["user_id"])
    op.create_index("ix_orders_customer", "orders", ["customer_id"])
    op.create_index("ix_orders_shop", "orders", ["shop_id"])

    op.create_table(
        "order_items",
        sa.Column("id", sa.Integer, primary_key=True),
        sa.Column("order_id", sa.Integer, sa.ForeignKey("orders.id", ondelete="CASCADE"), nullable=False),
        sa.Column("product_master_id", sa.Integer, nullable=False),
        sa.Column("product_name", sa.String(255), nullable=False),
        sa.Column("variant_id", sa.Integer, nullable=True),
        sa.Column("variant_name", sa.String(255), nullable=True),
        sa.Column("shop_product_id", sa.Integer, nullable=True),
        sa.Column("quantity", sa.Integer, nullable=False, server_default="1"),
        sa.Column("price", sa.Numeric(12, 2), nullable=False),
        sa.Column("total_price", sa.Numeric(12, 2), nullable=False),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("item_status", sa.String(20), nullable=False, server_default="PENDING"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default="now()"),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default="now()"),
        sa.CheckConstraint("quantity >= 1", name="ck_order_items_quantity_positive"),
        sa.CheckConstraint("price >= 0", name="ck_order_items_price_non_negative"),
        sa.CheckConstraint("total_price >= 0", name="ck_order_items_total_non_negative"),
        sa.CheckConstraint(f"item_status IN ({_ITEM_STATUSES})", name="ck_order_items_status"),
    )
    op.create_index("ix_order_items_order", "order_items", ["order_id"])
    op.create_index("ix_order_items_product_master", "order_items", ["product_master_id"])


def downgrade() -> None:
    op.drop_table("order_items")
    op.drop_table("orders")
