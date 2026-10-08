import { describe, it, expect } from 'vitest';
import { toCsv, downloadCsv, CsvColumn } from './csv';

describe('toCsv', () => {
  const columns: CsvColumn<{ id: number; name: string; note?: string }>[] = [
    { header: 'ID', value: (r) => r.id },
    { header: 'Name', value: (r) => r.name },
    { header: 'Note', value: (r) => r.note ?? '' },
  ];

  it('emits a header row plus one row per record', () => {
    const csv = toCsv(
      [
        { id: 1, name: 'Rice' },
        { id: 2, name: 'Milk' },
      ],
      columns
    );
    const lines = csv.replace(/^\uFEFF/, '').split('\r\n');
    expect(lines[0]).toBe('ID,Name,Note');
    expect(lines[1]).toBe('1,Rice,');
    expect(lines[2]).toBe('2,Milk,');
  });

  it('escapes values containing commas and quotes', () => {
    const csv = toCsv([{ id: 1, name: 'Oil, "5L"' }], columns);
    const lines = csv.replace(/^\uFEFF/, '').split('\r\n');
    // The comma-containing cell is wrapped, and the inner quotes doubled.
    expect(lines[1]).toBe('1,"Oil, ""5L""",');
  });

  it('neutralises CSV formula injection', () => {
    // A cell starting with a formula character could execute in Excel.
    const csv = toCsv([{ id: 1, name: '=SUM(A1:A2)', note: '@cmd' }], columns);
    const lines = csv.replace(/^\uFEFF/, '').split('\r\n');
    expect(lines[1]).toContain("'=SUM(A1:A2)");
    expect(lines[1]).toContain("'@cmd");
  });

  it('renders null and undefined as empty cells', () => {
    const csv = toCsv([{ id: 1, name: null as unknown as string }], columns);
    const lines = csv.replace(/^\uFEFF/, '').split('\r\n');
    expect(lines[1]).toBe('1,,');
  });

  it('produces only a header row for an empty dataset', () => {
    const csv = toCsv([], columns);
    const lines = csv.replace(/^\uFEFF/, '').split('\r\n');
    expect(lines).toHaveLength(1);
    expect(lines[0]).toBe('ID,Name,Note');
  });
});

describe('downloadCsv', () => {
  it('starts a download without throwing in the browser environment', () => {
    // jsdom simulates the anchor download; the helper must complete the flow
    // (create object URL, click, revoke) without throwing either way.
    expect(() => downloadCsv('x.csv', 'a,b')).not.toThrow();
    expect(downloadCsv('x.csv', 'a,b')).toBe(true);
  });
});
