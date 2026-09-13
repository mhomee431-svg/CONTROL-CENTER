from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.core.responses import success_response
from app.database.session import get_db
from app.models.user import User
from app.schemas.profile import ProfileResponse, ProfileUpdate

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("")
async def get_profile(
    current_user: User = Depends(get_current_user),
):
    """Return the current user's profile.

    IDOR-safe: the authenticated user is derived from the verified Firebase
    token — never from client input. No user_id parameter is accepted.
    """
    return success_response(data=ProfileResponse.model_validate(current_user).model_dump())


@router.put("")
async def update_profile(
    payload: ProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update the current user's profile.

    IDOR-safe: updates only the authenticated user (from verified token).
    Accepts partial updates — only provided fields are changed.
    """
    if payload.name is not None:
        current_user.name = payload.name
    if payload.email is not None:
        current_user.email = payload.email
    if payload.avatar_url is not None:
        current_user.avatar_url = payload.avatar_url

    db.add(current_user)
    db.commit()
    db.refresh(current_user)

    return success_response(
        data=ProfileResponse.model_validate(current_user).model_dump(),
        message="Profile updated",
    )


@router.patch("")
async def patch_profile(
    payload: ProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Partial-update the current user's profile (alias for PUT).

    IDOR-safe: the user is derived from the verified Firebase token.
    Only fields present in the payload are applied — omitted fields are left
    unchanged.
    """
    if payload.name is not None:
        current_user.name = payload.name
    if payload.email is not None:
        current_user.email = payload.email
    if payload.avatar_url is not None:
        current_user.avatar_url = payload.avatar_url

    db.add(current_user)
    db.commit()
    db.refresh(current_user)

    return success_response(
        data=ProfileResponse.model_validate(current_user).model_dump(),
        message="Profile updated",
    )
