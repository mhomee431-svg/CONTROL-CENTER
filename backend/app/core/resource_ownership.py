"""Resource ownership verification helpers.

Provides IDOR (Insecure Direct Object Reference) prevention by verifying
that users can only access resources they own or are authorized to access.

Usage:
    @router.put("/shops/{shop_id}/products/{product_id}")
    def update_product(
        shop_id: int,
        product_id: int,
        db: Session = Depends(get_db),
        user: User = Depends(get_current_user),
    ):
        # Verify shop ownership
        verify_shop_ownership(db, user, shop_id)
        # Verify product belongs to shop
        verify_product_in_shop(db, product_id, shop_id)
        # ... proceed with update
"""
import logging
from typing import Optional

from sqlalchemy.orm import Session

from app.core.exceptions import ForbiddenError, NotFoundError
from app.models.product import ShopProduct
from app.models.shop import Shop, ShopManager, ShopOwner

logger = logging.getLogger("app.core.resource_ownership")


def verify_shop_ownership(
    db: Session,
    user,
    shop_id: int,
    *,
    require_owner: bool = False,
) -> Shop:
    """Verify user owns or manages a shop.
    
    Args:
        db: Database session
        user: Current user
        shop_id: Shop ID to verify
        require_owner: If True, only owner can access (not managers)
    
    Returns:
        Shop object if authorized
    
    Raises:
        NotFoundError: Shop doesn't exist
        ForbiddenError: User not authorized
    """
    shop = db.query(Shop).filter(Shop.id == shop_id).first()
    if shop is None:
        raise NotFoundError(f"Shop {shop_id} not found")
    
    # Admin can access any shop
    if user.role is not None and user.role.name in ("admin", "admin_support", "admin_moderator"):
        return shop
    
    # Check ownership
    is_owner = (
        db.query(ShopOwner)
        .filter(
            ShopOwner.shop_id == shop_id,
            ShopOwner.user_id == user.id,
            ShopOwner.is_active == True,  # noqa: E712
        )
        .first()
        is not None
    )
    
    if is_owner:
        return shop
    
    if require_owner:
        raise ForbiddenError("Only the shop owner can perform this action")
    
    # Check management
    is_manager = (
        db.query(ShopManager)
        .filter(
            ShopManager.shop_id == shop_id,
            ShopManager.user_id == user.id,
            ShopManager.is_active == True,  # noqa: E712
        )
        .first()
        is not None
    )
    
    if is_manager:
        return shop
    
    raise ForbiddenError("You don't have access to this shop")


def verify_product_in_shop(
    db: Session,
    product_id: int,
    shop_id: int,
) -> ShopProduct:
    """Verify a product belongs to a specific shop.
    
    Args:
        db: Database session
        product_id: Shop product ID
        shop_id: Expected shop ID
    
    Returns:
        ShopProduct object
    
    Raises:
        NotFoundError: Product doesn't exist or doesn't belong to shop
    """
    shop_product = (
        db.query(ShopProduct)
        .filter(ShopProduct.id == product_id)
        .first()
    )
    
    if shop_product is None:
        raise NotFoundError(f"Product {product_id} not found")
    
    if shop_product.shop_id != shop_id:
        logger.warning(
            "Product %d does not belong to shop %d (actual: %d)",
            product_id, shop_id, shop_product.shop_id,
        )
        raise NotFoundError(f"Product {product_id} not found in this shop")
    
    return shop_product


def verify_user_ownership(
    db: Session,
    user,
    target_user_id: int,
) -> None:
    """Verify user is accessing their own resource.
    
    Args:
        db: Database session
        user: Current user
        target_user_id: User ID being accessed
    
    Raises:
        ForbiddenError: User accessing another user's resource
    """
    if user.id == target_user_id:
        return
    
    # Admin can access any user
    if user.role is not None and user.role.name.startswith("admin"):
        return
    
    raise ForbiddenError("You can only access your own resources")


def get_accessible_shop_ids(db: Session, user) -> list[int]:
    """Get list of shop IDs the user can access.
    
    Args:
        db: Database session
        user: Current user
    
    Returns:
        List of accessible shop IDs
    """
    # Admin can access all shops
    if user.role is not None and user.role.name.startswith("admin"):
        return [s.id for s in db.query(Shop).filter(Shop.is_deleted == False).all()]  # noqa: E712
    
    # Get owned shops
    owner_ids = [
        r.shop_id
        for r in db.query(ShopOwner.shop_id).filter(
            ShopOwner.user_id == user.id,
            ShopOwner.is_active == True,  # noqa: E712
        ).all()
    ]
    
    # Get managed shops
    manager_ids = [
        r.shop_id
        for r in db.query(ShopManager.shop_id).filter(
            ShopManager.user_id == user.id,
            ShopManager.is_active == True,  # noqa: E712
        ).all()
    ]
    
    return list(set(owner_ids + manager_ids))


def can_access_shop(db: Session, user, shop_id: int) -> bool:
    """Check if user can access a shop (without raising exceptions)."""
    try:
        verify_shop_ownership(db, user, shop_id)
        return True
    except (NotFoundError, ForbiddenError):
        return False
