import { describe, it, expect } from 'vitest';
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { ROUTES } from '@/core/routes/routes';

/**
 * Collects every routable page path under `src/app`, ignoring Next.js route
 * groups — `(dashboard)` and `(auth)` are organisational only and do not form
 * part of the URL.
 */
function collectPageRoutes(dir: string, prefix = ''): Set<string> {
  const found = new Set<string>();
  readdirSync(dir, { withFileTypes: true }).forEach((entry) => {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      // Route group: contributes no URL segment.
      const nextPrefix = entry.name.startsWith('(') ? prefix : `${prefix}/${entry.name}`;
      collectPageRoutes(full, nextPrefix).forEach((r) => found.add(r));
    } else if (entry.name === 'page.tsx') {
      found.add(prefix || '/');
    }
  });
  return found;
}

const PAGE_ROUTES = collectPageRoutes(join(process.cwd(), 'src', 'app'));

describe('route registry integrity', () => {
  const literals = Object.entries(ROUTES).filter(
    ([, v]) => typeof v === 'string'
  ) as Array<[string, string]>;

  // Every function-style route, invoked with a representative id.
  const dynamic = Object.entries(ROUTES).filter(
    ([, v]) => typeof v === 'function'
  ) as Array<[string, (id: number | string) => string]>;

  it('discovers the real page tree', () => {
    expect(PAGE_ROUTES.size).toBeGreaterThan(20);
    expect(PAGE_ROUTES.has('/dashboard')).toBe(true);
    expect(PAGE_ROUTES.has('/login')).toBe(true);
  });

  it('declares no duplicate literal routes', () => {
    const paths = literals.map(([, v]) => v);
    expect(new Set(paths).size).toBe(paths.length);
  });

  it('every literal route resolves to a real page', () => {
    const missing = literals.filter(([, v]) => !PAGE_ROUTES.has(v)).map(([k, v]) => `${k} -> ${v}`);
    expect(missing).toEqual([]);
  });

  it('every detail route resolves to a dynamic page', () => {
    // Detail routes are consumed as literal parents plus /[id].
    const missing = dynamic
      .filter(([, fn]) => !PAGE_ROUTES.has(`${fn(1).replace(/\/[^/]+$/, '')}/[id]`))
      .map(([k, fn]) => `${k} -> ${fn(1)}`);
    expect(missing).toEqual([]);
  });

  it('every route starts with a slash', () => {
    literals.forEach(([key, value]) => {
      expect(value.startsWith('/'), `${key} = ${value}`).toBe(true);
    });
    dynamic.forEach(([key, fn]) => {
      expect(fn(1).startsWith('/'), `${key} = ${fn(1)}`).toBe(true);
    });
  });
});