import { describe, it, expect } from 'vitest';
import { SAMPLE_EVENT_SHAPE } from '@/core/realtime/liveEvents';
import { ROUTES } from '@/core/routes/routes';
import { capabilityForPath } from '@/core/permissions/routeAccess';
import { CAPABILITIES } from '@/core/permissions/permissions';

describe('realtime event contract', () => {
  it('keeps the sample payload as documentation only', () => {
    // Retained per the "preserve unlinked code" rule, but it must never be
    // rendered as if it were real platform activity.
    expect(Array.isArray(SAMPLE_EVENT_SHAPE)).toBe(true);
    SAMPLE_EVENT_SHAPE.forEach((evt) => {
      expect(evt.id.startsWith('example-')).toBe(true);
      expect(evt.type).toBeTruthy();
      expect(evt.title).toBeTruthy();
    });
  });
});

describe('route registry integrity', () => {
  it('registers the admin notes and payments routes', () => {
    expect(ROUTES.AUDIT_NOTES).toBe('/audit/notes');
    expect(ROUTES.SUBSCRIPTIONS_PAYMENTS).toBe('/subscriptions/payments');
  });

  it('inherits the parent capability for nested routes', () => {
    // Longest-prefix matching must resolve these through /audit.
    expect(capabilityForPath(ROUTES.AUDIT_NOTES)).toBe(CAPABILITIES.AUDIT_READ);
    expect(capabilityForPath(ROUTES.SUBSCRIPTIONS_PAYMENTS)).toBe(CAPABILITIES.SUBSCRIPTIONS_READ);
  });
});