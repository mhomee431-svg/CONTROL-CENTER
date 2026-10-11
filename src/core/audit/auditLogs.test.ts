import { describe, it, expect } from 'vitest';
import {
  resolveReason,
  resolveResult,
  resolveSeverity,
  resolveRequestId,
  resolveAuditChanges,
  resolveAuditEntry,
  stringifyAuditValue,
} from '@/core/audit/auditLogs';
import type { AuditLogItem } from '@/core/types/admin';

function row(partial: Partial<AuditLogItem>): AuditLogItem {
  return {
    id: 1,
    action: 'shop.verification.verified',
    entity_type: 'shop',
    created_at: '2026-10-01T10:00:00Z',
    ...partial,
  };
}

describe('audit log center — field resolution', () => {
  it('prefers a first-class reason column over the details blob', () => {
    expect(resolveReason(row({ reason: '  Approved after review  ', details: { reason: 'stale' } }))).toBe(
      'Approved after review'
    );
  });

  it('falls back to well-known keys inside details', () => {
    expect(resolveReason(row({ details: { justification: 'Fraud suspected' } }))).toBe('Fraud suspected');
    expect(resolveReason(row({ details: { note: 'Called the merchant' } }))).toBe('Called the merchant');
    expect(resolveReason(row({ details: {} }))).toBeNull();
    expect(resolveReason(row({}))).toBeNull();
  });

  it('ignores a blank reason rather than rendering an empty string', () => {
    expect(resolveReason(row({ reason: '   ' }))).toBeNull();
  });

  it('normalises the result to upper case and prefers the column', () => {
    expect(resolveResult(row({ result: 'success' }))).toBe('SUCCESS');
    expect(resolveResult(row({ details: { status: 'partial' } }))).toBe('PARTIAL');
    expect(resolveResult(row({}))).toBeNull();
  });

  it('resolves a correlation id only from request-shaped keys', () => {
    expect(resolveRequestId(row({ request_id: 'req-123' }))).toBe('req-123');
    expect(resolveRequestId(row({ details: { correlation_id: 'corr-9' } }))).toBe('corr-9');
    // An entity id is NOT a correlation id.
    expect(resolveRequestId(row({ entity_id: 42 }))).toBeNull();
    expect(resolveRequestId(row({}))).toBeNull();
  });

  it('prefers an explicit severity over the action-derived value', () => {
    expect(resolveSeverity(row({ action: 'shop.deleted', severity: 'info' }))).toBe('INFO');
    expect(resolveSeverity(row({ action: 'shop.verified', details: { severity: 'warning' } }))).toBe(
      'WARNING'
    );
  });

  it('derives CRITICAL for destructive actions and WARNING for high-impact ones', () => {
    expect(resolveSeverity(row({ action: 'shop.deleted' }))).toBe('CRITICAL');
    expect(resolveSeverity(row({ action: 'admin_user.access_reset' }))).toBe('CRITICAL');
    expect(resolveSeverity(row({ action: 'shop.archived' }))).toBe('WARNING');
    expect(resolveSeverity(row({ action: 'admin_user.deactivated' }))).toBe('WARNING');
    expect(resolveSeverity(row({ action: 'shop.updated' }))).toBe('INFO');
  });

  it('builds a per-field diff from before/after object snapshots', () => {
    const changes = resolveAuditChanges(
      row({
        before: { name: 'Old Shop', status: 'PENDING' },
        after: { name: 'New Shop', status: 'PENDING' },
      })
    );
    expect(changes).toEqual([{ field: 'name', before: 'Old Shop', after: 'New Shop' }]);
  });

  it('reads before/after from the details blob when not first-class', () => {
    const changes = resolveAuditChanges(
      row({ details: { before: { price: 10 }, after: { price: 12 } } })
    );
    expect(changes).toEqual([{ field: 'price', before: '10', after: '12' }]);
  });

  it('reports a scalar state transition as a single change line', () => {
    const changes = resolveAuditChanges(row({ details: { from: 'PENDING', to: 'VERIFIED' } }));
    expect(changes).toEqual([{ field: 'state', before: 'PENDING', after: 'VERIFIED' }]);
  });

  it('returns no changes when the backend supplied neither snapshot', () => {
    expect(resolveAuditChanges(row({ details: { reason: 'no snapshot here' } }))).toEqual([]);
    expect(resolveAuditChanges(row({}))).toEqual([]);
  });

  it('resolves a complete entry with a fallback admin name', () => {
    const entry = resolveAuditEntry(
      row({
        admin_user: null,
        user_id: 7,
        entity_id: 55,
        details: { reason: 'Policy breach', result: 'failed' },
      })
    );
    expect(entry.admin).toBe('User #7');
    expect(entry.entityType).toBe('shop');
    expect(entry.entityId).toBe(55);
    expect(entry.reason).toBe('Policy breach');
    expect(entry.result).toBe('FAILED');
    expect(entry.createdAt).toBe('2026-10-01T10:00:00Z');
    expect(entry.severity).toBe('INFO');
  });

  it('reports System when no operator is identified', () => {
    expect(resolveAuditEntry(row({})).admin).toBe('System');
  });

  it('stringifies JSON values compactly and drops empties', () => {
    expect(stringifyAuditValue('x')).toBe('x');
    expect(stringifyAuditValue(0)).toBe('0');
    expect(stringifyAuditValue(false)).toBe('false');
    expect(stringifyAuditValue({ a: 1 })).toBe('{"a":1}');
    expect(stringifyAuditValue('   ')).toBeNull();
    expect(stringifyAuditValue(null)).toBeNull();
    expect(stringifyAuditValue(undefined)).toBeNull();
  });
});
