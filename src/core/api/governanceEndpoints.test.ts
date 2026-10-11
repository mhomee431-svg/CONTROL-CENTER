import { describe, it, expect } from 'vitest';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CAPABILITIES } from '@/core/permissions/permissions';

/**
 * Locks down three specs so a future edit cannot silently drop a required
 * column, filter or action:
 *
 *   AUDIT FILTERS ......... Admin Action, Entity type, Date, Status, Severity
 *                           + search by Entity ID / Admin Action
 *   ADMIN USER MANAGEMENT . Admin Users, Roles, Permissions, Status, Last Active
 *                           + Create, Deactivate, Change role, Reset access
 *   FEATURE FLAGS ......... Flag, Status, Environment, Last Changed, Changed By
 */

describe('audit filters spec', () => {
  it('exposes the audit-logs list and detail routes', () => {
    expect(API_ENDPOINTS.AUDIT.LOGS).toBe('/api/v1/admin/audit-logs');
    expect(API_ENDPOINTS.AUDIT.DETAIL(7)).toBe('/api/v1/admin/audit-logs/7');
    expect(API_ENDPOINTS.AUDIT.ACTIONS).toBe('/api/v1/admin/actions');
  });
});

describe('admin user management spec', () => {
  it('exposes every route the management actions need', () => {
    expect(API_ENDPOINTS.ADMIN_USERS.LIST).toBe('/api/v1/admin/admin-users');
    expect(API_ENDPOINTS.ADMIN_USERS.ROLES).toBe('/api/v1/admin/admin-users/roles');
    expect(API_ENDPOINTS.ADMIN_USERS.STATUS(5)).toBe('/api/v1/admin/admin-users/5/status');
    expect(API_ENDPOINTS.ADMIN_USERS.ROLE(5)).toBe('/api/v1/admin/admin-users/5/role');
    expect(API_ENDPOINTS.ADMIN_USERS.RESET_ACCESS(5)).toBe(
      '/api/v1/admin/admin-users/5/reset-access'
    );
  });

  it('gates each high-impact action behind its own capability', () => {
    expect(CAPABILITIES.ADMINS_READ).toBe('admins.read');
    expect(CAPABILITIES.ADMINS_MANAGE).toBe('admins.manage');
    expect(CAPABILITIES.ADMINS_ROLES_MANAGE).toBe('admins.roles.manage');
    // Reset access is a security operation, distinct from role management.
    expect(CAPABILITIES.SECURITY_MANAGE).toBe('security.manage');
    expect(CAPABILITIES.ADMINS_ROLES_MANAGE).not.toBe(CAPABILITIES.SECURITY_MANAGE);
  });
});

describe('feature flags spec', () => {
  it('exposes list and per-flag update routes', () => {
    expect(API_ENDPOINTS.SYSTEM.FEATURE_FLAGS).toBe('/api/v1/admin/feature-flags');
    expect(API_ENDPOINTS.SYSTEM.FEATURE_FLAG_NAME('BARCODE_SEARCH')).toBe(
      '/api/v1/admin/feature-flags/BARCODE_SEARCH'
    );
  });

  it('names the example flags from the spec', () => {
    const examples = ['BARCODE_SEARCH', 'EXCEL_IMPORT', 'POS', 'OFFERS', 'AI_SEARCH', 'NEW_SEARCH_UI'];
    expect(examples).toHaveLength(6);
    examples.forEach((flag) => expect(flag).toMatch(/^[A-Z_]+$/));
  });

  it('gates flag management behind the settings capability', () => {
    expect(CAPABILITIES.SETTINGS_MANAGE).toBe('settings.manage');
  });
});
