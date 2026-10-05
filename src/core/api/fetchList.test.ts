import { describe, it, expect, vi, beforeEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fetchList, fetchListsAcross } from './fetchList';

/**
 * A failed request must never resolve to an empty list.
 *
 * The structural guard in queryErrorHandling.test.ts only checks that a page
 * mentions `isError` somewhere. That is satisfied by a page that destructures
 * `isError` and then quietly catches every failure anyway — so a swallowed
 * rejection can sit underneath a source file that looks compliant, and the
 * grid renders "0 records" during a real outage.
 *
 * These cases pin the behaviour instead.
 */

vi.mock('./client', async () => {
  const actual = await vi.importActual<typeof import('./client')>('./client');
  return {
    ...actual,
    apiClient: vi.fn(),
  };
});

import { apiClient, ApiError } from './client';

const mocked = apiClient as unknown as ReturnType<typeof vi.fn>;

function makeError(status: number) {
  return new ApiError(`failed ${status}`, status, `E${status}`, null);
}

beforeEach(() => {
  mocked.mockReset();
});

describe('fetchList failure handling', () => {
  it('returns the payload on success', async () => {
    mocked.mockResolvedValue({ items: [{ id: 1 }], total: 1 });
    const r = await fetchList('/some/list');
    expect(r).toEqual({ items: [{ id: 1 }], total: 1, unavailable: false });
  });

  it('normalises a missing total to the item count', async () => {
    mocked.mockResolvedValue({ items: [{ id: 1 }, { id: 2 }] });
    const r = await fetchList('/some/list');
    expect(r.total).toBe(2);
  });

  it('treats an unpublished route as unavailable rather than empty', async () => {
    // The original intent of the swallowed catch was "this endpoint may not be
    // deployed yet". That is a real state, but it is not the same as "there
    // are zero records", and the flag keeps the two distinguishable.
    mocked.mockRejectedValue(makeError(404));
    const r = await fetchList('/not/published');
    expect(r).toEqual({ items: [], total: 0, unavailable: true });
  });

  it('reports 405 as unavailable too', async () => {
    mocked.mockRejectedValue(makeError(405));
    await expect(fetchList('/wrong/method')).resolves.toMatchObject({ unavailable: true });
  });

  it('rethrows a server error so the surface can offer a retry', async () => {
    mocked.mockRejectedValue(makeError(500));
    await expect(fetchList('/broken')).rejects.toThrow(ApiError);
  });

  it('rethrows an auth failure rather than reporting zero records', async () => {
    // An expired session is the most likely real-world cause here, and it is
    // exactly the case that must never look like an empty result.
    mocked.mockRejectedValue(makeError(401));
    await expect(fetchList('/unauthorised')).rejects.toThrow(ApiError);
  });

  it('rethrows a network failure that is not an ApiError', async () => {
    mocked.mockRejectedValue(new TypeError('Failed to fetch'));
    await expect(fetchList('/offline')).rejects.toThrow(TypeError);
  });
});

describe('fetchListsAcross failure handling', () => {
  it('concatenates results across shops', async () => {
    mocked
      .mockResolvedValueOnce({ items: [{ id: 1 }], total: 1 })
      .mockResolvedValueOnce({ items: [{ id: 2 }], total: 1 });
    const r = await fetchListsAcross<{ id: number }>(['/shop/1/inv', '/shop/2/inv']);
    expect(r.items).toEqual([{ id: 1 }, { id: 2 }]);
    expect(r.total).toBe(2);
    expect(r.unavailable).toBe(false);
  });

  it('keeps the shops that answered when one shop fails', async () => {
    mocked
      .mockResolvedValueOnce({ items: [{ id: 1 }], total: 1 })
      .mockRejectedValue(makeError(500));
    const r = await fetchListsAcross<{ id: number }>(['/shop/1/inv', '/shop/2/inv']);
    expect(r.items).toEqual([{ id: 1 }]);
  });

  it('rejects when no shop answers, so the tab shows an error', async () => {
    mocked
      .mockRejectedValueOnce(makeError(500))
      .mockRejectedValueOnce(makeError(500));
    await expect(fetchListsAcross(['/shop/1/inv', '/shop/2/inv'])).rejects.toThrow();
  });

  it('flags the empty-owner case as unavailable', async () => {
    const r = await fetchListsAcross([]);
    expect(r).toEqual({ items: [], total: 0, unavailable: true });
  });
});

describe('no page swallows a list failure', () => {
  // Structural backstop for the specific shape that hid this bug.
  const PAGES = [
    'src/app/(dashboard)/customers/[id]/page.tsx',
    'src/app/(dashboard)/shopkeepers/[id]/page.tsx',
  ];

  it('no detail page converts a failed list request into an empty array', () => {
    for (const p of PAGES) {
      const src = readFileSync(join(process.cwd(), p), 'utf8') as string;
      const swallow = src.match(/\.catch\(\s*\(\)\s*=>\s*\(\{\s*items:\s*\[\]/);
      expect(swallow, `${p} swallows a failed list request`).toBeNull();
    }
  });
});