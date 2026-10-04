import { describe, it, expect } from 'vitest';
import {
  CAPABILITIES,
  ROLE_CAPABILITIES,
  ADMIN_ROLES,
  PROTECTED_CAPABILITIES,
  getRoleLabel,
  hasAllPermissions,
  hasAnyPermission,
  hasPermission,
  isPlatformOwner,
} from '@/core/permissions/permissions';
import { AdminRoleInfo } from '@/core/types/admin';

const role = (overrides: Partial<AdminRoleInfo> = {}): AdminRoleInfo => ({
  user_id: 1,
  name: 'Test Admin',
  role_name: 'SUPPORT_ADMIN',
  level: 'SUB',
  permissions: [],
  ...overrides,
});

describe('hasPermission — centralized RBAC (Section 8/138)', () => {
  it('denies everything without role info', () => {
    expect(hasPermission(null, CAPABILITIES.CUSTOMERS_READ)).toBe(false);
    expect(hasPermission(undefined, CAPABILITIES.SETTINGS_MANAGE)).toBe(false);
  });

  it('grants wildcard access to SUPER level', () => {
    const info = role({ level: 'SUPER', role_name: 'SUPER_ADMIN', permissions: [] });
    expect(hasPermission(info, CAPABILITIES.SETTINGS_MANAGE)).toBe(true);
    expect(hasPermission(info, CAPABILITIES.PRODUCTS_MERGE)).toBe(true);
  });

  it('grants wildcard access to role_name "admin"', () => {
    const info = role({ role_name: 'admin', permissions: [] });
    expect(hasPermission(info, CAPABILITIES.AUDIT_READ)).toBe(true);
  });

  it('accepts backend action:resource encoding', () => {
    const info = role({ role_name: 'custom', permissions: ['read:customers', 'suspend:customers'] });
    expect(hasPermission(info, CAPABILITIES.CUSTOMERS_READ)).toBe(true);
    expect(hasPermission(info, CAPABILITIES.CUSTOMERS_SUSPEND)).toBe(true);
    expect(hasPermission(info, CAPABILITIES.CUSTOMERS_UPDATE)).toBe(false);
  });

  it('accepts canonical resource.action encoding', () => {
    const info = role({ role_name: 'custom', permissions: ['products.merge'] });
    expect(hasPermission(info, CAPABILITIES.PRODUCTS_MERGE)).toBe(true);
    expect(hasPermission(info, CAPABILITIES.PRODUCTS_READ)).toBe(false);
  });

  it('falls back to the documented role matrix when backend omits permissions', () => {
    const info = role({ role_name: ADMIN_ROLES.ANALYST, permissions: [] });
    expect(hasPermission(info, CAPABILITIES.ANALYTICS_READ)).toBe(true);
    expect(hasPermission(info, CAPABILITIES.SETTINGS_MANAGE)).toBe(false);
    expect(hasPermission(info, CAPABILITIES.CUSTOMERS_SUSPEND)).toBe(false);
  });

  it('enforces least privilege per role definition', () => {
    const verification = role({ role_name: ADMIN_ROLES.VERIFICATION_ADMIN, permissions: [] });
    expect(hasPermission(verification, CAPABILITIES.SHOPS_APPROVE)).toBe(true);
    expect(hasPermission(verification, CAPABILITIES.SHOPS_SUSPEND)).toBe(true);
    expect(hasPermission(verification, CAPABILITIES.SETTINGS_MANAGE)).toBe(false);
    expect(hasPermission(verification, CAPABILITIES.CUSTOMERS_SUSPEND)).toBe(false);

    const support = role({ role_name: ADMIN_ROLES.SUPPORT_ADMIN, permissions: [] });
    expect(hasPermission(support, CAPABILITIES.SUPPORT_UPDATE)).toBe(true);
    expect(hasPermission(support, CAPABILITIES.PRODUCTS_MERGE)).toBe(false);
  });

  it('denies unknown role with no permissions', () => {
    const info = role({ role_name: 'MYSTERY_ROLE', permissions: [] });
    expect(hasPermission(info, CAPABILITIES.CUSTOMERS_READ)).toBe(false);
  });

  it('supports anyOf / allOf composition', () => {
    const info = role({ role_name: ADMIN_ROLES.ANALYST, permissions: [] });
    expect(hasAnyPermission(info, [CAPABILITIES.SETTINGS_MANAGE, CAPABILITIES.AUDIT_READ])).toBe(true);
    expect(hasAllPermissions(info, [CAPABILITIES.AUDIT_READ, CAPABILITIES.SETTINGS_MANAGE])).toBe(false);
    expect(hasAllPermissions(info, [CAPABILITIES.AUDIT_READ, CAPABILITIES.ANALYTICS_READ])).toBe(true);
  });

  it('labels roles correctly for UI chips', () => {
    expect(getRoleLabel(role({ level: 'SUPER', role_name: 'SUPER_ADMIN' }))).toBe('SUPER ADMIN');
    expect(getRoleLabel(role({ role_name: ADMIN_ROLES.VERIFICATION_ADMIN }))).toBe('VERIFICATION ADMIN');
    expect(getRoleLabel(null)).toBe('ADMIN');
  });

  it('matrix only uses declared capability constants', () => {
    const declared = new Set<string>(Object.values(CAPABILITIES));
    Object.entries(ROLE_CAPABILITIES).forEach(([roleName, caps]) => {
      if (caps === '*') return;
      caps.forEach((cap: string) => {
        expect(declared.has(cap), `${roleName} declares unknown capability ${cap}`).toBe(true);
      });
    });
  });
});

