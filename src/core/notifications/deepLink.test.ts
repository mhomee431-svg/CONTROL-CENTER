import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import {
  ALL_NOTIFICATION_AUDIENCES,
  AUDIENCE_TARGETING,
  NOTIFICATION_TYPES,
  SUPPORTED_ROUTE_PREFIXES,
  buildDeepLink,
  isNotificationAudience,
  isNotificationType,
  isSupportedRoute,
  validateDeepLink,
  validateEntityId,
  validateExplicitUrl,
  validateMetadata,
  validateSchedule,
} from './deepLink';

/**
 * NOTIFICATION SAFETY contract:
 *   validate → notification type · entity ID · supported route
 */
describe('Deep link validation — notification type', () => {
  it('accepts every registered notification type', () => {
    Object.values(NOTIFICATION_TYPES).forEach((type) => {
      expect(isNotificationType(type)).toBe(true);
    });
  });

  it('rejects unknown notification types', () => {
    expect(isNotificationType('SOMETHING_ELSE')).toBe(false);
    expect(isNotificationType('')).toBe(false);
    const result = validateDeepLink('UNKNOWN_TYPE');
    expect(result.valid).toBe(false);
    expect(result.code).toBe('UNKNOWN_NOTIFICATION_TYPE');
  });
});

describe('Deep link validation — entity ID', () => {
  it('rejects a numeric entity for a no-entity type', () => {
    const result = validateDeepLink(NOTIFICATION_TYPES.ADMIN_BROADCAST, '123');
    expect(result.valid).toBe(false);
    expect(result.code).toBe('ENTITY_NOT_ALLOWED');
  });

  it('requires an entity for entity-bound types', () => {
    const result = validateDeepLink(NOTIFICATION_TYPES.PRODUCT_ALERT);
    expect(result.valid).toBe(false);
    expect(result.code).toBe('ENTITY_REQUIRED');
  });

  it('rejects non-numeric entity ids where a numeric key is required', () => {
    const result = validateDeepLink(NOTIFICATION_TYPES.PRODUCT_ALERT, 'abc');
    expect(result.valid).toBe(false);
    expect(result.code).toBe('INVALID_NUMERIC_ENTITY');
  });

  it('rejects negative / zero / over-long numeric ids', () => {
    expect(validateEntityId(NOTIFICATION_TYPES.OFFER_ALERT, '0').valid).toBe(false);
    expect(validateEntityId(NOTIFICATION_TYPES.OFFER_ALERT, '-5').valid).toBe(false);
    expect(validateEntityId(NOTIFICATION_TYPES.OFFER_ALERT, '1'.repeat(19)).valid).toBe(false);
  });

  it('rejects string ids containing unsafe characters', () => {
    const unsafe = ['../../etc', 'a b', 'a/b', 'a.b', '<script>', 'a%2e%2e'];
    unsafe.forEach((id) => {
      expect(validateEntityId(NOTIFICATION_TYPES.PRODUCT_ALERT, id).valid).toBe(false);
    });
  });

  it('rejects string ids on types that expect a numeric entity', () => {
    expect(validateEntityId(NOTIFICATION_TYPES.PRODUCT_ALERT, 'ORD-2026_0001').valid).toBe(false);
  });

  it('treats optional-entity types as valid with or without an id', () => {
    expect(validateEntityId(NOTIFICATION_TYPES.PROMOTION).valid).toBe(true);
    expect(validateEntityId(NOTIFICATION_TYPES.PROMOTION, '99').valid).toBe(true);
  });
});

describe('Deep link validation — supported route', () => {
  it('accepts registered admin route prefixes', () => {
    ['/dashboard', '/customers/5', '/products/10', '/notifications/campaigns', '/content/banners'].forEach(
      (path) => expect(isSupportedRoute(path)).toBe(true)
    );
  });

  it('rejects unregistered routes and traversal', () => {
    ['/secret', '/admin/../../etc/passwd', '/customers/../brands', 'dashboard'].forEach((path) =>
      expect(isSupportedRoute(path)).toBe(false)
    );
  });

  /**
   * Regression guard: a prefix must only be allow-listed when a real page
   * renders it. Registering a route that has no page would let a "validated"
   * deep link navigate the operator to a 404.
   *
   * This walks the actual App Router tree, so adding a page automatically keeps
   * the guard accurate and adding a bogus prefix fails the suite.
   */
  it('only allow-lists prefixes that have an actual page', () => {
    const appDir = path.resolve(__dirname, '../../app/(dashboard)');

    const walk = (dir: string, prefix = ''): string[] =>
      fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) return walk(full, `${prefix}/${entry.name}`);
        return entry.name === 'page.tsx' ? [prefix || '/'] : [];
      });

    const implemented = new Set(walk(appDir));
    const missing = SUPPORTED_ROUTE_PREFIXES.filter(
      (p) => !implemented.has(p) && !implemented.has(`${p}/index`)
    );

    expect(missing).toEqual([]);
  });

  it('builds a valid route for entity-bound types', () => {
    const result = validateDeepLink(NOTIFICATION_TYPES.SUPPORT_UPDATE, '42');
    expect(result.valid).toBe(true);
    expect(result.path).toBe('/support/42');
  });

  it('returns a pathless valid result for types with no destination', () => {
    const result = validateDeepLink(NOTIFICATION_TYPES.SYSTEM_MESSAGE);
    expect(result.valid).toBe(true);
    expect(result.path).toBeNull();
  });
});

