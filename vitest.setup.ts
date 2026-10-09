import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';

/**
 * Explicit DOM cleanup between tests.
 *
 * This suite runs with `isolate: false` + `singleThread: true`, so every test
 * file shares one module registry and one jsdom document. Testing Library's
 * automatic cleanup only registers itself when `afterEach` is a real global at
 * import time; under this configuration it can be missed, and a previously
 * rendered tree leaks into the next test's DOM assertions — which is exactly
 * how `PermissionGuard.test.tsx` intermittently saw a stale "secret" node.
 *
 * Registering cleanup explicitly makes every test start from a clean document,
 * regardless of global availability or execution order.
 */
afterEach(() => {
  cleanup();
});
