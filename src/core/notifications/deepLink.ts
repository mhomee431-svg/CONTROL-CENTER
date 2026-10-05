/**
 * NOTIFICATION SAFETY — Deep Link Validation
 * ==========================================
 *
 * Never allow arbitrary, unvalidated deep links in a notification payload.
 *
 * A notification that carries a `deep_link` is a vector for:
 *   - Phishing / open-redirect abuse (attacker-supplied external URL)
 *   - Unsupported route injection (a path the client cannot render)
 *   - Cross-entity confusion (a valid route pointing at the wrong entity type)
 *   - Malformed / non-numeric entity identifiers reaching the client router
 *
 * This module is the single, centralized gate that every notification send
 * must pass through BEFORE the payload is dispatched to the backend. It
 * validates three things, exactly as the safety contract requires:
 *
 *   1. notification type  → must be a supported, known notification type
 *   2. entity ID          → must match the identifier shape required by the type
 *   3. supported route    → the resulting path must map to a registered admin route
 *
 * The backend remains authoritative: this is a client-side pre-flight guard so
 * the operator is warned immediately, but it must never be the only defence.
 * The backend MUST re-validate every notification payload it receives.
 */

import { ROUTES } from '../routes/routes';

/** Supported notification types. Unknown types are rejected outright. */
export const NOTIFICATION_TYPES = {
  /** Free-form platform announcement — no entity, optional safe route. */
  ADMIN_BROADCAST: 'ADMIN_BROADCAST',
  /** Promotional campaign. */
  PROMOTION: 'PROMOTION',
  /** System maintenance / outage message. */
  SYSTEM_MESSAGE: 'SYSTEM_MESSAGE',
  /** Order lifecycle update. */
  ORDER_UPDATE: 'ORDER_UPDATE',
  /** Payment / subscription update, points at a subscription. */
  PAYMENT_UPDATE: 'PAYMENT_UPDATE',
  /** Offer / deal alert, points at an offer. */
  OFFER_ALERT: 'OFFER_ALERT',
  /** Product discovery alert, points at a product. */
  PRODUCT_ALERT: 'PRODUCT_ALERT',
  /** Shop / business update, points at a shop. */
  SHOP_UPDATE: 'SHOP_UPDATE',
  /** Verification decision, points at a verification record. */
  VERIFICATION_UPDATE: 'VERIFICATION_UPDATE',
  /** Support / complaint update, points at a support ticket. */
  SUPPORT_UPDATE: 'SUPPORT_UPDATE',
  /** Inventory freshness alert, points at a shop-product record. */
  INVENTORY_ALERT: 'INVENTORY_ALERT',
} as const;

export type NotificationType = (typeof NOTIFICATION_TYPES)[keyof typeof NOTIFICATION_TYPES];

export const ALL_NOTIFICATION_TYPES = Object.values(NOTIFICATION_TYPES) as NotificationType[];

/**
 * The entity ID shape a notification type expects.
 *
 * - `none`     → the type must NOT carry an entity id.
 * - `numeric`  → a positive integer surrogate key.
 * - `string`   → a bounded, safe opaque identifier (slug / code / UUID-ish).
 * - `optional` → either a valid id or no id at all.
 */
export type EntityIdKind = 'none' | 'numeric' | 'string' | 'optional';

interface NotificationTypeRule {
  /** Human label for the composer UI. */
  label: string;
  /** Required entity-id shape. */
  entity: EntityIdKind;
  /**
   * Route builder for this type. Returning `null` means the type has no
   * client-renderable destination and therefore must not carry a deep link.
   */
  buildRoute: ((id: string) => string) | null;
  /** Grouping for the composer dropdown. */
  audienceHint: 'all' | 'customer' | 'shopkeeper';
}

/**
 * Registry of supported notification types → entity contract → route builder.
 *
 * This is the authoritative allow-list. Adding a new notification type means
 * adding an entry here; nothing else may construct a deep link by hand.
 */
