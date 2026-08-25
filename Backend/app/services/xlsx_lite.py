"""Pure-stdlib XLSX (.xlsx) reader/writer — Phase 24 Excel inventory intake.

Deliberately dependency-free (openpyxl is NOT a project requirement), this
module supports the subset of OOXML produced by Excel, Google Sheets,
LibreOffice and openpyxl:

  - multiple sheets (first sheet by default)
  - shared strings, inline strings, plain/numeric/boolean cells
  - sparse rows (missing cells become ``None``)
  - cell references (``r="C4"``) as well as positional cells

The writer produces a minimal valid workbook using inline strings, which is
used for fixtures, downloadable templates and round-trip tests.
"""

from __future__ import annotations

import io
import re
import zipfile
from typing import Any, Sequence
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

_MAIN_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_OFFICE_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"

_CELL_REF_RE = re.compile(r"^([A-Za-z]+)(\d+)$")

SUPPORTED_EXTENSION = ".xlsx"


class UnsupportedFileError(ValueError):
    """Raised when the uploaded bytes are not a readable .xlsx workbook."""


# ── Column helpers ────────────────────────────────────────────────────────


def _column_index(letters: str) -> int:
    """'A' → 0, 'Z' → 25, 'AA' → 26 ..."""
    index = 0
    for ch in letters.upper():
        index = index * 26 + (ord(ch) - ord("A") + 1)
    return index - 1


def _column_letter(index: int) -> str:
    """0 → 'A', 25 → 'Z', 26 → 'AA' ..."""
    letters = ""
    index += 1
    while index:
        index, remainder = divmod(index - 1, 26)
        letters = chr(ord("A") + remainder) + letters
    return letters


# ── Reading ───────────────────────────────────────────────────────────────


def _sheet_target(zf: zipfile.ZipFile, sheet_index: int) -> str:
    """Resolve a sheet index to its worksheet XML part path."""
    try:
        workbook = ET.fromstring(zf.read("xl/workbook.xml"))
    except KeyError as exc:  # not a valid xlsx package
        raise UnsupportedFileError("Missing xl/workbook.xml") from exc
    sheets = workbook.find(f"{_MAIN_NS}sheets")
    if sheets is None or len(list(sheets)) == 0:
        raise UnsupportedFileError("Workbook contains no sheets")
    if sheet_index < 0 or sheet_index >= len(list(sheets)):
        raise UnsupportedFileError(f"Sheet index {sheet_index} out of range")

    sheet_el = list(sheets)[sheet_index]
    rid = sheet_el.get(f"{_OFFICE_REL}id", "")

    target = ""
    if "xl/_rels/workbook.xml.rels" in zf.namelist():
        rels = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
        for rel in rels:
            if rel.get("Id") == rid:
                target = rel.get("Target", "")
                break

    target = target.lstrip("/")
    if target.startswith("xl/"):
        return target
    return f"xl/{target}"


def _cell_value(cell_el: ET.Element, shared: list[str]) -> Any:
    """Extract a python value from one ``<c>`` element."""
    cell_type = cell_el.get("t", "n")

    if cell_type == "inlineStr":
        is_el = cell_el.find(f"{_MAIN_NS}is")
        if is_el is not None:
            return "".join(t.text or "" for t in is_el.iter(f"{_MAIN_NS}t"))
        return None

    v_el = cell_el.find(f"{_MAIN_NS}v")
    if v_el is None or v_el.text is None:
        return None
    raw = v_el.text

    if cell_type == "s":  # shared string index
        try:
            return shared[int(raw)]
        except (IndexError, ValueError):
            return None
    if cell_type == "b":  # boolean
        return True if raw.strip() == "1" else False
    if cell_type == "e":  # error cell (#DIV/0!, #N/A ...)
        return None
    # "n" (number) and "str" (formula cached string) come through as-is;
    # numeric normalization happens in the import validator layer.
    return raw


def read_workbook(data: bytes, sheet_index: int = 0) -> list[list[Any]]:
    """Read an .xlsx byte stream into a list-of-lists grid (first sheet).

    Raises :class:`UnsupportedFileError` when the bytes are not a valid
    xlsx package (bad magic, truncated zip, missing parts).
    """
    if not data:
        raise UnsupportedFileError("Empty file")
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise UnsupportedFileError("File is not a valid .xlsx (zip) archive") from exc

    try:
        shared: list[str] = []
        if "xl/sharedStrings.xml" in zf.namelist():
            sst = ET.fromstring(zf.read("xl/sharedStrings.xml"))
            for si in sst.findall(f"{_MAIN_NS}si"):
                shared.append("".join(t.text or "" for t in si.iter(f"{_MAIN_NS}t")))

        sheet_path = _sheet_target(zf, sheet_index)
        if sheet_path not in zf.namelist():
            raise UnsupportedFileError(f"Worksheet part '{sheet_path}' missing")
        worksheet = ET.fromstring(zf.read(sheet_path))
    except UnsupportedFileError:
        raise
    except Exception as exc:  # malformed XML anywhere
        raise UnsupportedFileError("Malformed worksheet XML") from exc
    finally:
        zf.close()

    rows_out: list[list[Any]] = []
    for row_el in worksheet.iter(f"{_MAIN_NS}row"):
        cells: dict[int, Any] = {}
        max_col = -1
        for c_el in row_el.findall(f"{_MAIN_NS}c"):
            ref = c_el.get("r") or ""
            match = _CELL_REF_RE.match(ref)
            col = _column_index(match.group(1)) if match else max_col + 1
            cells[col] = _cell_value(c_el, shared)
            max_col = max(max_col, col)
        rows_out.append([cells.get(i) for i in range(max_col + 1)])
    return rows_out


# ── Writing (fixtures / downloadable templates) ───────────────────────────


def _sheet_xml(rows: Sequence[Sequence[Any]]) -> str:
    lines = [
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
        f'<worksheet xmlns="{_MAIN_NS[1:-1]}"><sheetData>',
    ]
    for r_idx, row in enumerate(rows, start=1):
        lines.append(f'<row r="{r_idx}">')
        for c_idx, value in enumerate(row):
            ref = f"{_column_letter(c_idx)}{r_idx}"
            if value is None:
                continue
            if isinstance(value, bool):
                lines.append(f'<c r="{ref}" t="b"><v>{1 if value else 0}</v></c>')
            elif isinstance(value, (int, float)):
                lines.append(f'<c r="{ref}"><v>{value}</v></c>')
            else:
                text = escape(str(value))
                lines.append(f'<c r="{ref}" t="inlineStr"><is><t>{text}</t></is></c>')
        lines.append("</row>")
    lines.append("</sheetData></worksheet>")
    return "".join(lines)


_WORKBOOK_XML = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>'
)

_WORKBOOK_RELS_XML = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
    'Target="worksheets/sheet1.xml"/></Relationships>'
)

_ROOT_RELS_XML = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/></Relationships>'
)

_CONTENT_TYPES_XML = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" '
    'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    "</Types>"
)


def write_workbook(rows: Sequence[Sequence[Any]]) -> bytes:
    """Build a minimal valid .xlsx file from a list-of-lists grid."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("[Content_Types].xml", _CONTENT_TYPES_XML)
        zf.writestr("_rels/.rels", _ROOT_RELS_XML)
        zf.writestr("xl/workbook.xml", _WORKBOOK_XML)
        zf.writestr("xl/_rels/workbook.xml.rels", _WORKBOOK_RELS_XML)
        zf.writestr("xl/worksheets/sheet1.xml", _sheet_xml(rows))
    return buffer.getvalue()
