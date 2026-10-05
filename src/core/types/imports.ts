/**
 * IMPORT CENTER — Data Ingestion Models
 *
 * Admins monitor bulk ingestion pipelines across every supported source:
 * Excel workbooks, CSV files, POS integrations and generic bulk uploads.
 */

/** Supported ingestion sources. */
export type ImportSourceType = 'EXCEL' | 'CSV' | 'POS' | 'BULK';

/**
 * The complete import job lifecycle.
 *
 * UPLOADED → VALIDATING → PROCESSING → COMPLETED | PARTIAL | FAILED | CANCELLED
 *
 * PARTIAL means the job finished but some rows were rejected; the valid rows
 * were still ingested. CANCELLED means an operator aborted it mid-flight.
 */
export type ImportJobStatus =
  | 'UPLOADED'
  | 'VALIDATING'
  | 'PROCESSING'
  | 'COMPLETED'
  | 'PARTIAL'
  | 'FAILED'
  | 'CANCELLED';

/** Ordered lifecycle for progress indicators and status chips. */
export const IMPORT_JOB_STATUSES: ReadonlyArray<ImportJobStatus> = [
  'UPLOADED',
  'VALIDATING',
  'PROCESSING',
  'COMPLETED',
  'PARTIAL',
  'FAILED',
  'CANCELLED',
];

/** Statuses that mean the job is still moving. */
export const ACTIVE_IMPORT_STATUSES: ReadonlyArray<ImportJobStatus> = [
  'UPLOADED',
  'VALIDATING',
  'PROCESSING',
];

/** Statuses that are terminal — no further transition will occur. */
export const TERMINAL_IMPORT_STATUSES: ReadonlyArray<ImportJobStatus> = [
  'COMPLETED',
  'PARTIAL',
  'FAILED',
  'CANCELLED',
];

export function isActiveImportStatus(status?: string | null): boolean {
  return ACTIVE_IMPORT_STATUSES.includes((status || '').toUpperCase() as ImportJobStatus);
}

export function isTerminalImportStatus(status?: string | null): boolean {
  return TERMINAL_IMPORT_STATUSES.includes((status || '').toUpperCase() as ImportJobStatus);
}

export interface ImportJobItem {
  id: number;
  /** Original uploaded file name, e.g. "inventory-march.xlsx". */
  file_name?: string | null;
  /** Ingestion source family. */
  source_type?: ImportSourceType | string | null;
  /** Legacy/free-text source label (e.g. "POS Sync — Store 12"). */
  source?: string | null;
  /** Owning shop for shop-scoped imports. */
  shop_id?: number | null;
  shop_name?: string | null;
  status: ImportJobStatus | string;
  rows_total?: number | null;
  rows_valid?: number | null;
  rows_invalid?: number | null;
  rows_duplicate?: number | null;
  rows_processed?: number | null;
  rows_failed?: number | null;
  started_at?: string | null;
  finished_at?: string | null;
  error_message?: string | null;
  uploaded_by?: string | null;
  /** Downloadable report artifact produced by the ingestion pipeline. */
  report_url?: string | null;
  file_size_bytes?: number | null;
  /**
   * Backend-advertised capabilities. When a flag is explicitly false the UI
   * hides that control rather than offering one the API would reject.
   */
  can_retry?: boolean;
  can_cancel?: boolean;
  can_download_report?: boolean;
  created_at?: string;
  updated_at?: string;
}

/** A single row-level rejection produced during validation or processing. */
export interface ImportRowError {
  id?: number;
  /** 1-based row number in the source file. */
  row_number?: number | null;
  /** Column/field that failed validation. */
  field?: string | null;
  /** Human-readable reason for the rejection. */
  error?: string | null;
  /** Raw offending value, for operator triage. */
  value?: string | null;
  /** Severity as classified by the ingestion pipeline. */
  severity?: 'ERROR' | 'WARNING' | string | null;
}

/**
 * Retry is only offered when the backend actually supports it. The list/detail
 * responses may advertise capability flags; when absent the UI stays hidden
 * rather than offering a control the API will reject.
 */
export type ImportJobCapabilities = {
  can_retry?: boolean;
  can_cancel?: boolean;
  can_download_report?: boolean;
};