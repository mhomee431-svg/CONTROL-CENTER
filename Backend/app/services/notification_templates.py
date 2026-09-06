"""Notification templates for all notification types.

Provides pre-defined templates for consistent messaging across
push, email, and SMS channels.
"""
from dataclasses import dataclass
from typing import Optional


@dataclass
class NotificationTemplate:
    """A notification template for all channels."""
    push_title: str
    push_body: str
    email_subject: str
    email_template: str
    sms_body: str
    deep_link: str = "hyperlocal://home"


# ── Customer Templates ──────────────────────────────────────────────────────

PRICE_DROP = NotificationTemplate(
    push_title="Price Drop! 📉",
    push_body="{product_name} is now ₹{price} at {shop_name}",
    email_subject="Price Drop Alert - {product_name}",
    email_template="price_drop",
    sms_body="Hi {name}! {product_name} is now ₹{price} at {shop_name}. Check it out!",
    deep_link="hyperlocal://product/{product_id}",
)

PRODUCT_AVAILABLE = NotificationTemplate(
    push_title="Product Available! ✅",
    push_body="{product_name} is back in stock at {shop_name}",
    email_subject="Product Available - {product_name}",
    email_template="product_available",
    sms_body="Hi {name}! {product_name} is now available at {shop_name}.",
    deep_link="hyperlocal://product/{product_id}",
)

OFFER_ALERT = NotificationTemplate(
    push_title="Special Offer! 🎉",
    push_body="{offer_title} at {shop_name}",
    email_subject="Special Offer - {offer_title}",
    email_template="offer_alert",
    sms_body="Hi {name}! {offer_title} at {shop_name}. Don't miss out!",
    deep_link="hyperlocal://shop/{shop_id}",
)

ORDER_UPDATE = NotificationTemplate(
    push_title="Order Update 📦",
    push_body="Your order #{order_id} is {status}",
    email_subject="Order Update - #{order_id}",
    email_template="order_update",
    sms_body="Hi {name}! Your order #{order_id} is {status}.",
    deep_link="hyperlocal://order/{order_id}",
)

# ── Shopkeeper Templates ─────────────────────────────────────────────────────

SHOP_VERIFIED = NotificationTemplate(
    push_title="Shop Verified! ✅",
    push_body="Congratulations! Your shop is now live",
    email_subject="Shop Verified - Welcome to Hyperlocal!",
    email_template="shop_verified",
    sms_body="Hi {name}! Your shop has been verified and is now live on Hyperlocal.",
    deep_link="hyperlocal://shopkeeper/shop/{shop_id}",
)

SHOP_REJECTED = NotificationTemplate(
    push_title="Shop Verification Update",
    push_body="Your shop verification needs attention",
    email_subject="Shop Verification - Action Required",
    email_template="shop_rejected",
    sms_body="Hi {name}! Your shop verification needs some changes. Please check the app.",
    deep_link="hyperlocal://shopkeeper/shop/{shop_id}",
)

INVENTORY_LOW = NotificationTemplate(
    push_title="Low Stock Alert ⚠️",
    push_body="{product_name} is running low ({quantity} left)",
    email_subject="Low Stock Alert - {product_name}",
    email_template="inventory_low",
    sms_body="Hi {name}! {product_name} is running low ({quantity} left). Please restock.",
    deep_link="hyperlocal://shopkeeper/inventory",
)

POS_SYNC_SUCCESS = NotificationTemplate(
    push_title="POS Sync Complete ✅",
    push_body="Successfully synced {count} products",
    email_subject="POS Sync Complete",
    email_template="pos_sync_success",
    sms_body="Hi {name}! POS sync complete. {count} products synced.",
    deep_link="hyperlocal://shopkeeper/pos",
)

POS_SYNC_FAILED = NotificationTemplate(
    push_title="POS Sync Failed ❌",
    push_body="Failed to sync products. Will retry automatically.",
    email_subject="POS Sync Failed",
    email_template="pos_sync_failed",
    sms_body="Hi {name}! POS sync failed. We'll retry automatically.",
    deep_link="hyperlocal://shopkeeper/pos",
)

SUBSCRIPTION_REMINDER = NotificationTemplate(
    push_title="Subscription Expiring ⏰",
    push_body="Your {plan_name} plan expires in {days_left} days",
    email_subject="Subscription Expiring Soon",
    email_template="subscription_reminder",
    sms_body="Hi {name}! Your {plan_name} plan expires in {days_left} days. Renew now!",
    deep_link="hyperlocal://subscription",
)

PAYMENT_SUCCESS = NotificationTemplate(
    push_title="Payment Successful ✅",
    push_body="₹{amount} paid successfully",
    email_subject="Payment Confirmation",
    email_template="payment_success",
    sms_body="Hi {name}! ₹{amount} paid successfully. Thank you!",
    deep_link="hyperlocal://payments/{payment_id}",
)

PAYMENT_FAILED = NotificationTemplate(
    push_title="Payment Failed ❌",
    push_body="Payment of ₹{amount} failed. Please try again.",
    email_subject="Payment Failed",
    email_template="payment_failed",
    sms_body="Hi {name}! Payment of ₹{amount} failed. Please try again.",
    deep_link="hyperlocal://payments/{payment_id}",
)

SYSTEM_ANNOUNCEMENT = NotificationTemplate(
    push_title="📢 {title}",
    push_body="{message}",
    email_subject="{title}",
    email_template="system_announcement",
    sms_body="Hi {name}! {message}",
    deep_link="hyperlocal://home",
)


def get_template(notification_type: str) -> Optional[NotificationTemplate]:
    """Get a notification template by type."""
    templates = {
        "PRICE_DROP": PRICE_DROP,
        "PRODUCT_AVAILABLE": PRODUCT_AVAILABLE,
        "OFFER": OFFER_ALERT,
        "ORDER_UPDATE": ORDER_UPDATE,
        "SHOP_VERIFIED": SHOP_VERIFIED,
        "SHOP_REJECTED": SHOP_REJECTED,
        "INVENTORY_LOW": INVENTORY_LOW,
        "POS_SYNC_SUCCESS": POS_SYNC_SUCCESS,
        "POS_SYNC_FAILED": POS_SYNC_FAILED,
        "SUBSCRIPTION_REMINDER": SUBSCRIPTION_REMINDER,
        "PAYMENT_SUCCESS": PAYMENT_SUCCESS,
        "PAYMENT_FAILED": PAYMENT_FAILED,
        "SYSTEM": SYSTEM_ANNOUNCEMENT,
    }
    return templates.get(notification_type)