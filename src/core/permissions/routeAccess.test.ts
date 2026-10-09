import { describe, it, expect } from 'vitest';
import { CAPABILITIES, ALL_CAPABILITIES } from './permissions';
import { ROUTE_CAPABILITIES, capabilityForPath } from './routeAccess';
import { ROUTES } from '@/core/routes/routes';

describe('capabilityForPath — centralized route authorization (Section 8/138)', () => {
  it('returns null for unrestricted routes', () => {
    expect(capabilityForPath(ROUTES.DASHBOARD)).toBeNull();
    expect(capabilityForPath(ROUTES.LOGIN)).toBeNull();
    expect(capabilityForPath('/system/health')).toBeNull();
    expect(capabilityForPath('')).toBeNull();
  });

  it('resolves the capability for a restricted area', () => {
    expect(capabilityForPath(ROUTES.CUSTOMERS)).toBe(CAPABILITIES.CUSTOMERS_READ);
    expect(capabilityForPath(ROUTES.AUDIT)).toBe(CAPABILITIES.AUDIT_READ);
    expect(capabilityForPath(ROUTES.ANALYTICS)).toBe(CAPABILITIES.ANALYTICS_READ);
  });

  it('covers dynamic detail routes through their prefix', () => {
    expect(capabilityForPath(ROUTES.CUSTOMER_DETAIL(42))).toBe(CAPABILITIES.CUSTOMERS_READ);
    expect(capabilityForPath(ROUTES.PRODUCT_DETAIL('abc-1'))).toBe(CAPABILITIES.PRODUCTS_READ);
    expect(capabilityForPath(ROUTES.INVENTORY_DETAIL(7))).toBe(CAPABILITIES.INVENTORY_READ);
  });

  it('gates the verification queue and its case drill-down on the read capability', () => {
    // The queue is a read surface over the shop registry; the four triage
    // actions inside it are gated separately by <PermissionGuard />. Mapping
    // the route to the read capability keeps a look-only reviewer able to open
    // a case, which is the same population the sidebar offers the area to.
    expect(capabilityForPath(ROUTES.VERIFICATION)).toBe(CAPABILITIES.SHOPS_READ);
    expect(capabilityForPath(ROUTES.VERIFICATION_DETAIL(1))).toBe(CAPABILITIES.SHOPS_READ);
  });

  it('prefers the longest matching prefix', () => {
    // /system/settings must win over any broader /system mapping.
    expect(capabilityForPath(ROUTES.SYSTEM_SETTINGS)).toBe(CAPABILITIES.SETTINGS_READ);
    expect(capabilityForPath('/system/settings/general')).toBe(CAPABILITIES.SETTINGS_READ);
    expect(capabilityForPath(ROUTES.SYSTEM_FLAGS)).toBe(CAPABILITIES.SETTINGS_MANAGE);
  });

  it('matches on path boundaries only', () => {
    expect(capabilityForPath('/products-archive')).toBeNull();
    expect(capabilityForPath('/customer-support')).toBeNull();
  });

  it('tolerates trailing slashes', () => {
    expect(capabilityForPath('/customers/')).toBe(CAPABILITIES.CUSTOMERS_READ);
    expect(capabilityForPath('/audit/')).toBe(CAPABILITIES.AUDIT_READ);
  });

  it('never restricts the dashboard or login entry points', () => {
    expect(Object.keys(ROUTE_CAPABILITIES)).not.toContain(ROUTES.DASHBOARD);
    expect(Object.keys(ROUTE_CAPABILITIES)).not.toContain(ROUTES.LOGIN);
  });

  it('only maps declared capability constants', () => {
    const declared = new Set<string>(ALL_CAPABILITIES);
    Object.entries(ROUTE_CAPABILITIES).forEach(([route, capability]) => {
      expect(declared.has(capability), `${route} maps to undeclared capability ${capability}`).toBe(
        true
      );
    });
  });

  it('keeps every restricted route in sync with the route registry', () => {
    const registryRoutes = [
      ROUTES.CUSTOMERS,
      ROUTES.SHOPKEEPERS,
      ROUTES.BUSINESSES,
      ROUTES.VERIFICATION,
      ROUTES.LOCATIONS,
      ROUTES.PRODUCTS,
      ROUTES.CATEGORIES,
      ROUTES.BRANDS,
      ROUTES.INVENTORY,
      ROUTES.PRICING,
      ROUTES.IMPORTS,
      ROUTES.POS,
      ROUTES.OFFERS,
      ROUTES.SUBSCRIPTIONS,
      ROUTES.SUPPORT,
      ROUTES.AUDIT,
      ROUTES.ANALYTICS,
      ROUTES.ADMIN_USERS,
      ROUTES.SYSTEM_SETTINGS,
      ROUTES.SYSTEM_FLAGS,
      ROUTES.SYSTEM_JOBS,
    ];
    registryRoutes.forEach((route) => {
      expect(capabilityForPath(route), `${route} is not mapped in ROUTE_CAPABILITIES`).not.toBeNull();
    });
  });
});
