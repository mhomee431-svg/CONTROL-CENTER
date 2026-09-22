# Shopkeeper App — Analytics / Reports Metrics Coverage

Scope: `apps/shopkeeper_app` Reports & Insights screens.
Backend: `backend/app/api/routes/shopkeeper_analytics.py`
(`GET /api/v1/shopkeeper/shops/{id}/analytics/full` + drill-down routes).

## Contract

**Real data only. No fake sales / revenue charts.**

- Every value on the Reports screen is computed server-side from the
  analytics event stream: **shop views, product clicks, customer
  interactions, top searches, device breakdown, hourly distribution and
  inventory freshness**.
- The client never fabricates a metric. An absent / unknown backend
  section parses to an empty or zero-valued model (`InsightsBundle.fromJson`
  + `InsightsOverview` / `InventoryFreshness` / `InteractionBreakdown` /
  `DeviceBreakdown` all default-empty), so the UI renders an honest empty
  state instead of an invented number.
- `InsightsBundle.hasActivity` drives the single
  "No customer activity yet." empty state.
- Pinned by `test/analytics_real_data_test.dart` (model-level): empty
  payload -> all zeros/empty + `hasActivity == false`; a `revenue` field in
  the payload is **ignored** (the Sales report is engagement-only).

## Metric coverage

| Metric | Source / endpoint | Rendered | Notes |
|---|---|---|---|
| Product views | `views_timeseries` (drill-down `views`) | YES | KPI + daily series + hour-of-day distribution |
| Shop views | `views_timeseries` (drill-down `views`) | YES | KPI + daily series + hour-of-day distribution |
| Search appearances | `top_searches` (list of `{query,count}`) | YES | Searches card (non-zero terms only) |
| Inventory updates | `freshness` (fresh/stale/total) + `GET /inventory` | YES (honest substitute) | Backend exposes a freshness score, not an "inventory updates" count -> app shows `X fresh · Y stale`; never an invented counter |
| Top products | `top_products` (up to 50 rows drill-down) | YES | Clicks drill-down ranked list |
| Availability trends | none | NO (not available server-side) | No backend endpoint exists. The app does **not** surface this section rather than fabricate it |
| Sales / revenue | `revenue` key in admin payload only | EXCLUDED by design | Analytics carry no revenue fields. The "Sales report" tile is customer engagement only, with the disclaimer: "Sales totals and revenue are not available. The metrics below show customer engagement, not completed sales." |

## Business insights (live shop snapshot)

Separate from the customer-activity report above, the shopkeeper app renders
**business-insight cards**: top products, low stock, stale inventory, product
search visibility, offers performance and profile completeness.

- Endpoint: `GET /api/v1/shopkeeper/shops/{id}/insights`
  (`backend/app/api/routes/shopkeeper_portal.py` →
  `shopkeeper_service.business_insights`), permission `dashboard:read`.
- **Real data only**: every metric is computed server-side from the live
  database — listings, `inventory.quantity` vs `low_stock_threshold`, staleness
  of `last_inventory_update` / `last_price_update`, listing status visibility,
  `offers` + `offer_products`, and the shop profile columns. No estimates.
- These cards are a **live snapshot**, not windowed: the trailing-window
  selector (7 / 30 / 90 days) applies to the analytics sections only, which the
  section sub-heading states.
- Pinned by `test/business_insights_test.dart` (insight models + section
  widgets) and the backend `tests/test_shopkeeper_app.py` insights cases.

| Card id | Source metrics | Rendered |
|---|---|---|
| `top_products` | active listings ranked by stock value + recency, `ranked_count` | YES (headline + rows) |
| `low_stock` | `quantity <= low_stock_threshold`, `total_gap_units` | YES (headline + rows + restock nudge) |
| `stale_inventory` | no inventory/price touch for 30 days, `oldest_stale_days` | YES |
| `search_visibility` | active + approved/active status, `products_without_images` | YES (percentage headline) |
| `offers_performance` | active/draft/expiring counts, catalog coverage | YES |
| `profile_completeness` | 12 profile fields, `missing_fields_count` | YES (missing-field list) |

**Empty-state rules:** a card the backend classifies `healthy` with nothing
flagged is skipped — the backend always sends all six, so the app renders only
the ones that carry something. When the payload contains no cards at all the
section is hidden; a failed insights sub-call renders "Insights unavailable"
(the analytics report still renders normally), never an empty shop.


## Empty-state handling

- Whole screen, no activity -> `InsightsStatus.ready` + "No customer activity yet." card.
- Per-section, empty -> `_EmptyLine(...)`.
- Loading -> CircularProgressIndicator; errors -> retryable message view; access denied -> distinct 403 state.
