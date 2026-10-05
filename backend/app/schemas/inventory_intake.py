"""Phase 24 — Pydantic schemas for barcode + Excel inventory intake."""

from pydantic import BaseModel, Field


class BarcodeSaveRequest(BaseModel):
    """Confirm-and-save payload after a successful barcode scan."""

    barcode: str | None = Field(None, max_length=100, description="Scanned code (audit)")
    product_master_id: int = Field(..., ge=1)
    variant_id: int | None = Field(None, ge=1)
    price: float = Field(..., ge=0)
    mrp: float | None = Field(None, ge=0)
    sku: str | None = Field(None, max_length=100)
    quantity: int = Field(0, ge=0)
    low_stock_threshold: int = Field(5, ge=0)
    is_available: bool = True
    publish: bool = True


class ImportJobListResponse(BaseModel):
    job_ids: list[int]


class ColumnMappingRequest(BaseModel):
    """A corrected Column Mapping: HyperLocal field -> column index.

    Keyed by FIELD rather than by column, because the question the shopkeeper is
    answering is "what is this column?" and two columns may carry the same field
    name before the ambiguity is resolved.

    A `null` value means "do not import this field" — a legitimate answer for an
    optional column, and not an error.
    """

    column_mapping: dict[str, int | None] = Field(
        default_factory=dict,
        description=(
            "Canonical field name (e.g. 'price') to ZERO-BASED column index in "
            "the uploaded header row. Omit or null a field to skip it."
        ),
    )
