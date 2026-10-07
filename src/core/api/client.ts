import { ApiResponse } from '../types/api';
import { getAdminAccessToken, clearAdminAccessToken } from '../auth/adminSession';

export class ApiError extends Error {
  public statusCode: number;
  public errorCode?: string;
  public data?: unknown;
  public requestId?: string;

  constructor(
    message: string,
    statusCode: number,
    errorCode?: string,
    data?: unknown,
    requestId?: string
  ) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.errorCode = errorCode;
    this.data = data;
    this.requestId = requestId;
  }
}

interface RequestOptions extends RequestInit {
  params?: Record<string, string | number | boolean | undefined | null>;
  requiresAuth?: boolean;
}

const BASE_URL = process.env.NEXT_PUBLIC_API_URL || '';

/**
 * Single Authoritative API Client for HyperLocal Admin Control Center
 * Section 99: ONE centralized API client.
 */
export async function apiClient<T>(endpoint: string, options: RequestOptions = {}): Promise<T> {
  const { params, requiresAuth = true, headers = {}, ...customConfig } = options;

  let url = endpoint.startsWith('http') ? endpoint : `${BASE_URL}${endpoint}`;

  if (params) {
    const searchParams = new URLSearchParams();
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== '') {
        searchParams.append(key, String(value));
      }
    });
    const queryString = searchParams.toString();
    if (queryString) {
      url += (url.includes('?') ? '&' : '?') + queryString;
    }
  }

  const requestId = `req_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  const requestHeaders: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-Request-ID': requestId,
    ...(headers as Record<string, string>),
  };

  if (requiresAuth) {
    // Prefer the backend-managed HttpOnly cookie. The in-memory bearer token
    // is only a compatibility bridge for the current runtime.
    const token = getAdminAccessToken();
    if (token) requestHeaders['Authorization'] = `Bearer ${token}`;
  }

  const config: RequestInit = {
    ...customConfig,
    credentials: 'include',
    headers: requestHeaders,
  };

  let response: Response;
  try {
    response = await fetch(url, config);
  } catch (err: unknown) {
    throw new ApiError(
      err instanceof Error ? err.message : 'Network failure or server unreachable',
      0,
      'NETWORK_ERROR',
      undefined,
      requestId
    );
  }

  // Handle Unauthorized (401)
  if (response.status === 401) {
    clearAdminAccessToken();
    if (typeof window !== 'undefined' && window.location.pathname !== '/login') {
      window.location.href = '/login?expired=1';
    }
    throw new ApiError(
      'Session expired or unauthorized',
      401,
      'UNAUTHORIZED',
      undefined,
      response.headers.get('X-Request-ID') ?? undefined
    );
  }

  // Handle Forbidden (403)
  if (response.status === 403) {
    throw new ApiError(
      'You do not have permission to perform this action',
      403,
      'FORBIDDEN',
      undefined,
      response.headers.get('X-Request-ID') ?? undefined
    );
  }

  let data: ApiResponse<T> | null = null;
  try {
    data = await response.json();
  } catch {
    // Non-JSON response
  }

  if (!response.ok) {
    const errorMessage = data?.message || response.statusText || 'An unexpected error occurred';
    throw new ApiError(
      errorMessage,
      response.status,
      data?.error_code,
      data?.data,
      response.headers.get('X-Request-ID') ?? undefined
    );
  }

  return (data?.data !== undefined ? data.data : (data as unknown)) as T;
}
