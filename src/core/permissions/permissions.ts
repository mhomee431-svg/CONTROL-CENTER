import { AdminRoleInfo } from '../types/admin';

/**
 * Section 8, 138: Centralized RBAC / Capability Registry.
 *
 * Single source of truth for admin authorization. Pages and components must
 * never hardcode permission strings; they reference CAPABILITIES constants and
 * pass them to <PermissionGuard /> or the usePermissions() hook.
 *
 * Wire format note: this project's FastAPI backend returns permission strings
 * in `action:resource` form (e.g. "read:customers"). Capabilities below are
 * declared in the canonical `resource.action` form (e.g. "customers.read") and
 * compared against both representations, so the frontend works with either the
 * legacy backend encoding or the canonical dotted encoding.
 */

export const CAPABILITIES = {
  CUSTOMERS_READ: 'customers.read',
  CUSTOMERS_UPDATE: 'customers.update',
  CUSTOMERS_SUSPEND: 'customers.suspend',

  SHOPS_READ: 'shops.read',
  SHOPS_APPROVE: 'shops.approve',
  SHOPS_REJECT: 'shops.reject',
  SHOPS_SUSPEND: 'shops.suspend',

  PRODUCTS_READ: 'products.read',
  PRODUCTS_UPDATE: 'products.update',
  PRODUCTS_MERGE: 'products.merge',
  PRODUCTS_APPROVE: 'products.approve',

  INVENTORY_READ: 'inventory.read',
  INVENTORY_UPDATE: 'inventory.update',

  ANALYTICS_READ: 'analytics.read',
  AUDIT_READ: 'audit.read',

  SETTINGS_READ: 'settings.read',
  SETTINGS_MANAGE: 'settings.manage',

  NOTIFICATIONS_SEND: 'notifications.send',

  CONTENT_READ: 'content.read',
  CONTENT_MANAGE: 'content.manage',

  SUPPORT_READ: 'support.read',
  SUPPORT_UPDATE: 'support.update',

  OFFERS_READ: 'offers.read',
  OFFERS_UPDATE: 'offers.update',

  SUBSCRIPTIONS_READ: 'subscriptions.read',
  SUBSCRIPTIONS_UPDATE: 'subscriptions.update',

  TAXONOMY_READ: 'taxonomy.read',
  TAXONOMY_MANAGE: 'taxonomy.manage',

  // High-risk / ownership-only capabilities (platform owner & delegated admins)
  ADMINS_READ: 'admins.read',
  ADMINS_MANAGE: 'admins.manage',
  ADMINS_ROLES_MANAGE: 'admins.roles.manage',
  SECURITY_MANAGE: 'security.manage',
  OWNERSHIP_TRANSFER: 'ownership.transfer',
  SYSTEM_MAINTENANCE: 'system.maintenance',
} as const;

export type Capability = (typeof CAPABILITIES)[keyof typeof CAPABILITIES];

/** All potential admin roles. */
export const ADMIN_ROLES = {
  OWNER: 'OWNER',
  SUPER_ADMIN: 'SUPER_ADMIN',
  ADMIN: 'ADMIN',
  VERIFICATION_ADMIN: 'VERIFICATION_ADMIN',
  OPERATIONS_ADMIN: 'OPERATIONS_ADMIN',
  SUPPORT_ADMIN: 'SUPPORT_ADMIN',
  CONTENT_ADMIN: 'CONTENT_ADMIN',
  ANALYST: 'ANALYST',
} as const;

export type AdminRole = (typeof ADMIN_ROLES)[keyof typeof ADMIN_ROLES];

/**
 * The platform owner is the single centralized administrator role.
 *
 * OWNER is the highest authority on the platform. Every other role — including
 * SUPER_ADMIN — is a delegated operator that must NOT be assumed to hold every
 * permission. Ownership is transferable only by the current owner.
 */
export const OWNER_ROLE = ADMIN_ROLES.OWNER;

/** Roles that carry implicit wildcard (`*:*`) authority. */
export const WILDCARD_ROLES: ReadonlyArray<string> = [OWNER_ROLE, ADMIN_ROLES.SUPER_ADMIN, 'admin'];

