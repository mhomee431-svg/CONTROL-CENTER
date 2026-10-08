'use client';

import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/core/api/client';
import { useDateRange } from '@/core/filters/DateRangeContext';

/**
 * Fetch one analytics section over the shared reporting window.
 *
 * Every analytics surface reads the window from the same context, so this hook
 * sends identical `days` params to each section endpoint and caches the result
 * under a query key that includes the window — switching ranges re-fetches,
 * switching sections reuses the cache.
 */
export function useSectionAnalytics<T>(section: string, endpoint: string) {
  const { params } = useDateRange();

  const query = useQuery<T>({
    queryKey: ['admin', 'analytics', section, params],
    queryFn: () => apiClient<T>(endpoint, { params }),
    retry: false,
  });

  return {
    data: query.data,
    isLoading: query.isLoading,
    isError: query.isError,
  };
}

/** Format a count that the backend may report as null ("not collected"). */
export function formatNullable(value: number | null | undefined): number | null {
  return value === null || value === undefined ? null : value;
}
