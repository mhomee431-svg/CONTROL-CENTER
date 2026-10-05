import { describe, it, expect } from 'vitest';
import {
  canCancelJob,
  canDownloadReport,
  canRetryJob,
  fileExtension,
  formatBytes,
  formatDuration,
  ingestedRowCount,
  isJobActive,
  isJobTerminal,
  jobDurationSeconds,
  normalizeStatus,
  progressPercent,
  rejectedRowCount,
  sourceLabel,
  successRate,
  validateReportUrl,
} from './jobUtils';
import { ImportJobItem, IMPORT_JOB_STATUSES } from '../types/imports';

const job = (over: Partial<ImportJobItem> = {}): ImportJobItem => ({
  id: 1,
  status: 'UPLOADED',
  rows_total: 100,
  ...over,
});

describe('Import lifecycle statuses', () => {
  it('covers the full documented lifecycle', () => {
    expect(IMPORT_JOB_STATUSES).toEqual([
      'UPLOADED',
      'VALIDATING',
      'PROCESSING',
      'COMPLETED',
      'PARTIAL',
      'FAILED',
      'CANCELLED',
    ]);
  });

  it('normalizes known statuses case-insensitively', () => {
    expect(normalizeStatus('processing')).toBe('PROCESSING');
    expect(normalizeStatus('PARTIAL')).toBe('PARTIAL');
    expect(normalizeStatus('nonsense')).toBe('UNKNOWN');
    expect(normalizeStatus(null)).toBe('UNKNOWN');
  });

  it('treats in-flight statuses as active and the rest as terminal', () => {
    expect(isJobActive(job({ status: 'UPLOADED' }))).toBe(true);
    expect(isJobActive(job({ status: 'VALIDATING' }))).toBe(true);
    expect(isJobActive(job({ status: 'PROCESSING' }))).toBe(true);

    ['COMPLETED', 'PARTIAL', 'FAILED', 'CANCELLED'].forEach((status) => {
      expect(isJobActive(job({ status }))).toBe(false);
      expect(isJobTerminal(job({ status }))).toBe(true);
    });
  });
});

describe('Row accounting', () => {
  it('computes progress from processed over total', () => {
    expect(progressPercent(job({ status: 'PROCESSING', rows_total: 200, rows_processed: 50 }))).toBe(25);
  });

  it('returns 100% for any terminal job, even PARTIAL', () => {
    expect(progressPercent(job({ status: 'PARTIAL', rows_total: 10, rows_processed: 7 }))).toBe(100);
    expect(progressPercent(job({ status: 'FAILED', rows_total: 10, rows_processed: 0 }))).toBe(100);
    expect(progressPercent(job({ status: 'CANCELLED', rows_total: 10, rows_processed: 3 }))).toBe(100);
  });

  it('never exceeds 0-100 bounds or divides by zero', () => {
    expect(progressPercent(job({ rows_total: 0, rows_processed: 0 }))).toBe(0);
    expect(progressPercent(job({ rows_total: 10, rows_processed: 999 }))).toBe(100);
    expect(progressPercent(null)).toBe(0);
  });

  it('sums invalid + duplicate rows when no explicit failure count exists', () => {
    expect(rejectedRowCount(job({ rows_invalid: 3, rows_duplicate: 2 }))).toBe(5);
  });

  it('prefers an explicit failure count when present', () => {
    expect(rejectedRowCount(job({ rows_invalid: 3, rows_duplicate: 2, rows_failed: 9 }))).toBe(9);
  });

  it('falls back to valid rows when processed is not reported', () => {
    expect(ingestedRowCount(job({ rows_valid: 40 }))).toBe(40);
    expect(ingestedRowCount(job({ rows_processed: 25, rows_valid: 40 }))).toBe(25);
  });

  it('computes success rate only when rows were attempted', () => {
    expect(successRate(job({ rows_total: 200, rows_processed: 180 }))).toBe(90);
    expect(successRate(job({ rows_total: 0 }))).toBeNull();
    expect(successRate(null)).toBeNull();
  });
});

describe('Duration', () => {
  it('returns null while a job is still running', () => {
    expect(jobDurationSeconds(job({ started_at: '2026-01-01T00:00:00Z' }))).toBeNull();
    expect(formatDuration(job({ started_at: '2026-01-01T00:00:00Z' }))).toBeNull();
  });

  it('computes elapsed seconds once finished', () => {
    const j = job({ started_at: '2026-01-01T00:00:00Z', finished_at: '2026-01-01T00:00:45Z' });
    expect(jobDurationSeconds(j)).toBe(45);
    expect(formatDuration(j)).toBe('45s');
  });

  it('formats minutes and hours compactly', () => {
    const m = job({ started_at: '2026-01-01T00:00:00Z', finished_at: '2026-01-01T00:02:05Z' });
    expect(formatDuration(m)).toBe('2m 05s');
    const h = job({ started_at: '2026-01-01T00:00:00Z', finished_at: '2026-01-01T03:07:00Z' });
    expect(formatDuration(h)).toBe('3h 07m');
  });

  it('clamps negative durations to zero and ignores missing start', () => {
    expect(
      jobDurationSeconds(job({ started_at: '2026-01-01T01:00:00Z', finished_at: '2026-01-01T00:00:00Z' }))
    ).toBe(0);
    expect(jobDurationSeconds(job({ finished_at: '2026-01-01T00:00:00Z' }))).toBeNull();
  });
});