describe('Platform Owner & protected capabilities', () => {
  it('identifies only the platform owner role or is_owner flag', () => {
    expect(isPlatformOwner(role({ role_name: 'OWNER' }))).toBe(true);
    expect(isPlatformOwner(role({ role_name: 'owner' }))).toBe(true);
    expect(isPlatformOwner(role({ role_name: 'ADMIN', is_owner: true }))).toBe(true);
    expect(isPlatformOwner(role({ role_name: 'ADMIN', level: 'SUPER' }))).toBe(false);
    expect(isPlatformOwner(role({ role_name: 'SUPPORT_ADMIN' }))).toBe(false);
    expect(isPlatformOwner(null)).toBe(false);
  });

  it('grants the owner every capability, including sensitive ones', () => {
    const owner = role({ role_name: 'OWNER', level: 'SUPER', permissions: [] });
    PROTECTED_CAPABILITIES.forEach((cap) => {
      expect(hasPermission(owner, cap), `owner denied ${cap}`).toBe(true);
    });
    expect(hasPermission(owner, CAPABILITIES.OWNERSHIP_TRANSFER)).toBe(true);
    expect(hasPermission(owner, CAPABILITIES.ADMINS_MANAGE)).toBe(true);
  });

  it('does NOT assume delegated admins hold sensitive permissions', () => {
    // A broad-matrix role that would otherwise look powerful.
    const admin = role({ role_name: 'SUPPORT_ADMIN', permissions: [] });
    expect(hasPermission(admin, CAPABILITIES.ADMINS_MANAGE)).toBe(false);
    expect(hasPermission(admin, CAPABILITIES.ADMINS_ROLES_MANAGE)).toBe(false);
    expect(hasPermission(admin, CAPABILITIES.SECURITY_MANAGE)).toBe(false);
    expect(hasPermission(admin, CAPABILITIES.OWNERSHIP_TRANSFER)).toBe(false);
    expect(hasPermission(admin, CAPABILITIES.SYSTEM_MAINTENANCE)).toBe(false);
    expect(hasPermission(admin, CAPABILITIES.SETTINGS_MANAGE)).toBe(false);
  });

  it('protected capabilities require an explicit backend grant for delegated admins', () => {
    const delegated = role({
      role_name: 'OPERATIONS_ADMIN',
      permissions: ['manage:settings', 'read:admins'],
    });
    // Explicitly granted protected capability is honoured...
    expect(hasPermission(delegated, CAPABILITIES.SETTINGS_MANAGE)).toBe(true);
    // ...but the others remain denied even though the role is operational.
    expect(hasPermission(delegated, CAPABILITIES.ADMINS_MANAGE)).toBe(false);
    expect(hasPermission(delegated, CAPABILITIES.OWNERSHIP_TRANSFER)).toBe(false);
  });

  it('only the owner can transfer ownership', () => {
    const owner = role({ role_name: 'OWNER' });
    const superAdmin = role({ role_name: 'SUPER_ADMIN', level: 'SUPER' });
    expect(hasPermission(owner, CAPABILITIES.OWNERSHIP_TRANSFER)).toBe(true);
    expect(hasPermission(superAdmin, CAPABILITIES.OWNERSHIP_TRANSFER)).toBe(true); // SUPER_ADMIN still wildcard
    const analyst = role({ role_name: 'ANALYST' });
    expect(hasPermission(analyst, CAPABILITIES.OWNERSHIP_TRANSFER)).toBe(false);
  });

  it('labels the owner distinctly in the UI', () => {
    expect(getRoleLabel(role({ role_name: 'OWNER', level: 'SUPER' }))).toBe('OWNER');
    expect(getRoleLabel(role({ role_name: 'ADMIN', is_owner: true }))).toBe('OWNER');
  });

  it('every protected capability is a declared capability constant', () => {
    const declared = new Set<string>(Object.values(CAPABILITIES));
    PROTECTED_CAPABILITIES.forEach((cap) => {
      expect(declared.has(cap), `protected capability ${cap} is not declared`).toBe(true);
    });
  });
});
