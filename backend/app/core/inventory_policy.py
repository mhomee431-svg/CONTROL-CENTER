"""Shared inventory constants.

Kept in its own module so the inventory router and the dashboard agree on what
"stale" means; two copies of this number would eventually drift.
"""

STALE_AFTER_HOURS = 72
