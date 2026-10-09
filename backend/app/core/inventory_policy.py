"""Shared inventory constants.

Kept in its own module so the inventory router and the dashboard agree on what
"stale" means; two copies of this number would eventually drift.
"""

STALE_AFTER_HOURS = 72
# A record updated inside this window counts as FRESH; between FRESH and
# STALE it counts as RECENT. Both feed the freshness dashboard tiles.
FRESH_WITHIN_HOURS = 24
# At or below this quantity a record is LOW STOCK rather than in stock.
LOW_STOCK_THRESHOLD = 10