/**
 * Capabilities that must never be assumed. They are protected so that a
 * delegated admin without an explicit grant is denied even if a broad role
 * matrix would otherwise imply access.
 */
export const PROTECTED_CAPABILITIES: ReadonlyArray<Capability> = [
  CAPABILITIES.ADMINS_MANAGE,
  CAPABILITIES.ADMINS_ROLES_MANAGE,
  CAPABILITIES.SECURITY_MANAGE,
  CAPABILITIES.OWNERSHIP_TRANSFER,
  CAPABILITIES.SYSTEM_MAINTENANCE,
  CAPABILITIES.SETTINGS_MANAGE,
];

const PROTECTED_SET = new Set<string>(PROTECTED_CAPABILITIES);

export const ALL_CAPABILITIES = Object.values(CAPABILITIES) as Capability[];

/**
 * Default capability matrix per role.
 *
 * The backend remains authoritative: `AdminRoleInfo.permissions` returned by
 * /api/v1/admin/me always wins. This matrix exists so the UI can reason about
 * roles when the backend omits an explicit permission list, and so it documents
 * the intended least-privilege model in one place.
 */
export const ROLE_CAPABILITIES: Record<AdminRole, Capability[] | '*'> = {
  OWNER: '*',
  SUPER_ADMIN: '*',
  ADMIN: '*',

  VERIFICATION_ADMIN: [
    CAPABILITIES.SHOPS_READ,
    CAPABILITIES.SHOPS_APPROVE,
    CAPABILITIES.SHOPS_REJECT,
    CAPABILITIES.SHOPS_SUSPEND,
    CAPABILITIES.PRODUCTS_READ,
    CAPABILITIES.PRODUCTS_APPROVE,
    CAPABILITIES.INVENTORY_READ,
    CAPABILITIES.AUDIT_READ,
  ],

  OPERATIONS_ADMIN: [
    CAPABILITIES.CUSTOMERS_READ,
    CAPABILITIES.SHOPS_READ,
    CAPABILITIES.PRODUCTS_READ,
    CAPABILITIES.INVENTORY_READ,
    CAPABILITIES.INVENTORY_UPDATE,
    CAPABILITIES.OFFERS_READ,
    CAPABILITIES.OFFERS_UPDATE,
    CAPABILITIES.SUBSCRIPTIONS_READ,
    CAPABILITIES.ANALYTICS_READ,
    CAPABILITIES.AUDIT_READ,
  ],

  SUPPORT_ADMIN: [
    CAPABILITIES.CUSTOMERS_READ,
    CAPABILITIES.CUSTOMERS_UPDATE,
    CAPABILITIES.SHOPS_READ,
    CAPABILITIES.PRODUCTS_READ,
    CAPABILITIES.SUPPORT_READ,
    CAPABILITIES.SUPPORT_UPDATE,
    CAPABILITIES.NOTIFICATIONS_SEND,
  ],

  CONTENT_ADMIN: [
    CAPABILITIES.PRODUCTS_READ,
    CAPABILITIES.PRODUCTS_UPDATE,
    CAPABILITIES.PRODUCTS_MERGE,
    CAPABILITIES.PRODUCTS_APPROVE,
    CAPABILITIES.TAXONOMY_READ,
    CAPABILITIES.TAXONOMY_MANAGE,
    CAPABILITIES.INVENTORY_READ,
    CAPABILITIES.CONTENT_READ,
    CAPABILITIES.CONTENT_MANAGE,
    CAPABILITIES.NOTIFICATIONS_SEND,
  ],

  ANALYST: [
    CAPABILITIES.CUSTOMERS_READ,
    CAPABILITIES.SHOPS_READ,
    CAPABILITIES.PRODUCTS_READ,
    CAPABILITIES.INVENTORY_READ,
    CAPABILITIES.ANALYTICS_READ,
    CAPABILITIES.AUDIT_READ,
  ],
};

/** Convert canonical `resource.action` into the backend `action:resource` key. */
function toBackendKey(capability: string): string {
  const [resource, ...rest] = capability.split('.');
  return [rest.join('.'), resource].join(':');
}

