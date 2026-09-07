"""Domain entities — pure business objects independent of ORM/Framework."""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional


class UserStatus(str, Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    SUSPENDED = "suspended"
    BANNED = "banned"


class ShopStatus(str, Enum):
    PENDING = "pending"
    ACTIVE = "active"
    SUSPENDED = "suspended"
    REJECTED = "rejected"


class ProductStatus(str, Enum):
    DRAFT = "draft"
    ACTIVE = "active"
    INACTIVE = "inactive"
    ARCHIVED = "archived"


@dataclass
class User:
    id: Optional[int] = None
    phone_number: str = ""
    email: Optional[str] = None
    full_name: Optional[str] = None
    status: UserStatus = UserStatus.ACTIVE
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class Shop:
    id: Optional[int] = None
    name: str = ""
    owner_id: Optional[int] = None
    status: ShopStatus = ShopStatus.PENDING
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class Product:
    id: Optional[int] = None
    name: str = ""
    brand: Optional[str] = None
    category: Optional[str] = None
    barcode: Optional[str] = None
    status: ProductStatus = ProductStatus.ACTIVE
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class ShopProduct:
    id: Optional[int] = None
    shop_id: int = 0
    product_id: int = 0
    price: float = 0.0
    is_available: bool = True
    stock_quantity: int = 0
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None