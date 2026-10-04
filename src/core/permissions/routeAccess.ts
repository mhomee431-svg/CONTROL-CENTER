import { CAPABILITIES, Capability } from './permissions';

/**
 * Centralized route-level authorization map (Section 8 / 138).
 *
 * Individual pages must not hardcode permission checks for "can this admin open
 * this page". This registry is the single source of truth for which capability
 * unlocks which area of the control center, and `<RouteGuard />` enforces it for
 * every route under the dashboard layout in one place.
 *
 * Keys are route prefixes WITHOUT dynamic segments (`/customers/[id]` is covered
 * by `/customers`). Unmapped routes stay visible to every authenticated admin;
 * their individual actions are still gated by `<PermissionGuard />` in the page.
 */
export const ROUTE_CAPABILITIES: Record<string, Capability> = {
  // People
  '/customers': CAPABILITIES.CUSTOMERS_READ,
  '/shopkeepers': CAPABILITIES.SHOPS_READ,

  // Businesses & discovery footprint
  '/businesses': CAPABILITIES.SHOPS_READ,
  '/verification': CAPABILITIES.SHOPS_READ,
  '/locations': CAPABILITIES.SHOPS_READ,

  // Catalog
  '/products': CAPABILITIES.PRODUCTS_READ,
  '/categories': CAPABILITIES.TAXONOMY_READ,
  '/brands': CAPABILITIES.TAXONOMY_READ,

  // Inventory & pricing operations
  '/inventory': CAPABILITIES.INVENTORY_READ,
  '/pricing': CAPABILITIES.INVENTORY_READ,
  '/imports': CAPABILITIES.INVENTORY_READ,
  '/pos': CAPABILITIES.INVENTORY_READ,

  // Monetization
  '/offers': CAPABILITIES.OFFERS_READ,
  '/subscriptions': CAPABILITIES.SUBSCRIPTIONS_READ,

  // Engagement & governance
  '/support': CAPABILITIES.SUPPORT_READ,
  '/audit': CAPABILITIES.AUDIT_READ,

  // Analytics
  '/analytics': CAPABILITIES.ANALYTICS_READ,

  // Administration & platform configuration
  '/admin-users': CAPABILITIES.ADMINS_READ,
  '/system/settings': CAPABILITIES.SETTINGS_READ,
  '/system/flags': CAPABILITIES.SETTINGS_MANAGE,
  '/system/jobs': CAPABILITIES.SYSTEM_MAINTENANCE,
};

/**
 * Resolve the capability required to view `pathname`.
 *
 * Longest-prefix wins so a specific mapping (`/system/settings`) always beats a
 * broader one, and matching is boundary-aware so `/products-archive` never
 * matches `/products`. Returns `null` when the route is not restricted.
 */
export function capabilityForPath(pathname: string): Capability | null {
  if (!pathname) return null;
  const normalized = pathname.replace(/\/+$/, '') || '/';

  const match = Object.keys(ROUTE_CAPABILITIES)
    .sort((a, b) => b.length - a.length)
    .find((route) => normalized === route || normalized.startsWith(`${route}/`));

  return match ? ROUTE_CAPABILITIES[match] : null;
}