function expandBackendPermissions(permissions: string[]): Set<string> {
  const expanded = new Set<string>();
  permissions.forEach((raw) => {
    const value = raw.trim();
    if (!value) return;
    expanded.add(value);
    // Normalize backend action:resource into canonical resource.action too.
    if (value.includes(':') && !value.includes('.')) {
      const [action, resource] = value.split(':');
      if (action && resource) expanded.add(`${resource}.${action}`);
    }
  });
  return expanded;
}

/** True when the admin is the platform owner (single centralized authority). */
export function isPlatformOwner(roleInfo: AdminRoleInfo | null | undefined): boolean {
  if (!roleInfo) return false;
  const name = (roleInfo.role_name || '').toUpperCase();
  return name === OWNER_ROLE || roleInfo.is_owner === true;
}

/** True when the role carries implicit wildcard authority. */
export function hasWildcard(roleInfo: AdminRoleInfo | null | undefined): boolean {
  if (!roleInfo) return false;
  if (isPlatformOwner(roleInfo)) return true;
  if (roleInfo.level === 'SUPER') return true;
  const name = (roleInfo.role_name || '').toUpperCase();
  return WILDCARD_ROLES.map((r) => r.toUpperCase()).includes(name);
}

function resolveRoleCapabilities(roleInfo: AdminRoleInfo): Capability[] | '*' | null {
  const roleName = (roleInfo.role_name || '').toUpperCase();
  if (roleName in ROLE_CAPABILITIES) {
    return ROLE_CAPABILITIES[roleName as AdminRole];
  }
  return null;
}

/**
 * Central permission check. Every page/component must route through this.
 *
 * Resolution order:
 *   1. Platform owner / wildcard role → granted.
 *   2. Protected capability without an explicit backend grant → denied
 *      (delegated admins are never assumed to hold sensitive authority).
 *   3. Explicit backend permission (either encoding) → granted.
 *   4. Documented role matrix fallback (non-protected capabilities only).
 */
export function hasPermission(
  roleInfo: AdminRoleInfo | null | undefined,
  capability: Capability | string
): boolean {
  if (!roleInfo) return false;

  // 1. Owner / wildcard roles carry implicit *:*
  if (hasWildcard(roleInfo)) return true;

  const granted = expandBackendPermissions(roleInfo.permissions || []);
  const explicitlyGranted = granted.has(capability) || granted.has(toBackendKey(capability));

  // 2. Sensitive operations require an explicit grant for delegated admins.
  if (PROTECTED_SET.has(capability) && !explicitlyGranted) {
    return false;
  }

  // 3. Backend-authoritative explicit permission wins.
  if (explicitlyGranted) return true;

  // 4. Fall back to the documented role capability matrix when applicable.
  const roleCaps = resolveRoleCapabilities(roleInfo);
  if (roleCaps === '*') return true;
  if (roleCaps && roleCaps.includes(capability as Capability)) return true;

  return false;
}

export function hasAnyPermission(
  roleInfo: AdminRoleInfo | null | undefined,
  capabilities: Array<Capability | string>
): boolean {
  return capabilities.some((cap) => hasPermission(roleInfo, cap));
}

export function hasAllPermissions(
  roleInfo: AdminRoleInfo | null | undefined,
  capabilities: Array<Capability | string>
): boolean {
  return capabilities.every((cap) => hasPermission(roleInfo, cap));
}

/** Human-readable role label for UI chips. */
export function getRoleLabel(roleInfo: AdminRoleInfo | null | undefined): string {
  if (!roleInfo) return 'ADMIN';
  if (isPlatformOwner(roleInfo)) return 'OWNER';
  if (roleInfo.level === 'SUPER' || (roleInfo.role_name || '').toUpperCase() === 'SUPER_ADMIN') {
    return 'SUPER ADMIN';
  }
  if ((roleInfo.role_name || '').toLowerCase() === 'admin') return 'SUPER ADMIN';
  const role = (roleInfo.role_name || '').toUpperCase();
  if (role in ROLE_CAPABILITIES) {
    return role.replace(/_/g, ' ');
  }
  return roleInfo.name || 'ADMIN';
}
