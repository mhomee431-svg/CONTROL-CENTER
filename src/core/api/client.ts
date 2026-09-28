import { ApiResponse } from '../types/api';

export class ApiError extends Error {
  public statusCode: number;
  public errorCode?: string;
  public data?: unknown;

  constructor(message: string, statusCode: number, errorCode?: string, data?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.errorCode = errorCode;
    this.data = data;
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

  const requestHeaders: Record<string, string> = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-Request-ID': `req_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`,
    ...(headers as Record<string, string>),
  };

  if (requiresAuth && typeof window !== 'undefined') {
    const token = localStorage.getItem('admin_access_token');
    if (token) {
      requestHeaders['Authorization'] = `Bearer ${token}`;
    }
  }

  const config: RequestInit = {
    ...customConfig,
    headers: requestHeaders,
  };

  let response: Response;
  try {
    response = await fetch(url, config);
  } catch (err: unknown) {
    throw new ApiError(
      err instanceof Error ? err.message : 'Network failure or server unreachable',
      0,
      'NETWORK_ERROR'
    );
  }

  // Handle Unauthorized (401)
  if (response.status === 401) {
    if (typeof window !== 'undefined') {
      localStorage.removeItem('admin_access_token');
      localStorage.removeItem('admin_user');
      if (window.location.pathname !== '/login') {
        window.location.href = '/login?expired=1';
      }
    }
    throw new ApiError('Session expired or unauthorized', 401, 'UNAUTHORIZED');
  }

  // Handle Forbidden (403)
  if (response.status === 403) {
    throw new ApiError('You do not have permission to perform this action', 403, 'FORBIDDEN');
  }

  let data: ApiResponse<T> | null = null;
  try {
    data = await response.json();
  } catch {
    // Non-JSON response
  }

  if (!response.ok) {
    const errorMessage = data?.message || response.statusText || 'An unexpected error occurred';
    throw new ApiError(errorMessage, response.status, data?.error_code, data?.data);
  }

  return (data?.data !== undefined ? data.data : (data as unknown)) as T;
}
