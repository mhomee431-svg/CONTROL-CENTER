"""User Interactions / Leads routes.

Implements the "Public Browse + Action-Triggered Verification" gate:

  * ``POST /api/v1/interactions/action`` — REQUIRES a valid JWT. This is the
    verification gate: an unauthenticated customer receives 401 and must
    verify via phone OTP or Google login before the action is recorded.
  * Records are CREATE-ONLY — there is intentionally no update or delete
    route for customers (Immutable Actions Rule).
  * ``GET /api/v1/interactions/me`` — customer's own interactions (read-only).
  * ``GET /api/v1/interactions/shop/{shop_id}`` — public, read-only shop
    ratings/reviews for the browsable UI (no auth required).
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.exceptions import AppError
from app.core.responses import error_response, success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.interaction import InteractionCreateRequest
from app.services import interaction_service

router = APIRouter(prefix="/interactions", tags=["interactions"])


@router.post("/action", status_code=201)
async def create_action(
    payload: InteractionCreateRequest,
    current_user: User = Depends(get_current_user),  # ← the verification gate
    db: Session = Depends(get_db),
):
    """Record a verified customer action (view contact / message / rating).

    Requires a valid JWT (phone-OTP or Google login). Create-only.
    """
    try:
        data = interaction_service.create_interaction(
            db,
            user=current_user,
            shop_id=payload.shop_id,
            action_type=payload.action_type,
            message_content=payload.message_content,
            rating=payload.rating,
        )
    except AppError as exc:
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )

    db.commit()
    return success_response(data=data, message="Action recorded", status_code=201)


@router.get("/me")
async def my_interactions(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Read-only list of the current customer's interactions."""
    rows = interaction_service.list_customer_interactions(db, current_user)
    return success_response(data={"interactions": rows}, message="OK")


@router.get("/shop/{shop_id}")
async def shop_reviews(
    shop_id: int,
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """Public, read-only shop ratings & reviews (browse without login)."""
    try:
        data = interaction_service.list_shop_reviews(db, shop_id, limit=limit)
    except AppError as exc:
        return error_response(
            message=exc.message,
            error_code=exc.error_code,
            status_code=exc.status_code,
        )
    return success_response(data=data, message="OK")