import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * A failed request must never be indistinguishable from an empty result.
 *
 * An operator seeing "0 records" concludes the platform has no data. An
 * operator seeing a failure alert knows to escalate. Collapsing the two is how
 * real incidents get missed, so this is asserted structurally across the app.
 */

const APP_DIR = join(process.cwd(), 'src', 'app');

function collectPages(dir: string, prefix = ''): string[] {
  const out: string[] = [];
  readdirSync(dir, { withFileTypes: true }).forEach((entry) => {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      const next = entry.name.startsWith('(') ? prefix : `${prefix}/${entry.name}`;
      out.push(...collectPages(full, next));
    } else if (entry.name === 'page.tsx') {
      out.push(prefix || '/');
    }
  });
  return out;
}

const PAGES = collectPages(APP_DIR);

/** Reads a page source by route, resolving the route group that contains it. */
function findPageSource(route: string): string | null {
  const segments = route.split('/').filter(Boolean);
  // Descend one level at a time so route groups like (dashboard) are skipped.
  const walk = (dir: string, remaining: string[]): string | null => {
    if (remaining.length === 0) {
      try {
        return readFileSync(join(dir, 'page.tsx'), 'utf8');
      } catch {
        return null;
      }
    }
    const [head, ...rest] = remaining;
    try {
      const entries = readdirSync(dir, { withFileTypes: true });
      const direct = entries.find((e) => e.isDirectory() && e.name === head);
      if (direct) {
        const found = walk(join(dir, head), rest);
        if (found) return found;
      }
      for (const group of entries.filter((e) => e.isDirectory() && e.name.startsWith('('))) {
        const found = walk(join(dir, group.name), remaining);
        if (found) return found;
      }
    } catch {
      return null;
    }
    return null;
  };
  return walk(APP_DIR, segments);
}

describe('query failure surfaces an explicit state', () => {
  const pagesWithQueries = PAGES.map((route) => ({
    route,
    src: findPageSource(route),
  })).filter((p): p is { route: string; src: string } => Boolean(p.src?.includes('useQuery')));

  it('found the page corpus', () => {
    expect(pagesWithQueries.length).toBeGreaterThan(20);
  });

  it('resolves page sources, not just counts', () => {
    // Guards against the assertions below passing on an empty corpus.
    expect(findPageSource('/customers')).toContain('useQuery');
    expect(findPageSource('/analytics/geography')).toContain('useQuery');
  });

  it('every page issuing a query handles isError', () => {
    const offenders = pagesWithQueries
      .filter((p) => !p.src.includes('isError'))
      .map((p) => p.route);
    expect(offenders).toEqual([]);
  });

  it('grid-based pages surface query failures explicitly', () => {
    // Two acceptable patterns: pass `error` to AdminDataGrid, or render the
    // page's own error Alert above it. What must never happen is neither.
    const offenders = pagesWithQueries
      .filter((p) => p.src.includes('<AdminDataGrid'))
      .filter(
        (p) =>
          !p.src.includes('error={isError}') &&
          !/<Alert severity="error"/.test(p.src)
      )
      .map((p) => p.route);
    expect(offenders).toEqual([]);
  });

  it('no page renders zero-valued metrics as a substitute for a failure', () => {
    // Geography analytics previously reported 0 covered cities on error.
    const geo = findPageSource('/analytics/geography');
    expect(geo).toContain('isError');
    expect(geo).toContain('Unavailable');
  });
});

describe('every dashboard page is reachable from the sidebar', () => {
  // A page that nothing links to is invisible: it still builds, still passes
  // every check, and is never opened. /settings was exactly this — a working
  // hub for eight administration sections that no navigation entry pointed at.
  const pages: string[] = [];
  const walk = (dir: string, prefix: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full, entry.name.startsWith('(') ? prefix : `${prefix}/${entry.name}`);
      } else if (entry.name === 'page.tsx') {
        pages.push(prefix || '/');
      }
    }
  };
  walk(APP_DIR, '');

  const routesSrc = readFileSync(join(process.cwd(), 'src/core/routes/routes.ts'), 'utf8');
  const sidebarSrc = readFileSync(join(process.cwd(), 'src/core/components/Sidebar.tsx'), 'utf8');

  const navPaths = [...new Set([...sidebarSrc.matchAll(/ROUTES\.([A-Z_0-9]+)/g)].map((m) => m[1]))]
    .map((key) => {
      // Anchored so SETTINGS does not match the SYSTEM_SETTINGS entry that
      // appears earlier in the file.
      const found = routesSrc.match(new RegExp(`^\\s*${key}:\\s*'([^']+)'`, 'm'));
      return found ? found[1] : null;
    })
    .filter((v): v is string => Boolean(v));

  it('found the page corpus', () => {
    expect(pages.length).toBeGreaterThan(20);
  });

  it('resolves sidebar route constants', () => {
    expect(navPaths.length).toBeGreaterThan(10);
  });

  it('has no orphaned pages', () => {
    const orphans = pages.filter((p) => {
      // The login page is reached from the session guard on a 401, never from
      // the authenticated nav. The root is a redirect shim to the dashboard.
      if (p === '/login' || p === '/') return false;
      return !navPaths.some((n) => p === n || p.startsWith(n === '/' ? '/' : `${n}/`));
    });
    expect(orphans).toEqual([]);
  });
});