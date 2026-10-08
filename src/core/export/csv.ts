/**
 * Client-side CSV export for grid data.
 *
 * The DATA GRID RULE allows export "if supported". This helper takes the
 * currently loaded page of rows — never the whole dataset, which the server
 * holds and the browser must not try to swallow — and streams it as a
 * download.
 *
 * Injection is handled explicitly: a cell starting with `=`, `+`, `-` or `@`
 * could otherwise execute as a formula in Excel (CSV injection), so every such
 * cell is prefixed to break the formula interpretation.
 */

/** Escape a single CSV cell: quotes doubled, wrapped when needed. */
function escapeCell(value: unknown): string {
  const text = value === null || value === undefined ? '' : String(value);
  // Neutralise CSV formula injection by prefixing a quote-safe character.
  const safe = /^[=+\-@\t\r]/.test(text) ? `'${text}` : text;
  return /[",\n\r]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
}

export interface CsvColumn<T> {
  /** Header text in the output file. */
  header: string;
  /** Row value, resolved from the record. */
  value: (row: T) => unknown;
}

/**
 * Build a CSV document from rows.
 *
 * Columns are explicit rather than derived from object keys, so the export
 * matches what the operator sees in the grid instead of leaking internal
 * field names or nested objects.
 */
export function toCsv<T>(rows: T[], columns: CsvColumn<T>[]): string {
  const header = columns.map((c) => escapeCell(c.header)).join(',');
  const body = rows.map((row) => columns.map((c) => escapeCell(c.value(row))).join(','));
  // CRLF and a BOM so Excel opens the file with the correct encoding.
  return `\uFEFF${[header, ...body].join('\r\n')}`;
}

/**
 * Trigger a browser download of `filename` containing `csv`.
 * Returns true when a download was started.
 */
export function downloadCsv(filename: string, csv: string): boolean {
  if (typeof window === 'undefined') return false;
  try {
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    return true;
  } catch {
    return false;
  }
}