export const NOTIFICATION_TYPE_RULES: Record<NotificationType, NotificationTypeRule> = {
  [NOTIFICATION_TYPES.ADMIN_BROADCAST]: {
    label: 'Platform Announcement',
    entity: 'none',
    buildRoute: null,
    audienceHint: 'all',
  },
  [NOTIFICATION_TYPES.PROMOTION]: {
    label: 'Promotional Campaign',
    entity: 'optional',
    buildRoute: null,
    audienceHint: 'all',
  },
  [NOTIFICATION_TYPES.SYSTEM_MESSAGE]: {
    label: 'System Message',
    entity: 'none',
    buildRoute: null,
    audienceHint: 'all',
  },
  [NOTIFICATION_TYPES.ORDER_UPDATE]: {
    label: 'Order Update',
    entity: 'none',
    buildRoute: null,
    audienceHint: 'customer',
  },
  [NOTIFICATION_TYPES.PAYMENT_UPDATE]: {
    label: 'Payment / Subscription Update',
    entity: 'none',
    buildRoute: () => ROUTES.SUBSCRIPTIONS,
    audienceHint: 'shopkeeper',
  },
  [NOTIFICATION_TYPES.OFFER_ALERT]: {
    label: 'Offer / Deal Alert',
    entity: 'numeric',
    buildRoute: (id) => ROUTES.OFFER_DETAIL(id),
    audienceHint: 'customer',
  },
  [NOTIFICATION_TYPES.PRODUCT_ALERT]: {
    label: 'Product Alert',
    entity: 'numeric',
    buildRoute: (id) => ROUTES.PRODUCT_DETAIL(id),
    audienceHint: 'customer',
  },
  [NOTIFICATION_TYPES.SHOP_UPDATE]: {
    label: 'Shop / Business Update',
    entity: 'numeric',
    buildRoute: (id) => ROUTES.BUSINESS_DETAIL(id),
    audienceHint: 'shopkeeper',
  },
  [NOTIFICATION_TYPES.VERIFICATION_UPDATE]: {
    label: 'Verification Decision',
    entity: 'numeric',
    buildRoute: (id) => ROUTES.VERIFICATION_DETAIL(id),
    audienceHint: 'shopkeeper',
  },
  [NOTIFICATION_TYPES.SUPPORT_UPDATE]: {
    label: 'Support Ticket Update',
    entity: 'numeric',
    buildRoute: (id) => ROUTES.SUPPORT_DETAIL(id),
    audienceHint: 'customer',
  },
  [NOTIFICATION_TYPES.INVENTORY_ALERT]: {
    label: 'Inventory Freshness Alert',
    entity: 'numeric',
    buildRoute: (id) => ROUTES.INVENTORY_DETAIL(id),
    audienceHint: 'shopkeeper',
  },
};

/**
 * Every path prefix the admin client is able to render.
 *
 * A deep link is only "supported" when its pathname begins with one of these.
 * This prevents a valid-looking but unregistered route from being dispatched.
 */
export const SUPPORTED_ROUTE_PREFIXES: ReadonlyArray<string> = [
  ROUTES.DASHBOARD,
  ROUTES.CUSTOMERS,
  ROUTES.SHOPKEEPERS,
  ROUTES.BUSINESSES,
  ROUTES.VERIFICATION,
  ROUTES.PRODUCTS,
  ROUTES.CATEGORIES,
  ROUTES.BRANDS,
  ROUTES.INVENTORY,
  ROUTES.PRICING,
  ROUTES.OFFERS,
  ROUTES.SUBSCRIPTIONS,
  ROUTES.SEARCH,
  ROUTES.CONTENT,
  ROUTES.LOCATIONS,
  ROUTES.IMPORTS,
  ROUTES.POS,
  ROUTES.NOTIFICATIONS,
  ROUTES.SUPPORT,
  ROUTES.AUDIT,
  ROUTES.ANALYTICS,
  ROUTES.SYSTEM_HEALTH,
  ROUTES.SYSTEM_JOBS,
  ROUTES.SYSTEM_FLAGS,
  ROUTES.SYSTEM_SETTINGS,
  ROUTES.SYSTEM_LIVE_OPERATIONS,
  ROUTES.ADMIN_USERS,
  ROUTES.SETTINGS,
];

