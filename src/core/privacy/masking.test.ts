import { describe, it, expect } from 'vitest';
import {
  FORBIDDEN_FIELDS,
  stripForbiddenFields,
  containsForbiddenFields,
  maskEmail,
  maskPhone,
  maskIdentifier,
  summarizeLocation,
} from '@/core/privacy/masking';

describe('customer privacy contract', () => {
  it('strips credential fields from nested payloads', () => {
    const payload = {
      id: 1,
      name: 'Asha',
      password: 'hunter2',
      otp: '123456',
      profile: {
        email: 'a@b.com',
        access_token: 'eyJhbGciOi...',
        devices: [{ id: 'd1', refresh_token: 'rt_secret' }],
      },
    };

    const clean = stripForbiddenFields(payload);

    expect(containsForbiddenFields(clean)).toBeNull();
    expect((clean as Record<string, unknown>).password).toBeUndefined();
    expect((clean as Record<string, unknown>).otp).toBeUndefined();
    expect((clean as unknown as { profile: Record<string, unknown> }).profile.access_token).toBeUndefined();
    expect(
      (clean as unknown as { profile: { devices: Array<Record<string, unknown>> } }).profile.devices[0]
        .refresh_token
    ).toBeUndefined();
    // Legitimate data survives.
    expect((clean as unknown as { profile: { email: string } }).profile.email).toBe('a@b.com');
  });

  it('covers every credential class named in the privacy contract', () => {
    ['password', 'otp', 'token', 'access_token', 'refresh_token', 'api_key', 'secret', 'mfa_secret'].forEach(
      (f) => expect(FORBIDDEN_FIELDS).toContain(f)
    );
  });

  it('detects a forbidden key so a leak is testable', () => {
    expect(containsForbiddenFields({ ok: { password_hash: 'x' } })).toBe('ok.password_hash');
    expect(containsForbiddenFields({ fine: 1 })).toBeNull();
  });

  it('masks email while preserving the domain', () => {
    // 7-char local part → first + 5 stars (capped) + last.
    expect(maskEmail('shopper@example.com')).toBe('s*****r@example.com');
    expect(maskEmail('ab@example.com')).toBe('a*@example.com');
    expect(maskEmail('')).toBe('—');
    expect(maskEmail(null)).toBe('—');
  });

  it('masks phone keeping only the last two digits', () => {
    // +91 country code + 8 digits -> 10 digits total -> 8 dots + last 2.
    expect(maskPhone('+919811234567')).toBe('+91••••••••67');
    // Bare 10-digit number -> 6 dots + last 2.
    expect(maskPhone('9811234567')).toBe('••••••67');
  });

  it('honours operator permission when masking identifiers', () => {
    expect(maskIdentifier('9811234567', 'phone', true)).toBe('9811234567');
    expect(maskIdentifier('9811234567', 'phone', false)).not.toBe('9811234567');
    expect(maskIdentifier('Asha Rao', 'name', false)).toBe('A*****o');
    expect(maskIdentifier(null, 'email', false)).toBe('—');
  });

  it('summarizes location at coarse granularity only', () => {
    expect(summarizeLocation({ area: 'Saket', city: 'New Delhi', state: 'DL' })).toBe(
      'Saket, New Delhi, DL'
    );
    expect(summarizeLocation(null)).toBe('—');
    expect(summarizeLocation({})).toBe('—');
  });
});