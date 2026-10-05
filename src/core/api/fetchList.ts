import { apiClient, ApiError } from './client';

/**
 * Shared list fetcher for the tabbed detail surfaces.
 *
 * These tabs each have their own backend contract, and some of those routes
 * are not published on every deployment yet. The naive way to cope is to
 * swallow the failure and return an empty array, but that makes an outage
 * indistinguishable from "this merchant has no imports" — an operator reads
 * an empty grid and concludes the data is gone rather than that the request
 * failed.
 *
 * So the two cases are kept apart:
 *   - 404 / 405 — the route is not published on this deployment. Reported as
 *     `unavailable` so the UI can say so, instead of implying zero records.
 *   - anything else (network, 401, 403, 500, timeout) — rethrown, so the
 *     query enters its error state and the surface offers a retry.
 */
export interface ListResult<T> {
  items: T[];
  total: number;
  /** True when the backend has not published this route yet. */
  unavailable: boolean;
}

export async function fetchList<T>(
  endpoint: string,
  options: { params?: Record<string, string | number | boolean | undefined | null> } = {}
): Promise<ListResult<T>> {
  try {
    const r = await apiClient<{ items?: T[]; total?: number }>(endpoint, options);
    const items = r.items ?? [];
    return { items, total: r.total ?? items.length, unavailable: false };
  } catch (err) {
    const status = err instanceof ApiError ? err.statusCode : undefined;
    // 404/405 means the route does not exist on this deployment. That is a
    // known, stable state rather than a transient fault, so it is reported
    // rather than thrown.
    if (status === 404 || status === 405) {
      return { items: [], total: 0, unavailable: true };
    }
    throw err;
  }
}

/**
 * Runs several list requests and concatenates them, for a parent entity that
 * owns many children (a merchant with several shops, for example).
 *
 * Settled independently: one child failing must not blank the whole surface,
 * because the siblings that did answer are still valid information. If none
 * of them answer the aggregate rejects, so the caller shows a failure rather
 * than an empty result.
 */
export async function fetchListsAcross<T>(
  endpoints: string[],
  options: { params?: Record<string, string | number | boolean | undefined | null> } = {}
): Promise<ListResult<T>> {
  if (endpoints.length === 0) {
    return { items: [], total: 0, unavailable: true };
  }
  const settled = await Promise.allSettled(
    endpoints.map((endpoint) => fetchList<T>(endpoint, options))
  );

  const fulfilled = settled.filter(
    (s): s is PromiseFulfilledResult<ListResult<T>> => s.status === 'fulfilled'
  );

  // Nothing answered: surface the first real failure so the surface reports
  // the outage rather than an empty aggregate.
  if (fulfilled.length === 0) {
    const firstRejection = settled.find(
      (s): s is PromiseRejectedResult => s.status === 'rejected'
    );
    throw firstRejection ? firstRejection.reason : new Error('Every child request failed');
  }

  return {
    items: fulfilled.flatMap((r) => r.value.items),
    total: fulfilled.reduce((sum, r) => sum + r.value.total, 0),
    unavailable: fulfilled.every((r) => r.value.unavailable),
  };
}