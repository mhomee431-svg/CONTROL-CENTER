import { AdminRoleInfo } from '../types/admin';

/**
 * Section 8 & Section 138: RBAC & Permission Verification
 * Matches backend `app/core/admin_permissions.py`
 */

export function hasPermission(
  roleInfo: AdminRoleInfo | null | undefined,
  resource: string,
  action: string
): boolean {
  if (!roleInfo) return false;
  if (roleInfo.level === 'SUPER' || roleInfo.role_name === 'admin') {
    return true; // Super Admin carries implicit wildcard (*:*)
  }
  const targetKey = `${action}:${resource}`;
  return roleInfo.permissions.includes(targetKey);
}
