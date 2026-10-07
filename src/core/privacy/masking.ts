/**
 * Customer Privacy & Data-Minimisation Utilities
 *
 * The privacy contract is strict and non-negotiable:
 *   - Never display passwords, OTPs, authentication tokens or security credentials.
 *   - Show the minimum necessary; mask identifiers unless the operator is permitted.
 *
 * These helpers are the single enforcement point. Detail pages must route every
 * personal field through them rather than rendering raw values, so a future
 * field addition cannot accidentally leak a credential.
 */

/** Fields that must NEVER be rendered in the admin UI, in any form. */
export const FORBIDDEN_FIELDS: ReadonlyArray<string> = [
  'password',
  'password_hash',
  'hashed_password',
  'otp',
  'otp_code',
  'otp_hash',
  'token',
  'access_token',
  'refresh_token',
  'id_token',
  'auth_token',
  'session_token',
  'api_key',
  'secret',
  'client_secret',
  'private_key',
  'salt',
  'two_factor_secret',
  'mfa_secret',
  'credential',
  'credentials',
];

/**
 * Defence in depth: strips forbidden keys from any backend payload before it
 * reaches a component. The backend should never send these, but a frontend
 * that trusts that assumption has already lost.
 */
export function stripForbiddenFields<T>(input: T): T {
  if (Array.isArray(input)) {
    return input.map((item) => stripForbiddenFields(item)) as unknown as T;
  }
  if (input && typeof input === 'object') {
    const out: Record<string, unknown> = {};
    Object.entries(input as Record<string, unknown>).forEach(([key, value]) => {
      if (FORBIDDEN_FIELDS.includes(key.toLowerCase())) return;
      out[key] = stripForbiddenFields(value);
    });
    return out as T;
  }
  return input;
}

/** True when a payload contains any forbidden key (used by tests). */
export function containsForbiddenFields(input: unknown, path = ''): string | null {
  if (Array.isArray(input)) {
    for (const item of input) {
      const found = containsForbiddenFields(item, path);
      if (found) return found;
    }
    return null;
  }
  if (input && typeof input === 'object') {
    for (const [key, value] of Object.entries(input as Record<string, unknown>)) {
      if (FORBIDDEN_FIELDS.includes(key.toLowerCase())) {
        return path ? `${path}.${key}` : key;
      }
      const found = containsForbiddenFields(value, path ? `${path}.${key}` : key);
      if (found) return found;
    }
  }
  return null;
}

/**
 * Masks an email, preserving only enough to identify the account.
 * `shopper@example.com` → `s****r@example.com`
 */
export function maskEmail(email?: string | null): string {
  if (!email) return '—';
  const at = email.indexOf('@');
  if (at <= 0) return '—';
  const local = email.slice(0, at);
  const domain = email.slice(at);
  if (local.length <= 2) return `${local[0] ?? '*'}*${domain}`;
  return `${local[0]}${'*'.repeat(Math.min(local.length - 2, 5))}${local[local.length - 1]}${domain}`;
}

/**
 * Masks a phone number, keeping the country code and last two digits only.
 * `+919811234567` → `+91•••••67`
 */
export function maskPhone(phone?: string | null): string {
  if (!phone) return '—';
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 4) return '•'.repeat(digits.length);
  const prefix = phone.startsWith('+') ? `+${digits.slice(0, 2)}` : '';
  return `${prefix}${'•'.repeat(Math.max(digits.length - 4, 0))}${digits.slice(-2)}`;
}

/**
 * General personal-data mask honouring operator permission.
 * When `permitted` is true the raw value is returned; otherwise a masked form
 * is produced. Callers pass the resolved permission so masking is not a
 * hardcoded policy decision in the view layer.
 */
export function maskIdentifier(
  value: string | null | undefined,
  kind: 'phone' | 'email' | 'name',
  permitted: boolean
): string {
  if (!value) return '—';
  if (permitted) return value;
  if (kind === 'email') return maskEmail(value);
  if (kind === 'phone') return maskPhone(value);
  const trimmed = value.trim();
  if (trimmed.length <= 2) return `${trimmed[0] ?? '*'}*`;
  return `${trimmed[0]}${'*'.repeat(Math.min(trimmed.length - 2, 5))}${trimmed[trimmed.length - 1]}`;
}

/** Coarse location granularity — never a precise home address. */
export function summarizeLocation(
  location?: { city?: string | null; state?: string | null; area?: string | null } | null
): string {
  if (!location) return '—';
  const parts = [location.area, location.city, location.state].filter(Boolean);
  return parts.length > 0 ? parts.join(', ') : '—';
}

/** Renders a relative time description, used by "recently registered/active" views. */
export function describeRecency(value?: string | null): string {
  if (!value) return '—';
  const ts = new Date(value).getTime();
  if (Number.isNaN(ts)) return '—';
  const ageMs = Date.now() - ts;
  if (ageMs < 0) return 'Just now';
  const days = Math.floor(ageMs / 86_400_000);
  if (days < 1) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days <= 7) return `${days} days ago`;
  if (days <= 30) return `${Math.floor(days / 7)} week(s) ago`;
  if (days <= 365) return `${Math.floor(days / 30)} month(s) ago`;
  return `${Math.floor(days / 365)} year(s) ago`;
}