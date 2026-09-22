"""Shopkeeper support ticket routes (``/shopkeeper/support/*``).

The shopkeeper-facing half of the platform's support/complaints system. The
storage, taxonomy and status vocabulary all live in
``app.services.support_service`` (backed by the existing ``complaints`` table);
this module is only the HTTP surface for them.

Scoping: every handler resolves the CURRENT user and passes it to the service,
which filters on ``complainant_user_id``. There is no path/query parameter that
selects another reporter's tickets, so the routes cannot be used to read someone
else's support history.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import AppError
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.shopkeeper import ShopkeeperSupportTicketCreate
from app.services import media_service, support_service

router = APIRouter(prefix="/shopkeeper/support", tags=["shopkeeper-support"])

# The only media category a support ticket accepts. Product/shop images can
# never be re-purposed as ticket evidence, and vice versa.
SUPPORT_ATTACHMENT_CATEGORY = "SUPPORT_ATTACHMENT"


async def _resolve_attachment(
    db: Session, user: User, key: str | None
) -> dict | None:
    """Validate an optional screenshot key against the media pipeline.

    Delegates to ``media_service.attach_media``, which enforces the key shape,
    the category (``SUPPORT_ATTACHMENT``) and the SELF scope, then HEADs the
    object so a phantom key cannot be referenced. Always returns ``None`` for
    no key, so the caller can pass the result straight through to the service.
    """
    if not key:
        return None
    return await media_service.attach_media(
        db, user, key=key, expected_category=SUPPORT_ATTACHMENT_CATEGORY
    )


@router.post("/tickets", status_code=201)
async def create_support_ticket(
    payload: ShopkeeperSupportTicketCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Files a support ticket for the signed-in shopkeeper.

    Returns the created ticket INCLUDING its ``status`` and ``status_label``, so
    the app can show the ticket reference and the real triage state immediately
    instead of assuming "submitted" locally. An optional screenshot is validated
    through the media pipeline FIRST — a rejected attachment never leaves a
    half-filed ticket behind.
    """
    data = payload.model_dump(exclude_none=True)
    attachment_key = data.pop("attachment_key", None)

    try:
        attachment = await _resolve_attachment(db, current_user, attachment_key)
    except AppError as exc:
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
            data=getattr(exc, "data", None),
        )

    ticket = support_service.create_ticket(
        db,
        user=current_user,
        attachment=attachment,
        **data,
    )
    return success_response(
        data=ticket, message="Support ticket created", status_code=201
    )


@router.get("/tickets")
async def list_support_tickets(
    status: str | None = Query(
        None, description="Filter by status (OPEN, IN_PROGRESS, RESOLVED, ...)"
    ),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Tickets filed by the signed-in shopkeeper, newest first."""
    tickets, total = support_service.list_my_tickets(
        db, user=current_user, status=status, limit=limit, offset=offset
    )
    return success_response(
        data={"tickets": tickets, "count": len(tickets), "total": total},
        message="OK",
    )


@router.get("/tickets/{ticket_id}")
async def get_support_ticket(
    ticket_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """One ticket filed by the signed-in shopkeeper (404 if it is not theirs)."""
    ticket = support_service.get_ticket(db, user=current_user, ticket_id=ticket_id)
    return success_response(data=ticket, message="OK")
