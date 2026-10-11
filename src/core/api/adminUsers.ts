import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import type { AdminUserRecord, AdminRoleOption } from '@/core/types/admin';

/**
 * ADMIN USER MANAGEMENT — API module.
 *
 * Every write here is a governance action: it changes who can sign in or what
 * they may do. The backend is authoritative for authorization and for the audit
 * trail; this module only shapes the requests.
 *
 * The three mutations all carry an operator `reason`, which the backend records
 * in the append-only audit log. That is why none of them is exposed as a bare
 * fire-and-forget call — the UI is expected to collect the reason first.
 */

export interface AdminUserListParams {
  search?: string;
  role?: string;
  status?: string;
  limit?: number;
  offset?: number;
}

export async function listAdminUsers(
  params: AdminUserListParams
): Promise<{ items: AdminUserRecord[]; total: number }> {
  return apiClient<{ items: AdminUserRecord[]; total: number }>(API_ENDPOINTS.ADMIN_USERS.LIST, {
    params: {
      search: params.search || undefined,
      role: params.role || undefined,
      status: params.status || undefined,
      limit: params.limit,
      offset: params.offset,
    },
  });
}

export async function listAdminRoles(): Promise<AdminRoleOption[]> {
  const res = await apiClient<{ items: AdminRoleOption[] }>(API_ENDPOINTS.ADMIN_USERS.ROLES);
  return res.items ?? [];
}

export interface CreateAdminUserPayload {
  username: string;
  password: string;
  name?: string;
  email?: string;
  role_name: string;
  reason?: string;
}

export async function createAdminUser(payload: CreateAdminUserPayload): Promise<AdminUserRecord> {
  return apiClient<AdminUserRecord>(API_ENDPOINTS.ADMIN_USERS.CREATE, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
}

export async function setAdminUserStatus(
  id: number | string,
  isActive: boolean,
  reason: string
): Promise<AdminUserRecord> {
  return apiClient<AdminUserRecord>(API_ENDPOINTS.ADMIN_USERS.STATUS(id), {
    method: 'PATCH',
    body: JSON.stringify({ is_active: isActive, reason }),
  });
}

export async function changeAdminUserRole(
  id: number | string,
  roleName: string,
  reason: string
): Promise<AdminUserRecord> {
  return apiClient<AdminUserRecord>(API_ENDPOINTS.ADMIN_USERS.ROLE(id), {
    method: 'PATCH',
    body: JSON.stringify({ role_name: roleName, reason }),
  });
}

export interface ResetAdminAccessResult extends AdminUserRecord {
  /** Present only immediately after a reset that generated a password. */
  temporary_password?: string | null;
}

export async function resetAdminAccess(
  id: number | string,
  opts: { newPassword?: string; reason: string }
): Promise<ResetAdminAccessResult> {
  return apiClient<ResetAdminAccessResult>(API_ENDPOINTS.ADMIN_USERS.RESET_ACCESS(id), {
    method: 'POST',
    body: JSON.stringify({ new_password: opts.newPassword || undefined, reason: opts.reason }),
  });
}