export interface DeepLinkValidationResult {
  /** True only when the link is safe to dispatch. */
  valid: boolean;
  /** Normalized, relative path — never an absolute/external URL. */
  path: string | null;
  /** Machine-readable reason when `valid` is false. */
  code?: DeepLinkErrorCode;
  /** Human-readable reason for the operator. */
  message?: string;
}

export type DeepLinkErrorCode =
  | 'UNKNOWN_NOTIFICATION_TYPE'
  | 'ENTITY_NOT_ALLOWED'
  | 'ENTITY_REQUIRED'
  | 'INVALID_NUMERIC_ENTITY'
  | 'INVALID_STRING_ENTITY'
  | 'ROUTE_NOT_SUPPORTED'
  | 'EXTERNAL_URL_BLOCKED'
  | 'PROTOCOL_RELATIVE_BLOCKED'
  | 'MALFORMED_URL'
  | 'TRAVERSAL_BLOCKED';

/** Numeric surrogate keys: positive integers only. */
const NUMERIC_ID_RE = /^[1-9]\d{0,17}$/;
/**
 * Opaque string identifiers: alphanumerics plus `-` and `_`, 1–64 chars.
 * Deliberately narrow so no path separators, dots, spaces or shell characters
 * can be smuggled through an entity id.
 */
const SAFE_STRING_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;

/** True when a string is a supported notification type. */
export function isNotificationType(value: string): value is NotificationType {
  return (ALL_NOTIFICATION_TYPES as ReadonlyArray<string>).includes(value);
}

/** True when a pathname maps to a registered admin route prefix. */
export function isSupportedRoute(pathname: string): boolean {
  if (!pathname || !pathname.startsWith('/')) return false;
  // Reject traversal / encoded traversal outright.
  if (pathname.includes('..') || /%2e%2e/i.test(pathname)) return false;
  return SUPPORTED_ROUTE_PREFIXES.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`)
  );
}

/**
 * Validate an entity id against the shape required by its notification type.
 * Exported so the composer can give live inline feedback.
 */
export function validateEntityId(
  type: NotificationType,
  entityId?: string | number | null
): DeepLinkValidationResult {
  const rule = NOTIFICATION_TYPE_RULES[type];
  if (!rule) {
    return { valid: false, path: null, code: 'UNKNOWN_NOTIFICATION_TYPE', message: `Unsupported notification type: ${type}` };
  }

  const raw = entityId === undefined || entityId === null ? '' : String(entityId).trim();

  if (rule.entity === 'none') {
    if (raw) {
      return {
        valid: false,
        path: null,
        code: 'ENTITY_NOT_ALLOWED',
        message: `"${rule.label}" notifications do not accept an entity ID.`,
      };
    }
    return { valid: true, path: null };
  }

  if (!raw) {
    if (rule.entity === 'optional') return { valid: true, path: null };
    return {
      valid: false,
      path: null,
      code: 'ENTITY_REQUIRED',
      message: `"${rule.label}" notifications require an entity ID.`,
    };
  }

  if (rule.entity === 'numeric') {
    if (!NUMERIC_ID_RE.test(raw)) {
      return {
        valid: false,
        path: null,
        code: 'INVALID_NUMERIC_ENTITY',
        message: 'Entity ID must be a positive numeric identifier.',
      };
    }
    return { valid: true, path: raw };
  }

  if (rule.entity === 'string') {
    if (!SAFE_STRING_ID_RE.test(raw)) {
      return {
        valid: false,
        path: null,
        code: 'INVALID_STRING_ENTITY',
        message: 'Entity ID may only contain letters, numbers, hyphens and underscores (max 64 chars).',
      };
    }
    return { valid: true, path: raw };
  }

  // optional: validate whichever shape was supplied (accept numeric or safe string).
  if (!NUMERIC_ID_RE.test(raw) && !SAFE_STRING_ID_RE.test(raw)) {
    return {
      valid: false,
      path: null,
      code: 'INVALID_STRING_ENTITY',
      message: 'Entity ID is not a valid identifier.',
    };
  }
  return { valid: true, path: raw };
}

/**
 * Build the deep link for a notification type + entity id.
 *
 * Returns a relative path or `null` when the type has no destination. The
 * result is always validated through {@link validateDeepLink} by callers before
 * it is placed into a payload.
 */
export function buildDeepLink(
  type: NotificationType,
  entityId?: string | number | null
): string | null {
  const rule = NOTIFICATION_TYPE_RULES[type];
  if (!rule || !rule.buildRoute) return null;

  const entity = validateEntityId(type, entityId);
  if (!entity.valid || !entity.path) return null;

  return rule.buildRoute(entity.path);
}

/**
 * PRIMARY GATE — validate a complete notification deep-link payload.
 *
 * Validates all three required dimensions together:
 *   1. notification type is supported
 *   2. entity ID matches the type's contract
 *   3. the produced route is a registered, client-renderable admin route
 *
 * Also rejects any externally-supplied `candidateUrl` that is not a relative
 * admin path (external hosts, protocol-relative `//evil.com`, `javascript:`,
 * traversal, etc.).
 *
 * @param type       Notification type to validate.
 * @param entityId   Entity identifier (shape depends on `type`).
 * @param candidateUrl Optional explicit URL to validate instead of building one.
 */
