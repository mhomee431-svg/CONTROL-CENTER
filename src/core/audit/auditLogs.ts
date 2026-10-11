import type { AuditLogItem } from '@/core/types/admin';

/**
 * AUDIT LOG CENTER — field resolution.
 *
 * The requirement: every sensitive admin action must be traceable, showing
 *
 *   Admin Action · Entity · Entity ID · Timestamp · Reason (where applicable)
 *   · Result · Request/Correlation ID (where provided)
 *   · before/after (when the backend supplies it)
 *
 * The backend stores each event as an `AuditLog` row whose only structured
 * column is a free-form `details` JSON blob. Different writers populate it
 * differently yesterday (`{"reason": ...}`, `{"status": ...}`, `{"from": ...,
 * "to": ...}`), and a future backend will publish `reason`/`result`/
 * `request_id`/`before`/`after` as first-class columns.
 *
 * Rather than teach the grid about every writer, this module resolves each
 * display field once, preferring a first-class column when the backend sends
 * one and falling back to a well-known `details` key. A missing value is
 * reported as `null` so the UI renders "Not reported" — never an invented
 * value, and never a blank that reads as "the action had no reason".
 */

/** Keys inside `details` that are treated as the operator's justification. */
const REASON_KEYS = ['reason', 'justification', 'note', 'comment'] as const;

/** Keys inside `details` that describe the outcome of the action. */
const RESULT_KEYS = ['result', 'outcome', 'status', 'state'] as const;

/** Keys inside `details` that carry a correlation / request id. */
const REQUEST_ID_KEYS = ['request_id', 'correlation_id', 'trace_id', 'requestId'] as const;

/** Keys inside `details` that carry an explicit severity. */
const SEVERITY_KEYS = ['severity', 'level'] as const;

/** Keys inside `details` holding the pre-change snapshot. */
const BEFORE_KEYS = ['before', 'old', 'previous', 'from'] as const;

/** Keys inside `details` holding the post-change snapshot. */
const AFTER_KEYS = ['after', 'new', 'current', 'to'] as const;

/** A single resolved line in the before → after diff. */
export interface AuditChange {
  field: string;
  before: string | null;
  after: string | null;
}

/** The fully-resolved audit row the Audit Log Center renders. */
export interface ResolvedAuditEntry {
  id: number;
  action: string;
  entityType: string | null;
  entityId: number | string | null;
  /** The operator name, falling back to the numeric user id, then "System". */
  admin: string;
  createdAt: string | null;
  reason: string | null;
  result: string | null;
  /** INFO | WARNING | CRITICAL — resolved from the column, details, or action. */
  severity: string | null;
  requestId: string | null;
  ipAddress: string | null;
  /** Flattened before→after diff; empty when the backend supplied neither. */
  changes: AuditChange[];
  /** Raw `details`, still available for an "all fields" view. */
  details: Record<string, unknown> | null;
}

/** True for a non-null, non-empty string. */
function isMeaningfulString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

/**
 * Reads the first present key from a record. Returns `undefined` when none of
 * the candidate keys exist, so callers can distinguish "absent" from "null".
 */
function firstPresent(
  source: Record<string, unknown> | null | undefined,
  keys: ReadonlyArray<string>
): unknown {
  if (!source) return undefined;
  for (const key of keys) {
    if (Object.prototype.hasOwnProperty.call(source, key)) {
      return source[key];
    }
  }
  return undefined;
}

