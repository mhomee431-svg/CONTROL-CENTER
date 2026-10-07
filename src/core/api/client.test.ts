import { afterEach, describe, expect, it, vi } from 'vitest';
import { apiClient, ApiError } from './client';

describe('apiClient diagnostic request IDs', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('includes the server request ID on API errors', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            success: false,
            message: 'Internal server error',
            error_code: 'INTERNAL_ERROR',
          }),
          {
            status: 500,
            headers: {
              'Content-Type': 'application/json',
              'X-Request-ID': 'req-server-123',
            },
          }
        )
      )
    );

    await expect(apiClient('/broken', { requiresAuth: false })).rejects.toMatchObject({
      requestId: 'req-server-123',
      statusCode: 500,
      errorCode: 'INTERNAL_ERROR',
    });
  });

  it('keeps the client request ID on network failures', async () => {
    let sentRequestId: string | null = null;
    const fetchMock = vi.fn((_input: RequestInfo | URL, init?: RequestInit) => {
      sentRequestId = new Headers(init?.headers).get('X-Request-ID');
      return Promise.reject(new TypeError('offline'));
    });
    vi.stubGlobal('fetch', fetchMock);

    const error = await apiClient('/offline', { requiresAuth: false }).catch(
      (reason: unknown) => reason as ApiError
    );
    if (!(error instanceof ApiError)) {
      throw new Error('Expected an ApiError for a network failure');
    }
    expect(error.requestId).toBe(sentRequestId);
  });
});
