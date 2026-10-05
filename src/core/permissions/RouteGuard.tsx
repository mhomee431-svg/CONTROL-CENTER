'use client';

import React from 'react';
import { usePathname } from 'next/navigation';
import { usePermissions } from './PermissionGuard';
import { AccessDenied } from '@/core/components/AccessDenied';
import { capabilityForPath } from './routeAccess';

interface RouteGuardProps {
  children: React.ReactNode;
}

/**
 * Section 138: Route-level admin authorization.
 *
 * Wraps the dashboard shell so a single centralized map (`ROUTE_CAPABILITIES`)
 * decides which areas an admin role may open. Pages never repeat permission
 * checks for navigation-level access — they only gate their own actions with
 * `<PermissionGuard capability={CAPABILITIES.*} />`.
 *
 * This is defense-in-depth for UX: the backend remains authoritative and
 * re-validates every request regardless of what the UI renders.
 */
export const RouteGuard: React.FC<RouteGuardProps> = ({ children }) => {
  const pathname = usePathname();
  const { can, isLoading } = usePermissions();

  if (isLoading) return null;

  const required = capabilityForPath(pathname);
  if (required && !can(required)) return <AccessDenied capability={required} />;

  return <>{children}</>;
};
