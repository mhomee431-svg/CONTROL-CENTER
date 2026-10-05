import { describe, it, expect } from 'vitest';
import { existsSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * The architecture contracts are the specification this frontend is built
 * against. Deleting one does not fail a single test — the suite still passes
 * while the contract it enforces is silently gone — so the loss is invisible
 * until someone reads a page that no longer matches the agreed design.
 *
 * This guards the files themselves rather than any behaviour.
 */

const ROOT = join(process.cwd(), 'docs');

const REQUIRED_DOCS = [
  'PHASE_1_CURRENT_STATE_REPORT.md',
  'PHASE_2_ARCHITECTURE_CONTRACT.md',
  'frontend-architecture-contract.md',
];

describe('architecture contract docs', () => {
  it('found the docs directory', () => {
    expect(existsSync(ROOT)).toBe(true);
  });

  it('keeps every architecture contract present', () => {
    const missing = REQUIRED_DOCS.filter((name) => !existsSync(join(ROOT, name)));
    expect(missing).toEqual([]);
  });

  it('keeps each contract non-empty', () => {
    // A zero-byte file parses fine in most tools but documents nothing.
    const empty = REQUIRED_DOCS.filter((name) => {
      const path = join(ROOT, name);
      return existsSync(path) && statSync(path).size === 0;
    });
    expect(empty).toEqual([]);
  });
});