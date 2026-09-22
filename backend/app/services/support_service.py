"""Shopkeeper support tickets — real intake + tracking on the `complaints` table.

WHY THIS EXISTS
---------------
The shopkeeper app's *Contact support* / *Report an issue* screens could only
compose a report text and copy it to the clipboard, because the backend exposed
no support-intake endpoint: a "Send" button would either have done nothing or
lied. This service is the engine behind the missing endpoint.

It deliberately reuses the platform's EXISTING ``complaints`` table
(``app/models/admin.py``) instead of inventing a parallel ``support_tickets``
table:

  * that table already carries everything a TRACKED ticket needs — reporter
    (``complainant_user_id``), type, ``subject``, ``description``, ``status``,
    ``priority``, ``assigned_to``, ``resolution_notes`` and ``resolved_at``;
  * the admin side ALREADY reads and updates it (``GET``/``PUT
    /admin/complaints`` → ``admin_service.list_complaints`` /
    ``admin_service.update_complaint``), so a ticket filed from the app lands
    in the queue support actually works from. One triage queue, not two.

What is added here is only the missing *shopkeeper-facing* half: a scoped
create / list / read for the signed-in reporter.

STATUS VALUES ARE THE BACKEND'S
-------------------------------
Statuses are the real ``ComplaintStatus`` members (OPEN, IN_PROGRESS,
RESOLVED, CLOSED, REJECTED); :data:`STATUS_LABELS` attaches the app-facing
wording. The app renders exactly what it is given and never invents its own
"Submitted → In progress → Resolved" progression — a ticket an admin resolves
directly must not be displayed as "in progress".

WHY APP-ISSUE CODES ARE PREFIXED ``APP_``
-----------------------------------------
``complaints.complaint_type`` also carries CUSTOMER complaints about a shop
(WRONG_PRICE / FAKE_PRODUCT / SHOP_ISSUE). Shopkeeper-reported app issues are
filed under ``APP_*`` codes so an admin triaging the shared queue can tell
"the merchant cannot use the app" apart from "a customer says the price is
wrong" — and so the resolution notice emitted by
``admin_service.update_complaint`` is only sent to shopkeepers for tickets
that actually came from the shopkeeper app.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy.orm import Session, defer

from app.core.exceptions import NotFoundError, ValidationError
from app.models.admin import Complaint, ComplaintStatus
from app.models.shop import Shop
from app.models.user import User

# ── Canonical taxonomy ────────────────────────────────────────────────────
# Deliberately declared ONCE, on the server: a category the backend does not
# accept is rejected with a 422 instead of being stored as free text an admin
# cannot filter on. The app's `IssueCategory` enum sends these exact codes.
CATEGORIES: dict[str, str] = {
    "APP_PRODUCTS": "Products & catalogue",
    "APP_INVENTORY": "Inventory & stock",
    "APP_OFFERS": "Offers & pricing",
    "APP_POS": "POS / billing sync",
    "APP_PAYMENTS": "Payments & subscription",
    "APP_ACCOUNT": "Account & sign-in",
    "APP_OTHER": "Something else",
}

# Priorities are stored in `complaints.priority`, whose vocabulary is shared
# with customer complaints (LOW, MEDIUM, HIGH, URGENT). URGENT is accepted so a
# support agent can escalate a ticket later without a schema change.
PRIORITIES: frozenset[str] = frozenset({"LOW", "MEDIUM", "HIGH", "URGENT"})

# App-facing wording for every backend status. Keyed by the enum member so a
# new member added to `ComplaintStatus` fails the exhaustiveness test in
# `tests/test_shopkeeper_support.py` instead of silently rendering "None".
STATUS_LABELS: dict[ComplaintStatus, str] = {
    ComplaintStatus.OPEN: "Submitted",
    ComplaintStatus.IN_PROGRESS: "In progress",
    ComplaintStatus.RESOLVED: "Resolved",
    ComplaintStatus.CLOSED: "Closed",
    ComplaintStatus.REJECTED: "Not accepted",
}

# ── Field limits ──────────────────────────────────────────────────────────
# Enforced here as well as in the request schema: the service is also called
# from tests and admin tooling, and a ticket with an empty description is
# useless in the triage queue.
MIN_DESCRIPTION_LENGTH = 10
MAX_DESCRIPTION_LENGTH = 4000
MAX_STEPS_LENGTH = 2000
MAX_SUBJECT_LENGTH = 255


def _text(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _status_code(complaint: Complaint) -> str:
    """The status value as stored (an enum member or a raw string)."""
    status = complaint.status
    return str(getattr(status, "value", status))


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


# ── Validation ────────────────────────────────────────────────────────────
def normalize_category(raw: str) -> str:
    """Validates and returns an accepted ``APP_*`` category code."""
    code = _text(raw).upper()
    if not code:
        raise ValidationError("An issue category is required")
    if code not in CATEGORIES:
        raise ValidationError(
            f"Unknown issue category: {raw}",
            data={"allowed_categories": sorted(CATEGORIES)},
        )
    return code


def normalize_priority(raw: str | None) -> str:
    """Validates and returns the triage priority (defaults to MEDIUM)."""
    code = _text(raw).upper() or "MEDIUM"
    if code not in PRIORITIES:
        raise ValidationError(
            f"Unknown priority: {raw}",
            data={"allowed_priorities": sorted(PRIORITIES)},
        )
    return code


def _compose_description(
    *,
    description: str,
    steps: str | None,
    app_version: str | None,
    shop_name: str | None,
    shop_id: int | None,
) -> str:
    """One stored body holding everything support needs to triage.

    ``complaints`` has no ``steps`` / ``app_version`` column, and adding one
    would be a migration for a purely presentational split. The report is
    therefore stored as the shopkeeper wrote it, with the reproduction steps and
    the client context appended under a separator — exactly the shape the
    clipboard flow already produced, so nothing an admin previously saw is lost.
    """
    body = _text(description)
    if len(body) < MIN_DESCRIPTION_LENGTH:
        raise ValidationError(
            "Please describe the problem in a little more detail",
            data={"min_length": MIN_DESCRIPTION_LENGTH},
        )
    if len(body) > MAX_DESCRIPTION_LENGTH:
        raise ValidationError(
            "The description is too long",
            data={"max_length": MAX_DESCRIPTION_LENGTH},
        )

    parts = [body]

    step_text = _text(steps)
    if step_text:
        if len(step_text) > MAX_STEPS_LENGTH:
            raise ValidationError(
                "The reproduction steps are too long",
                data={"max_length": MAX_STEPS_LENGTH},
            )
        parts.append(f"Steps to reproduce:\n{step_text}")

    context: list[str] = []
    version = _text(app_version)
    if version:
        context.append(f"App: {version}")
    if shop_id is not None:
        context.append(f"Shop: {shop_name or 'unnamed'} (id {shop_id})")
    if context:
        parts.append("----\n" + "\n".join(context))

    return "\n\n".join(parts)


def _derive_subject(category: str, subject: str | None, description: str) -> str:
    """A one-line triage title stored in ``complaints.subject`` (NOT NULL).

    An explicit subject wins; otherwise the first line the shopkeeper wrote is
    used, prefixed with the category label so an admin list view is scannable.
    Both are hard-capped to the column width (255) rather than truncated by the
    database.
    """
    explicit = _text(subject)
    if explicit:
        return explicit[:MAX_SUBJECT_LENGTH]

    first_line = next(
        (line.strip() for line in _text(description).splitlines() if line.strip()),
        "No description",
    )
    label = CATEGORIES[category]
    return f"[{label}] {first_line}"[:MAX_SUBJECT_LENGTH]


# ── Shop scoping ──────────────────────────────────────────────────────────
def _resolve_shop(db: Session, user: User, shop_id: int | None) -> Shop | None:
    """Authorizes ``shop_id`` for *user* and returns the shop row.

    Reuses the single shopkeeper authorization helper, so a ticket can never be
    filed against a shop the caller does not own or manage (IDOR). The location
    geometry is deferred: SQLite has no ``AsBinary()`` and the coordinates are
    irrelevant to filing a ticket.
    """
    if shop_id is None:
        return None
    from app.services import shopkeeper_service

    access = shopkeeper_service.resolve_shop_access(db, user, shop_id)
    return (
        db.query(Shop)
        .options(defer(Shop.location))
        .filter(Shop.id == access.shop.id)
        .first()
    )


# ── Serialization ─────────────────────────────────────────────────────────
def _attachment_filename(key: str | None) -> str | None:
    """The display filename for a stored media key.

    The key's last segment is ``{uuid8}_{safe-name}.{ext}`` (server-minted), so
    the readable name is everything after the first ``_``. Derived from the
    object the caller actually uploaded rather than from a request field, so a
    ticket can never display a filename for content it does not hold.
    """
    if not key:
        return None
    segment = key.rsplit("/", 1)[-1]
    _, _, safe = segment.partition("_")
    return safe or segment


def _serialize_attachment(complaint: Complaint) -> dict | None:
    """The attached evidence for a ticket, or None when none was attached.

    The stored KEY is exchanged for a short-lived presigned GET at
    serialization time (the same read strategy the catalog uses), so the URL a
    client receives is always fresh — an expired URL could never be persisted.
    """
    key = complaint.attachment_key
    if not key:
        return None
    meta = complaint.attachment_meta or {}
    from app.services import media_service

    return {
        "key": key,
        "url": media_service.resolve_media_url(key),
        "filename": meta.get("filename"),
        "content_type": meta.get("content_type"),
        "size_bytes": meta.get("size_bytes"),
    }


def serialize_ticket(complaint: Complaint, *, shop_name: str | None = None) -> dict:
    """The app-facing ticket payload.

    ``reference`` is the human-quotable ticket number; ``status`` is the raw
    backend value the app switches on, while ``status_label`` is the wording to
    display. Both are sent so the app never keeps its own copy of the status
    vocabulary.
    """
    return {
        "id": complaint.id,
        "reference": f"HL-{complaint.id}",
        "category": complaint.complaint_type,
        "category_label": CATEGORIES.get(complaint.complaint_type),
        "subject": complaint.subject,
        "description": complaint.description,
        "status": _status_code(complaint),
        "status_label": STATUS_LABELS.get(complaint.status),
        "priority": complaint.priority,
        "shop_id": complaint.entity_id,
        "shop_name": shop_name,
        "attachment": _serialize_attachment(complaint),
        "resolution_notes": complaint.resolution_notes,
        "resolved_at": _iso(complaint.resolved_at),
        "created_at": _iso(complaint.created_at),
        "updated_at": _iso(complaint.updated_at),
    }


def _shop_names(db: Session, complaints: list[Complaint]) -> dict[int, str]:
    """Bulk-resolves shop names for a page of tickets (one query, no N+1)."""
    shop_ids = {
        int(c.entity_id)
        for c in complaints
        if c.entity_type == "SHOP" and c.entity_id is not None
    }
    if not shop_ids:
        return {}
    rows = (
        db.query(Shop.id, Shop.name)
        .options(defer(Shop.location))
        .filter(Shop.id.in_(shop_ids))
        .all()
    )
    return {int(row[0]): row[1] for row in rows}


# ── Public API ────────────────────────────────────────────────────────────
def create_ticket(
    db: Session,
    *,
    user: User,
    category: str,
    description: str,
    priority: str | None = None,
    subject: str | None = None,
    steps: str | None = None,
    app_version: str | None = None,
    shop_id: int | None = None,
    attachment: dict | None = None,
) -> dict:
    """Files a support ticket for the signed-in shopkeeper.

    Opens in ``OPEN`` — the state support triages from — and is written to the
    hash-chained audit trail, because a ticket is the shopkeeper's record that
    they reported a problem and asked for help.

    ``attachment`` is the ALREADY-VALIDATED media grant for an optional
    screenshot (see the route: ``media_service.attach_media`` with the
    ``SUPPORT_ATTACHMENT`` category). Validation stays in the media service —
    which also performs the storage HEAD — so this function cannot be tricked
    into persisting a key that was never authorized or never uploaded.
    """
    code = normalize_category(category)
    shop = _resolve_shop(db, user, shop_id)
    attachment_key = (attachment or {}).get("key")

    complaint = Complaint(
        complainant_user_id=user.id,
        complaint_type=code,
        subject=_derive_subject(code, subject, description),
        description=_compose_description(
            description=description,
            steps=steps,
            app_version=app_version,
            shop_name=shop.name if shop is not None else None,
            shop_id=shop.id if shop is not None else None,
        ),
        entity_type="SHOP" if shop is not None else None,
        entity_id=shop.id if shop is not None else None,
        status=ComplaintStatus.OPEN,
        priority=normalize_priority(priority),
        attachment_key=attachment_key,
        attachment_meta=(
            {
                "filename": _attachment_filename(attachment_key),
                "content_type": attachment.get("content_type"),
                "size_bytes": attachment.get("size_bytes"),
            }
            if attachment
            else None
        ),
    )
    db.add(complaint)
    db.flush()

    from app.services import audit_service

    audit_service.record_critical_action(
        db,
        action="CREATE",
        entity_type="SUPPORT_TICKET",
        entity_id=complaint.id,
        user_id=user.id,
        new_values={
            "reference": f"HL-{complaint.id}",
            "category": complaint.complaint_type,
            "priority": complaint.priority,
            "shop_id": complaint.entity_id,
            "has_attachment": complaint.attachment_key is not None,
        },
        description=(
            f"Support ticket HL-{complaint.id} filed from the shopkeeper app "
            f"({CATEGORIES[code]})"
        ),
    )
    db.commit()
    db.refresh(complaint)

    return serialize_ticket(
        complaint, shop_name=shop.name if shop is not None else None
    )


def list_my_tickets(
    db: Session,
    *,
    user: User,
    status: str | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    """Tickets filed by *user*, newest first, optionally filtered by status.

    Scoped to ``complainant_user_id`` — an admin's complaints view is a separate,
    permission-gated surface, so no other reporter's ticket can leak into this
    list.
    """
    query = db.query(Complaint).filter(Complaint.complainant_user_id == user.id)

    wanted = _text(status)
    if wanted:
        try:
            query = query.filter(Complaint.status == ComplaintStatus(wanted.upper()))
        except ValueError as exc:
            raise ValidationError(
                f"Unknown ticket status: {status}",
                data={"allowed_statuses": [s.value for s in ComplaintStatus]},
            ) from exc

    total = query.count()
    rows = (
        query.order_by(Complaint.id.desc())
        .offset(max(offset, 0))
        .limit(max(1, min(limit, 200)))
        .all()
    )

    names = _shop_names(db, rows)
    tickets = [
        serialize_ticket(
            row,
            shop_name=(
                names.get(int(row.entity_id)) if row.entity_id is not None else None
            ),
        )
        for row in rows
    ]
    return tickets, total


def get_ticket(db: Session, *, user: User, ticket_id: int) -> dict:
    """One ticket owned by *user*.

    A ticket that exists but belongs to someone else raises the SAME 404 as a
    missing one: whether another merchant has ticket ``N`` is not something an
    unauthorized caller may learn.
    """
    complaint = (
        db.query(Complaint)
        .filter(
            Complaint.id == ticket_id,
            Complaint.complainant_user_id == user.id,
        )
        .first()
    )
    if complaint is None:
        raise NotFoundError("Support ticket not found")

    name = None
    if complaint.entity_type == "SHOP" and complaint.entity_id is not None:
        row = (
            db.query(Shop.name)
            .options(defer(Shop.location))
            .filter(Shop.id == complaint.entity_id)
            .first()
        )
        name = row[0] if row is not None else None

    return serialize_ticket(complaint, shop_name=name)