/** Renders any JSON value as a compact, displayable string. */
export function stringifyAuditValue(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return value.trim().length > 0 ? value : null;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

/**
 * Resolves the operator justification. Prefers a first-class `reason` column,
 * then the well-known keys inside `details`.
 */
export function resolveReason(row: Pick<AuditLogItem, 'reason' | 'details'>): string | null {
  if (isMeaningfulString(row.reason)) return row.reason.trim();
  const fromDetails = firstPresent(row.details, REASON_KEYS);
  return isMeaningfulString(fromDetails) ? fromDetails.trim() : null;
}

/**
 * Resolves the outcome. Prefers a first-class `result` column, then the
 * well-known keys inside `details`. Values are upper-cased so a badge can
 * match them case-insensitively against SUCCESS / FAILED / PARTIAL.
 */
export function resolveResult(row: Pick<AuditLogItem, 'result' | 'details'>): string | null {
  const raw = isMeaningfulString(row.result)
    ? row.result
    : firstPresent(row.details, RESULT_KEYS);
  if (!isMeaningfulString(raw)) return null;
  return raw.trim().toUpperCase();
}

/**
 * Resolves the correlation id. Prefers a first-class `request_id` column, then
 * the well-known keys inside `details`. A bare entity id is deliberately NOT
 * used — a correlation id must identify the request, not the record.
 */
export function resolveRequestId(
  row: Pick<AuditLogItem, 'request_id' | 'details'>
): string | null {
  if (isMeaningfulString(row.request_id)) return row.request_id.trim();
  const fromDetails = firstPresent(row.details, REQUEST_ID_KEYS);
  return isMeaningfulString(fromDetails) ? fromDetails.trim() : null;
}

/** Action-name fragments that mark a hard-destructive event (CRITICAL). */
const CRITICAL_MARKERS = ['delete', 'purge', 'wipe', 'revoke', 'reset'] as const;

/** Action-name fragments that mark a high-impact event (WARNING). */
const WARNING_MARKERS = [
  'archive',
  'suspend',
  'reject',
  'ban',
  'deactivate',
  'disable',
  'revoke',
  'override',
  'force',
] as const;

/**
 * Resolves the severity of an audit event.
 *
 * Prefers a first-class `severity` column, then an explicit `severity`/`level`
 * inside `details`, and otherwise derives it from the action name so a
 * destructive action is never presented as merely informational. This mirrors
 * the backend's own derivation so the badge and the server-side filter agree.
 */
export function resolveSeverity(
  row: Pick<AuditLogItem, 'action' | 'severity' | 'details'>
): string {
  const explicit = isMeaningfulString(row.severity)
    ? row.severity
    : firstPresent(row.details, SEVERITY_KEYS);
  if (isMeaningfulString(explicit)) return explicit.trim().toUpperCase();

  const action = (row.action || '').toLowerCase();
  if (CRITICAL_MARKERS.some((m) => action.includes(m))) return 'CRITICAL';
  if (WARNING_MARKERS.some((m) => action.includes(m))) return 'WARNING';
  return 'INFO';
}

/**
 * Builds the before→after diff.
 *
 * Two shapes are supported:
 *   1. Explicit snapshots — `before`/`after` (or `old`/`new`) objects, compared
 *      key by key so only genuinely changed fields are listed.
 *   2. Transition scalars — `from`/`to` (or the older `{"from": X, "to": Y}`
 *      verification payload), reported as a single change line.
 *
 * Returns an empty array when the backend supplied neither, so the UI can say
 * "before/after not supplied" instead of rendering an empty-looking diff.
 */
export function resolveAuditChanges(
  row: Pick<AuditLogItem, 'before' | 'after' | 'details'>
): AuditChange[] {
  const details = (row.details ?? null) as Record<string, unknown> | null;

  const before =
    (row.before as Record<string, unknown> | null | undefined) ??
    (firstPresent(details, BEFORE_KEYS) as Record<string, unknown> | null | undefined);
  const after =
    (row.after as Record<string, unknown> | null | undefined) ??
    (firstPresent(details, AFTER_KEYS) as Record<string, unknown> | null | undefined);

  const isRecord = (v: unknown): v is Record<string, unknown> =>
    typeof v === 'object' && v !== null && !Array.isArray(v);

  // Shape 1: object snapshots → per-field comparison.
  if (isRecord(before) || isRecord(after)) {
    const beforeObj = isRecord(before) ? before : {};
    const afterObj = isRecord(after) ? after : {};
    const fields = Array.from(
      new Set([...Object.keys(beforeObj), ...Object.keys(afterObj)])
    ).sort();

    const changes: AuditChange[] = [];
    for (const field of fields) {
      const b = stringifyAuditValue(beforeObj[field]);
      const a = stringifyAuditValue(afterObj[field]);
      if (b !== a) {
        changes.push({ field, before: b, after: a });
      }
    }
    if (changes.length > 0) return changes;
  }

  // Shape 2: scalar transition → one change line.
  const fromVal = stringifyAuditValue(before);
  const toVal = stringifyAuditValue(after);
  if (fromVal !== null || toVal !== null) {
    return [{ field: 'state', before: fromVal, after: toVal }];
  }

  return [];
}

/**
 * Resolves one raw backend row into the complete set of columns the Audit Log
 * Center renders. Pure and synchronous so it is trivially testable and safe to
 * call inside a grid `valueGetter`.
 */
export function resolveAuditEntry(row: AuditLogItem): ResolvedAuditEntry {
  const admin =
    (isMeaningfulString(row.admin_user) && row.admin_user.trim()) ||
    (row.user_id != null ? `User #${row.user_id}` : 'System');

  return {
    id: row.id,
    action: row.action,
    entityType: row.entity_type ?? null,
    entityId: row.entity_id ?? null,
    admin,
    createdAt: row.created_at ?? null,
    reason: resolveReason(row),
    result: resolveResult(row),
    severity: resolveSeverity(row),
    requestId: resolveRequestId(row),
    ipAddress: isMeaningfulString(row.ip_address) ? row.ip_address : null,
    changes: resolveAuditChanges(row),
    details: row.details ?? null,
  };
}
