/**
 * Dashboard Filter Contract
 *
 * Section: "DASHBOARD FILTERS — Only show filters supported by backend."
 *
 * The backend is the single source of truth. This registry declares, per filter,
 * the exact query parameter the FastAPI admin layer accepts. A filter is only
 * rendered when it is declared here, so we never surface a control the backend
 * would silently ignore.
 *
 * Adding a new filter = add an entry here + add the matching param to the
 * query. Nothing else in the UI needs to change.
 */

export type DashboardFilterKey =
  | 'city'
  | 'state'
  | 'category'
  | 'business_type'
  | 'date_range'
  | 'shop_status'
  | 'customer_status';

export type DashboardFilterValue = string;

/** Serialized filter state: only keys with a non-empty value are meaningful. */
export type DashboardFilterState = Partial<Record<DashboardFilterKey, DashboardFilterValue>>;

export interface SelectOption {
  value: string;
  label: string;
}

export interface DashboardFilterDefinition {
  key: DashboardFilterKey;
  /** Human label rendered in the filter bar. */
  label: string;
  /** Exact backend query parameter name. */
  param: string;
  /** Options, when the filter is an enum the backend validates server-side. */
  options?: SelectOption[];
  /** True when the option list must be loaded from the backend. */
  dynamicOptions?: boolean;
  /** Endpoint supplying the options for `dynamicOptions` filters. */
  optionsEndpoint?: string;
  helpText?: string;
}

/**
 * Date range is owned by the centralized analytics date-range module
 * (`core/filters/dateRange.ts`) and serialized as `days`, matching the backend's
 * analytics contract (`GET /api/v1/admin/analytics/summary?days=30`).
 *
 * This registry deliberately does NOT define its own option list — options come
 * from DATE_RANGE_PRESETS so presets can never drift between components.
 */
export const DATE_RANGE_PARAM = 'days';

export { DATE_RANGE_PRESETS } from './dateRange';

/** Mirrors `UserStatus` in core/types/admin.ts — backend-authoritative enum. */
export const CUSTOMER_STATUS_OPTIONS: SelectOption[] = [
  { value: 'ACTIVE', label: 'Active' },
  { value: 'INACTIVE', label: 'Inactive' },
  { value: 'SUSPENDED', label: 'Suspended' },
  { value: 'BANNED', label: 'Banned' },
  { value: 'PENDING', label: 'Pending' },
];

/** Mirrors `ShopStatus` in core/types/admin.ts — backend-authoritative enum. */
export const SHOP_STATUS_OPTIONS: SelectOption[] = [
  { value: 'ACTIVE', label: 'Active' },
  { value: 'INACTIVE', label: 'Inactive' },
  { value: 'SUSPENDED', label: 'Suspended' },
  { value: 'PENDING', label: 'Pending' },
  { value: 'REJECTED', label: 'Rejected' },
];

/**
 * The backend ships no `business_type` enum contract, so the business-type
 * filter is intentionally NOT declared. Enabling it here (with an explicit
 * option list) is the one and only change required once the backend
 * advertises `business_type` on the dashboard/metrics and shops endpoints.
 */
export const DASHBOARD_FILTERS: DashboardFilterDefinition[] = [
  {
    key: 'date_range',
    label: 'Date Range',
    param: DATE_RANGE_PARAM,
    // Options are supplied by the DateRangeProvider (presets + custom picker),
    // not declared here, so the window control lives in exactly one place.
    dynamicOptions: true,
    helpText: 'Reporting window applied to every metric on this dashboard.',
  },
  {
    key: 'city',
    label: 'City',
    param: 'city',
    dynamicOptions: true,
    optionsEndpoint: '/api/v1/admin/shops',
    helpText: 'Scoped to shops in the selected city.',
  },
  {
    key: 'state',
    label: 'State',
    param: 'state',
    dynamicOptions: true,
    optionsEndpoint: '/api/v1/admin/shops',
    helpText: 'Scoped to shops in the selected state.',
  },
  {
    key: 'category',
    label: 'Category',
    param: 'category',
    dynamicOptions: true,
    optionsEndpoint: '/api/v1/admin/categories',
    helpText: 'Top-level catalog category scope.',
  },
  {
    key: 'shop_status',
    label: 'Shop Status',
    param: 'shop_status',
    options: SHOP_STATUS_OPTIONS,
  },
  {
    key: 'customer_status',
    label: 'Customer Status',
    param: 'customer_status',
    options: CUSTOMER_STATUS_OPTIONS,
  },
];

export function getDashboardFilter(key: DashboardFilterKey): DashboardFilterDefinition | undefined {
  return DASHBOARD_FILTERS.find((f) => f.key === key);
}

/**
 * Convert UI filter state into backend query params.
 *
 * Empty/undefined values are dropped so the backend applies its own default
 * rather than receiving `city=` and filtering on an empty string.
 */
export function toFilterParams(
  filters: DashboardFilterState,
  definitions: DashboardFilterDefinition[] = DASHBOARD_FILTERS
): Record<string, string> {
  const params: Record<string, string> = {};
  definitions.forEach((def) => {
    const value = filters[def.key];
    if (value !== undefined && value !== null && value !== '') {
      params[def.param] = value;
    }
  });
  return params;
}

export function countActiveFilters(filters: DashboardFilterState): number {
  return DASHBOARD_FILTERS.filter((def) => {
    const v = filters[def.key];
    return v !== undefined && v !== null && v !== '';
  }).length;
}

export function isDefaultDashboardFilters(filters: DashboardFilterState): boolean {
  return countActiveFilters(filters) === 0;
}