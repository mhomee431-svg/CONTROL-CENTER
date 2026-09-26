"""Search text normalization — tokenization, accent folding, trigram-friendly slugs."""

import re
import unicodedata

# ── Config ──────────────────────────────────────────────────────────────────
STOP_WORDS = {
    "the", "a", "an", "and", "or", "for", "in", "on", "at", "to", "of",
    "with", "by", "from", "is", "are", "was", "were", "be", "this", "that",
}

# Common brand/product tokens that map to the same normalized form
SYNONYM_MAP: dict[str, str] = {
    "coca cola": "cocacola",
    "coca-cola": "cocacola",
    "fanta": "fanta",
    "lays": "lays",
    "lays classic": "lays classic",
    "bhuijia": "bhujia",
    "bhujia": "bhujia",
}


def normalize_text(text: str | None) -> str:
    """Normalize text: lowercase, accent-fold, remove punctuation/extra whitespace."""
    if not text:
        return ""
    # Unicode NFKD normalization + strip combining marks (accent folding)
    normalized = unicodedata.normalize("NFKD", str(text))
    normalized = "".join(c for c in normalized if not unicodedata.combining(c))
    # Lowercase
    normalized = normalized.lower()
    # Replace non-alphanumeric with space
    normalized = re.sub(r"[^a-z0-9]+", " ", normalized)
    # Collapse whitespace
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def tokenize(text: str | None) -> list[str]:
    """Return list of noiseless tokens from text."""
    norm = normalize_text(text)
    if not norm:
        return []
    tokens = norm.split()
    # Remove stop words and very short tokens (len < 2)
    return [t for t in tokens if t not in STOP_WORDS and len(t) >= 2]


def build_discovery_text(
    product_name: str | None,
    *,
    brand: str | None = None,
    category: str | None = None,
    subcategory: str | None = None,
    variant: str | None = None,
    sku: str | None = None,
    identifiers: list[str | None] | tuple[str | None, ...] | None = None,
) -> str:
    """Build the canonical product-discovery document.

    Normal matching understands how customers name products: product name,
    brand, category/subcategory, variant, SKU, and active identifiers such as
    EAN/UPC. Description, material, and detailed specifications are excluded so
    ordinary product-name search never depends on attribute-level metadata.
    """
    parts: list[str | None] = [
        product_name,
        brand,
        category,
        subcategory,
        variant,
        sku,
    ]
    parts.extend(identifiers or ())
    return " ".join(
        normalized
        for normalized in (normalize_text(part) for part in parts if part)
        if normalized
    )


def build_search_text(product_name: str | None, brand: str | None = None, category: str | None = None,
                      variant: str | None = None, subcategory: str | None = None, sku: str | None = None,
                      barcode: str | None = None, description: str | None = None) -> str:
    """Build the legacy all-field projection kept for compatibility."""
    parts = [
        product_name,
        brand,
        category,
        subcategory,
        variant,
        description,
        sku,
        barcode,
    ]
    return " ".join(normalize_text(p) for p in parts if p)


def similarity_threshold(query_len: int) -> float:
    """Return the pg_trgm similarity threshold based on query length."""
    if query_len <= 3:
        return 0.5
    if query_len <= 5:
        return 0.4
    if query_len <= 8:
        return 0.3
    return 0.25


def is_barcode_query(query: str) -> bool:
    """Detect if a query looks like a barcode (all digits, length >= 6)."""
    q = query.strip()
    return len(q) >= 6 and q.isdigit()