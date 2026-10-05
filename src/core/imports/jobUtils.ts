/**
 * IMPORT CENTER — Presentation & Safety Helpers
 *
 * Pure functions shared by the Import Center list and detail views, plus the
 * report-download safety gate.
 *
 * The backend stays authoritative: these helpers only derive display values and
 * decide whether a control may be offered. They never fabricate job state.
 */

import {
  ImportJobItem,
  ImportJobStatus,
  isActiveImportStatus,
  isTerminalImportStatus,
} from '../types/imports';

/** Normalize a possibly-missing status to the known lifecycle set. */
export function normalizeStatus(status?: string | null): ImportJobStatus | 'UNKNOWN' {
  const upper = (status || '').toUpperCase();
  const known: ImportJobStatus[] = [
    'UPLOADED',
    'VALIDATING',
    'PROCESSING',
    'COMPLETED',
    'PARTIAL',
    'FAILED',
    'CANCELLED',
  ];
  return known.includes(upper as ImportJobStatus) ? (upper as ImportJobStatus) : 'UNKNOWN';
}

/** True while the job is still moving through the pipeline. */
export function isJobActive(job?: Pick<ImportJobItem, 'status'> | null): boolean {
  return isActiveImportStatus(job?.status);
}

/** True once the job has reached a final state. */
export function isJobTerminal(job?: Pick<ImportJobItem, 'status'> | null): boolean {
  return isTerminalImportStatus(job?.status);
}

function num(value?: number | null): number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0;
}

/**
 * Completion percentage (0–100) for the progress bar.
 *
 * Processed rows drive the bar when a total is known; a finished job is always
 * 100% regardless of reported counters, so a PARTIAL job does not look stalled.
 */
export function progressPercent(job?: ImportJobItem | null): number {
  if (!job) return 0;
  if (isJobTerminal(job)) return 100;

  const total = num(job.rows_total);
  if (total === 0) return 0;

  const processed = num(job.rows_processed);
  return Math.min(100, Math.max(0, Math.round((processed / total) * 100)));
}

/** Rows that were rejected for any reason (invalid + duplicates + failed). */
export function rejectedRowCount(job?: ImportJobItem | null): number {
  if (!job) return 0;
  const explicit = num(job.rows_failed);
  if (explicit > 0) return explicit;
  return num(job.rows_invalid) + num(job.rows_duplicate);
}

/** Rows successfully ingested. */
export function ingestedRowCount(job?: ImportJobItem | null): number {
  if (!job) return 0;
  const processed = num(job.rows_processed);
  if (processed > 0) return processed;
  return num(job.rows_valid);
}

/**
 * Wall-clock duration between start and finish, in whole seconds.
 *
 * Returns null while the job is still running (no finish timestamp yet), so the
 * UI can show a live indicator instead of a misleading zero.
 */
export function jobDurationSeconds(job?: ImportJobItem | null): number | null {
  if (!job?.started_at) return null;
  const start = new Date(job.started_at).getTime();
  if (Number.isNaN(start)) return null;

  if (!job.finished_at) return null;
  const end = new Date(job.finished_at).getTime();
  if (Number.isNaN(end)) return null;

  const seconds = Math.round((end - start) / 1000);
  return seconds < 0 ? 0 : seconds;
}

/** Compact human duration, e.g. "2m 05s". Returns null when not computable. */
export function formatDuration(job?: ImportJobItem | null): string | null {
  const seconds = jobDurationSeconds(job);
  if (seconds === null) return null;
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  const remaining = seconds % 60;
  if (minutes < 60) return `${minutes}m ${String(remaining).padStart(2, '0')}s`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${String(minutes % 60).padStart(2, '0')}m`;
}

/** Success rate as a whole percentage, or null when no rows were attempted. */
export function successRate(job?: ImportJobItem | null): number | null {
  if (!job) return null;
  const total = num(job.rows_total);
  if (total === 0) return null;
  return Math.round((ingestedRowCount(job) / total) * 100);
}

/** Human label for the ingestion source. */
export function sourceLabel(job?: ImportJobItem | null): string {
  const explicit = (job?.source_type || '').toUpperCase();
  if (explicit === 'EXCEL' || explicit === 'CSV' || explicit === 'POS' || explicit === 'BULK') {
    return explicit;
  }
  return job?.source || 'Bulk';
}

/** File extension of the uploaded artifact, uppercased, or null. */
export function fileExtension(job?: ImportJobItem | null): string | null {
  const name = job?.file_name;
  if (!name) return null;
  const idx = name.lastIndexOf('.');
  if (idx === -1 || idx === name.length - 1) return null;
  return name.slice(idx + 1).toUpperCase();
}

/** Size of a byte count for display, e.g. 1.4 MB. */
export function formatBytes(bytes?: number | null): string | null {
  if (typeof bytes !== 'number' || !Number.isFinite(bytes) || bytes < 0) return null;
  if (bytes < 1024) return `${bytes} B`;
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1024;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(1)} ${units[unitIndex]}`;
}

/**
 * Retry is offered only for terminal jobs that actually failed partially or
 * wholly. A COMPLETED or CANCELLED job has nothing to retry.
 *
 * The backend may additionally gate this via `can_retry`; when it explicitly
 * says false we honour that and hide the control.
 */
export function canRetryJob(job?: ImportJobItem | null): boolean {
  if (!job) return false;
  if (job.can_retry === false) return false;
  if (!isJobTerminal(job)) return false;
  const status = normalizeStatus(job.status);
  return status === 'PARTIAL' || status === 'FAILED';
}

/** Cancellation is only meaningful while a job is still in flight. */
export function canCancelJob(job?: ImportJobItem | null): boolean {
  if (!job) return false;
  if (job.can_cancel === false) return false;
  return isJobActive(job);
}

/**
 * Report download is offered only when the job finished and the backend exposes
 * a report URL (or the operator's role implies it).
 */
export function canDownloadReport(job?: ImportJobItem | null): boolean {
  if (!job) return false;
  if (job.can_download_report === false) return false;
  return isJobTerminal(job);
}

/**
 * Download gate for the ingestion report artifact.
 *
 * A report must be a root-relative path served by our own backend (typically a
 * signed file under the ingestion reports prefix). Absolute hosts,
 * protocol-relative URLs, `javascript:`/`data:` schemes and path traversal are
 * all rejected, so a crafted `report_url` can never redirect the operator off
 * the platform or execute script.
 */
export function validateReportUrl(url?: string | null): { valid: boolean; url?: string; reason?: string } {
  if (!url) return { valid: false, reason: 'No report is available for this job.' };

  const value = String(url).trim();

  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) {
    return { valid: false, reason: 'Report URLs must be relative paths served by the backend.' };
  }
  if (value.startsWith('//')) {
    return { valid: false, reason: 'Protocol-relative report URLs are not permitted.' };
  }
  if (value.includes('..') || /%2e%2e/i.test(value)) {
    return { valid: false, reason: 'Path traversal is not permitted in report URLs.' };
  }
  if (!value.startsWith('/')) {
    return { valid: false, reason: 'Report URLs must be root-relative.' };
  }

  // Reject control characters and whitespace that could smuggle a second header
  // or break out of the path segment.
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001F\u007F\s]/.test(value)) {
    return { valid: false, reason: 'Report URL contains illegal whitespace or control characters.' };
  }

  return { valid: true, url: value };
}