export function validateDeepLink(
  type: string,
  entityId?: string | number | null,
  candidateUrl?: string | null
): DeepLinkValidationResult {
  if (!isNotificationType(type)) {
    return {
      valid: false,
      path: null,
      code: 'UNKNOWN_NOTIFICATION_TYPE',
      message: `Unsupported notification type: ${type}`,
    };
  }

  // An explicit URL must never be trusted — validate it directly and hard.
  if (candidateUrl != null && candidateUrl !== '') {
    return validateExplicitUrl(candidateUrl);
  }

  const entity = validateEntityId(type, entityId);
  if (!entity.valid) return entity;

  const rule = NOTIFICATION_TYPE_RULES[type];
  if (!rule.buildRoute) {
    // Type has no destination: valid, but carries no path.
    return { valid: true, path: null };
  }

  if (!entity.path) {
    return {
      valid: false,
      path: null,
      code: 'ENTITY_REQUIRED',
      message: `"${rule.label}" notifications require an entity ID to build a route.`,
    };
  }

  const path = rule.buildRoute(entity.path);

  if (!isSupportedRoute(path)) {
    return {
      valid: false,
      path: null,
      code: 'ROUTE_NOT_SUPPORTED',
      message: `Route "${path}" is not a supported admin route.`,
    };
  }

  return { valid: true, path };
}

/**
 * Validate a fully-formed URL string supplied by an operator or an upstream
 * system. Only relative admin paths are ever accepted.
 */
export function validateExplicitUrl(url: string): DeepLinkValidationResult {
  const value = String(url).trim();

  if (!value) {
    return { valid: true, path: null };
  }

  // Reject scheme-bearing and protocol-relative URLs (http:, javascript:, //host).
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) {
    return {
      valid: false,
      path: null,
      code: 'EXTERNAL_URL_BLOCKED',
      message: 'External or scheme-bearing URLs are not permitted in notifications.',
    };
  }
  if (value.startsWith('//')) {
    return {
      valid: false,
      path: null,
      code: 'PROTOCOL_RELATIVE_BLOCKED',
      message: 'Protocol-relative URLs are not permitted.',
    };
  }
  if (!value.startsWith('/')) {
    return {
      valid: false,
      path: null,
      code: 'MALFORMED_URL',
      message: 'Deep links must be root-relative admin paths starting with "/".',
    };
  }
  if (value.includes('..') || /%2e%2e/i.test(value)) {
    return {
      valid: false,
      path: null,
      code: 'TRAVERSAL_BLOCKED',
      message: 'Path traversal is not permitted.',
    };
  }

  // Strip query/hash before prefix matching, but keep them in the output path.
  const pathname = value.split(/[?#]/)[0];

  if (!isSupportedRoute(pathname)) {
    return {
      valid: false,
      path: null,
      code: 'ROUTE_NOT_SUPPORTED',
      message: `Route "${pathname}" is not a supported admin route.`,
    };
  }

  return { valid: true, path: value };
}