describe('Deep link validation — external URL hardening', () => {
  it('blocks scheme-bearing URLs', () => {
    ['https://evil.com', 'javascript:alert(1)', 'data:text/html;base64,x'].forEach((url) => {
      const result = validateExplicitUrl(url);
      expect(result.valid).toBe(false);
      expect(result.code).toBe('EXTERNAL_URL_BLOCKED');
    });
  });

  it('blocks protocol-relative URLs', () => {
    const result = validateExplicitUrl('//evil.com/path');
    expect(result.valid).toBe(false);
    expect(result.code).toBe('PROTOCOL_RELATIVE_BLOCKED');
  });

  it('blocks traversal in explicit URLs', () => {
    const result = validateExplicitUrl('/customers/../../etc');
    expect(result.valid).toBe(false);
    expect(result.code).toBe('TRAVERSAL_BLOCKED');
  });

  it('blocks non-root-relative paths', () => {
    const result = validateExplicitUrl('customers/5');
    expect(result.valid).toBe(false);
    expect(result.code).toBe('MALFORMED_URL');
  });

  it('accepts a supported relative admin path', () => {
    const result = validateExplicitUrl('/products/12?tab=pricing');
    expect(result.valid).toBe(true);
    expect(result.path).toBe('/products/12?tab=pricing');
  });
});

describe('buildDeepLink', () => {
  it('returns null for types without a destination', () => {
    expect(buildDeepLink(NOTIFICATION_TYPES.ADMIN_BROADCAST)).toBeNull();
  });

  it('returns null when the entity id is invalid', () => {
    expect(buildDeepLink(NOTIFICATION_TYPES.PRODUCT_ALERT, 'nope')).toBeNull();
  });

  it('returns the correct route for a valid entity id', () => {
    expect(buildDeepLink(NOTIFICATION_TYPES.PRODUCT_ALERT, 7)).toBe('/products/7');
  });
});
describe('Audience targeting — only backend-supported dimensions exposed', () => {
  it('exposes a capability entry for every audience scope', () => {
    ALL_NOTIFICATION_AUDIENCES.forEach((audience) => {
      expect(AUDIENCE_TARGETING[audience]).toBeDefined();
      expect(AUDIENCE_TARGETING[audience].audience).toBe(audience);
    });
  });

  it('only enables selected-id targeting for selectable audiences', () => {
    // "All" is a whole-platform scope; it has no explicit id list.
    expect(AUDIENCE_TARGETING.all.selected).toBe(false);
    expect(AUDIENCE_TARGETING.customer.selected).toBe(true);
    expect(AUDIENCE_TARGETING.shopkeeper.selected).toBe(true);
  });

  it('recognises supported audiences and rejects others', () => {
    expect(isNotificationAudience('customer')).toBe(true);
    expect(isNotificationAudience('shopkeeper')).toBe(true);
    expect(isNotificationAudience('everyone')).toBe(false);
  });
});

describe('Schedule validation (Notification Composer)', () => {
  const now = new Date('2026-01-01T00:00:00.000Z');

  it('treats an empty schedule as "send now"', () => {
    const result = validateSchedule('', now);
    expect(result.valid).toBe(true);
    expect(result.iso).toBeNull();
  });

  it('rejects a schedule in the past', () => {
    const result = validateSchedule('2025-12-31T23:00:00.000Z', now);
    expect(result.valid).toBe(false);
    expect(result.message).toMatch(/future/i);
  });

  it('rejects an unparseable date', () => {
    expect(validateSchedule('not-a-date', now).valid).toBe(false);
  });

  it('accepts a future schedule and normalises to ISO', () => {
    const result = validateSchedule('2026-01-02T10:00:00.000Z', now);
    expect(result.valid).toBe(true);
    expect(result.iso).toBe('2026-01-02T10:00:00.000Z');
  });
});

describe('Metadata validation (Notification Composer)', () => {
  it('treats empty metadata as absent', () => {
    expect(validateMetadata('')).toEqual({ valid: true, value: null });
  });

  it('rejects invalid JSON', () => {
    const result = validateMetadata('{ not json }');
    expect(result.valid).toBe(false);
  });

  it('rejects non-object JSON', () => {
    expect(validateMetadata('[1,2,3]').valid).toBe(false);
    expect(validateMetadata('"a string"').valid).toBe(false);
  });

  it('accepts a JSON object verbatim', () => {
    const result = validateMetadata('{"campaign":"spring","tier":2}');
    expect(result.valid).toBe(true);
    expect(result.value).toEqual({ campaign: 'spring', tier: 2 });
  });
});
