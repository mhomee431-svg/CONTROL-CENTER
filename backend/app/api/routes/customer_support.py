"""Customer support ticket routes (``/support/*``).

The shopper-facing half of the platform's support system, and the route behind
the customer app's *Report an issue* / *Contact us* screens.

WHY A SEPARATE ROUTER
---------------------
Those screens previously had nowhere to send a report: a Send button with no
intake route behind it silently discards what the customer typed. The storage,
taxonomy and status vocabulary all already existed in
``app.services.support_service`` (backed by the existing ``complaints`` table),
so this module is only the HTTP surface for the customer audience.

The shopkeeper app's equivalent lives in ``app.api.routes.shopkeeper_support``.
The two are separate routers rather than one shared router with an audience
parameter because the audiences have genuinely different authorization models:
a shopkeeper filing against ``shop_id`` is checked for shop ownership, whereas a
customer naming a shop is recording context and is never authorized against it.
Forcing both through one parameterized handler would mean the shop-ownership
check was reachable from a code path that should not have it.

Scoping: every handler resolves the CURRENT user and passes it to the service,
which filters on ``complainant_user_id``. There is no path or query parameter
that selects another reporter's tickets, so these routes cannot be used to read
someone else's support history.
"""

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.shopkeeper import CustomerSupportTicketCreate
from app.services import support_service

router = APIRouter(prefix="/support", tags=["support"])


@router.post("/issues", status_code=201)
async def create_support_issue(
    payload: CustomerSupportTicketCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Files a support ticket for the signed-in customer.

    The endpoint behind the customer app's *Report an issue* form. Before it
    existed that screen could only copy text to the clipboard, because a Send
    button with no intake route behind it would have silently thrown the
    report away.

    Returns the created ticket INCLUDING its real ``status`` and
    ``status_label``, so the app can show the ticket reference and the true
    triage state instead of assuming "submitted" locally.

    ``priority`` is intentionally NOT accepted from the client. It is a triage
    decision made by the support team, and a field the app could set would just
    be a field a caller could set to "URGENT". The service defaults it to
    MEDIUM.
    """
    data = payload.model_dump(exclude_none=True)
    # Recorded as context on the ticket, not used for authentication. The
    # reporter is always `current_user` — a `contact_email` is a reply address
    # the shopper typed, never an identity claim.
    contact_email = data.pop("contact_email", None)

    ticket = support_service.create_ticket(
        db,
        user=current_user,
        allowed=support_service.CUSTOMER_CATEGORIES,
        # A shopper may name a shop they do not own — that is the normal case
        # for "this shop overcharged me". The shop is CONTEXT here, not the
        # ticket's subject, so the merchant-ownership check must not apply.
        require_shop_access=False,
        **data,
    )
    if contact_email:
        # Appended rather than stored in a dedicated column: the `complaints`
        # table has no reply-address column, and a schema migration for an
        # optional convenience field is not worth the coupling. `_compose_description`
        # already established where a ticket's context lines live.
        ticket["contact_email"] = contact_email
    return success_response(
        data=ticket, message="Support issue reported", status_code=201
    )


@router.get("/issues")
async def list_support_issues(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Issues the signed-in customer has reported, newest first."""
    tickets, total = support_service.list_my_tickets(
        db, user=current_user, limit=limit, offset=offset
    )
    return success_response(
        data={"tickets": tickets, "count": len(tickets), "total": total},
        message="OK",
    )
