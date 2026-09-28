/**
 * Standard API Response Structures matching FastAPI Backend
 */

export interface ApiResponse<T = unknown> {
  success: boolean;
  message: string;
  data: T;
  error_code?: string;
}

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  limit: number;
  offset: number;
}

export interface ApiPaginationParams {
  limit?: number;
  offset?: number;
  search?: string;
  [key: string]: string | number | boolean | undefined | null;
}
