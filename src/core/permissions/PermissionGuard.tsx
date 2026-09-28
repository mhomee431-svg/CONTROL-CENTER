'use client';

import React from 'react';
import { useAuth } from '../auth/AuthContext';
import { hasPermission } from './permissions';

interface PermissionGuardProps {
  resource: string;
  action: string;
  fallback?: React.ReactNode;
  children: React.ReactNode;
}

/**
 * Section 138: Admin Permission Guard
 * Conditionally renders UI elements based on authorized admin permissions.
 */
export const PermissionGuard: React.FC<PermissionGuardProps> = ({
  resource,
  action,
  fallback = null,
  children,
}) => {
  const { adminRole, isLoading } = useAuth();

  if (isLoading) {
    return null;
  }

  const allowed = hasPermission(adminRole, resource, action);

  if (!allowed) {
    return <>{fallback}</>;
  }

  return <>{children}</>;
};
