'use client';

import React from 'react';
import { useAuth } from '../auth/AuthContext';
import { AccessDenied } from '../components/AccessDenied';
import type { AdminRole, Capability } from './permissions';
import {
  getRoleLabel,
  hasAllPermissions,
  hasAnyPermission,
  hasPermission,
  isPlatformOwner,
  ROLE_CAPABILITIES,
} from './permissions';

interface PermissionGuardProps {
  /** Single capability (canonical `resource.action` form). */
  capability?: Capability | string;
  /** Require ANY of these capabilities. */
  anyOf?: Array<Capability | string>;
  /** Require ALL of these capabilities. */
  allOf?: Array<Capability | string>;
  fallback?: React.ReactNode;
  children: React.ReactNode;
}

/**
 * Section 138: Admin Permission Guard
 * Conditionally renders UI elements based on centralized capabilities.
 * Pages must never hardcode permission strings; pass CAPABILITIES.* instead.
 */
export const PermissionGuard: React.FC<PermissionGuardProps> = ({
  capability,
  anyOf,
  allOf,
  fallback,
  children,
}) => {
  const { adminRole, isLoading } = useAuth();

  if (isLoading) return null;

  let allowed = true;
  if (capability) allowed = allowed && hasPermission(adminRole, capability);
  if (anyOf && anyOf.length > 0) allowed = allowed && hasAnyPermission(adminRole, anyOf);
  if (allOf && allOf.length > 0) allowed = allowed && hasAllPermissions(adminRole, allOf);

  if (!allowed) return <>{fallback ?? <AccessDenied capability={capability} />}</>;

  return <>{children}</>;
};

/**
 * Centralized permission hook for page/feature state.
 * Keeps authorization logic out of individual page components.
 */
export function usePermissions() {
  const { adminRole, isLoading } = useAuth();

  return {
    isLoading,
    role: adminRole,
    roleLabel: getRoleLabel(adminRole),
    isOwner: isPlatformOwner(adminRole),
    can: (capability: Capability | string) => hasPermission(adminRole, capability),
    canAny: (capabilities: Array<Capability | string>) => hasAnyPermission(adminRole, capabilities),
    canAll: (capabilities: Array<Capability | string>) => hasAllPermissions(adminRole, capabilities),
    isRole: (role: AdminRole) => (adminRole?.role_name || '').toUpperCase() === role,
    hasRoleMatrix: !!adminRole && (adminRole.role_name || '').toUpperCase() in ROLE_CAPABILITIES,
  };
}