describe('Action gating', () => {
  it('offers retry only for PARTIAL or FAILED terminal jobs', () => {
    expect(canRetryJob(job({ status: 'PARTIAL' }))).toBe(true);
    expect(canRetryJob(job({ status: 'FAILED' }))).toBe(true);
    expect(canRetryJob(job({ status: 'COMPLETED' }))).toBe(false);
    expect(canRetryJob(job({ status: 'CANCELLED' }))).toBe(false);
    expect(canRetryJob(job({ status: 'PROCESSING' }))).toBe(false);
    expect(canRetryJob(null)).toBe(false);
  });

  it('honours an explicit backend can_retry=false', () => {
    expect(canRetryJob(job({ status: 'FAILED', can_retry: false }))).toBe(false);
  });

  it('offers cancel only while the job is in flight', () => {
    expect(canCancelJob(job({ status: 'PROCESSING' }))).toBe(true);
    expect(canCancelJob(job({ status: 'UPLOADED' }))).toBe(true);
    expect(canCancelJob(job({ status: 'COMPLETED' }))).toBe(false);
    expect(canCancelJob(job({ status: 'PROCESSING', can_cancel: false }))).toBe(false);
  });

  it('offers a report only for finished jobs', () => {
    expect(canDownloadReport(job({ status: 'COMPLETED' }))).toBe(true);
    expect(canDownloadReport(job({ status: 'PARTIAL' }))).toBe(true);
    expect(canDownloadReport(job({ status: 'PROCESSING' }))).toBe(false);
    expect(canDownloadReport(job({ status: 'COMPLETED', can_download_report: false }))).toBe(false);
  });
});

describe('Source + file metadata', () => {
  it('labels known source families', () => {
    expect(sourceLabel(job({ source_type: 'EXCEL' }))).toBe('EXCEL');
    expect(sourceLabel(job({ source_type: 'csv' }))).toBe('CSV');
    expect(sourceLabel(job({ source_type: 'POS' }))).toBe('POS');
    expect(sourceLabel(job({ source_type: 'BULK' }))).toBe('BULK');
  });

  it('falls back to the free-text source then to Bulk', () => {
    expect(sourceLabel(job({ source: 'POS Sync — Store 12' }))).toBe('POS Sync — Store 12');
    expect(sourceLabel(job({}))).toBe('Bulk');
  });

  it('extracts the file extension', () => {
    expect(fileExtension(job({ file_name: 'inventory-march.xlsx' }))).toBe('XLSX');
    expect(fileExtension(job({ file_name: 'shop.csv' }))).toBe('CSV');
    expect(fileExtension(job({ file_name: 'noextension' }))).toBeNull();
    expect(fileExtension(job({}))).toBeNull();
  });

  it('formats byte sizes', () => {
    expect(formatBytes(512)).toBe('512 B');
    expect(formatBytes(2048)).toBe('2.0 KB');
    expect(formatBytes(1024 * 1024 * 3)).toBe('3.0 MB');
    expect(formatBytes(null)).toBeNull();
  });
});

describe('Report download safety gate', () => {
  it('accepts a root-relative backend asset path', () => {
    const result = validateReportUrl('/reports/import-42.csv');
    expect(result.valid).toBe(true);
    expect(result.url).toBe('/reports/import-42.csv');
  });

  it('blocks scheme-bearing URLs', () => {
    ['https://evil.com/r.csv', 'javascript:alert(1)', 'data:text/csv,x'].forEach((url) => {
      expect(validateReportUrl(url).valid).toBe(false);
    });
  });

  it('blocks protocol-relative URLs', () => {
    expect(validateReportUrl('//evil.com/r.csv').valid).toBe(false);
  });

  it('blocks traversal', () => {
    expect(validateReportUrl('/reports/../../etc/passwd').valid).toBe(false);
    expect(validateReportUrl('/reports/%2e%2e/x').valid).toBe(false);
  });

  it('blocks relative and whitespace-bearing paths', () => {
    expect(validateReportUrl('reports/x.csv').valid).toBe(false);
    expect(validateReportUrl('/reports/a b.csv').valid).toBe(false);
  });

  it('reports a clear reason when no report exists', () => {
    expect(validateReportUrl(null).reason).toBeTruthy();
    expect(validateReportUrl(undefined).valid).toBe(false);
  });
});