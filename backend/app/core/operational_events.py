"""Create durable feed events in the same transaction as operational writes."""

from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, event, inspect
from sqlalchemy.orm import Session

from app.models import (
    Complaint,
    ImportJob,
    Offer,
    OperationalEvent,
    SearchQuery,
    Shop,
    ShopDocument,
    ShopInventory,
    ShopPricing,
)


def _event_for(instance: object, session: Session) -> tuple[str, str] | None:
    is_new = instance in session.new

    if isinstance(instance, SearchQuery) and is_new:
        return "CUSTOMER_SEARCH", "A customer searched nearby products"
    if isinstance(instance, Complaint) and is_new:
        return "SUPPORT_TICKET", "A new support ticket was submitted"
    if isinstance(instance, ShopDocument) and is_new:
        return "VERIFICATION_SUBMISSION", "New shop documents were submitted for review"
    if isinstance(instance, Shop):
        if is_new:
            return "SHOPKEEPER_REGISTRATION", "A new shop registered"
        if instance in session.dirty:
            status = inspect(instance).attrs.verification_status.history
            if status.has_changes():
                return "VERIFICATION", "A shop verification decision was recorded"
            return "SHOP_UPDATE", "Shop information was updated"
    if isinstance(instance, ShopInventory) and (
        is_new
        or any(
            inspect(instance).attrs[name].history.has_changes()
            for name in ("quantity", "price", "stock_status")
        )
    ):
        return "INVENTORY_UPDATE", "Shop inventory was updated"
    if isinstance(instance, (ShopPricing, Offer)) and (
        is_new
        or instance in session.dirty
    ):
        return "PRICE_UPDATE", "A shop price or offer was updated"
    if isinstance(instance, ImportJob) and instance in session.dirty:
        status = inspect(instance).attrs.status.history
        if status.has_changes() and instance.status == "COMPLETED":
            return "IMPORT_COMPLETION", "A catalog or inventory import completed"
    return None


def record_operational_events(
    session: Session, flush_context: object, instances: object
) -> None:
    tracked = tuple(session.new) + tuple(session.dirty)
    recorded = False
    for instance in tracked:
        if isinstance(instance, OperationalEvent):
            continue
        details = _event_for(instance, session)
        if details is not None:
            event_type, title = details
            session.add(OperationalEvent(type=event_type, title=title))
            recorded = True
    if recorded:
        session.execute(
            delete(OperationalEvent).where(
                OperationalEvent.created_at
                < datetime.now(timezone.utc) - timedelta(days=7)
            )
        )


def register_operational_events() -> None:
    if not event.contains(Session, "before_flush", record_operational_events):
        event.listen(Session, "before_flush", record_operational_events)
