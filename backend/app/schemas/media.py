"""Phase 7 — Media upload request/response schemas."""

from typing import Optional

from pydantic import BaseModel, Field


class MediaUploadURLRequest(BaseModel):
    """Request a signed upload grant for one object.

    The size is declared up-front and enforced twice: as a
    ``content-length-range`` condition inside the S3 policy, and re-checked
    against the stored object at confirm time.
    """

    category: str = Field(..., min_length=1, max_length=32, description="PRODUCT_IMAGE | SHOP_IMAGE | DOCUMENT")
    filename: str = Field(..., min_length=1, max_length=255)
    content_type: str = Field(..., min_length=3, max_length=100, description="MIME type, e.g. image/jpeg")
    size_bytes: int = Field(..., ge=1, le=64 * 1024 * 1024)
    shop_id: Optional[int] = Field(None, ge=1, description="Required for shop-scoped categories")


class MediaConfirmRequest(BaseModel):
    """Confirm that a signed upload completed; get back a read URL."""

    key: str = Field(..., min_length=8, max_length=512)


class MediaAttachRequest(BaseModel):
    """Attach an uploaded (and confirmed) media key to a product or shop.

    The key must have been produced by this backend's signed-upload flow and
    must be scoped to a shop the caller is authorized for.
    """

    key: str = Field(..., min_length=8, max_length=512)
    target_type: str = Field(..., pattern="^(product|shop)$")
    product_master_id: Optional[int] = Field(None, ge=1)
    shop_id: Optional[int] = Field(None, ge=1, description="Target shop (required for both target types)")
    field: str = Field("image", max_length=12, description="Shop target column: image | cover | logo")
