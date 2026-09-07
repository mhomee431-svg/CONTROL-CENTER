"""Shared SQLite-compatibility helpers for tests that materialise PostGIS
Geography columns on a plain SQLite engine.

Several phase test-files *previously* duplicated a ``_strip_geo_columns()``
that mutated the process-global ``Base.metadata`` in place (Geography -> Text)
so ``create_all`` works on SQLite. Because that metadata is shared across every
test module in the same interpreter, a mutation introduced **order-dependent
failures**: ``test_search_geo::test_search_index_model_has_geo`` asserts the
production ``SearchIndex.location`` is a PostGIS ``Geography`` column, but it
failed whenever an earlier-imported module had already stripped it to ``Text``.

This module makes the stripping *idempotent* and *reversible*: it records the
pristine Geography types in a registry keyed by ``(table, column)`` so a test
can inspect the *declared* type without being affected by global mutation.
"""

import sqlalchemy as sa
from geoalchemy2 import Geography

from app.database.session import Base


# (table_name, column_name) -> pristine Geography type instance.
_ORIGINAL_GEO: dict[tuple[str, str], Geography] = {}


def strip_geo_columns() -> None:
    """Replace PostGIS Geography columns with Text for SQLite ``create_all``,
    recording the pristine types for later introspection/restoration."""
    for table in Base.metadata.tables.values():
        has_geo = False
        for col in list(table.columns):
            if isinstance(col.type, Geography):
                # Record only the *first* (pristine) impression so repeated
                # stripping is a no-op for introspection.
                _ORIGINAL_GEO.setdefault((table.name, col.name), col.type)
                col.type = sa.Text()
                col.nullable = True  # test rows may omit spatial data
                has_geo = True
        if has_geo:
            keep = set(table.columns.keys())
            for idx in list(table.indexes):
                idx_cols = {c.name for c in idx.columns}
                if idx_cols & {"location"} or not idx_cols <= keep:
                    table.indexes.discard(idx)


def make_timestamp_defaults_portable() -> None:
    """Replace literal "now()" server defaults / onupdates with Python-side
    callables so SQLite stores real timestamps (mirrors Postgres semantics).

    Shared helper extracted from the per-file pattern used by the SQLite-based
    test modules (admin_phase26 etc.). Idempotent: safe to call multiple times.
    """
    from datetime import datetime as _dt

    from sqlalchemy import ColumnDefault

    def _now(ctx=None):
        return _dt.utcnow()

    for table in Base.metadata.tables.values():
        for col in table.columns:
            sd = getattr(col, "server_default", None)
            sd_arg = getattr(sd, "arg", None)
            if sd_arg == "now()":
                if col.default is None:
                    col.default = ColumnDefault(_now)
                col.server_default = None
            elif isinstance(sd_arg, str) and sd_arg.lower() == "false":
                if col.default is None and (
                    getattr(getattr(col.type, "python_type", None), "__name__", "")
                    == "bool"
                ):
                    col.default = ColumnDefault(False)
                col.server_default = None
            ou = getattr(col, "onupdate", None)
            if ou is not None and getattr(ou, "arg", None) == "now()":
                col.onupdate = ColumnDefault(_now, for_update=True)


def restore_geo_columns() -> None:
    """Restore pristine Geography types for every column stripped so far."""
    for (table_name, col_name), pristine in _ORIGINAL_GEO.items():
        table = Base.metadata.tables.get(table_name)
        if table is None or col_name not in table.columns:
            continue
        table.columns[col_name].type = pristine


def declared_type(table_name: str, col_name: str):
    """Return the *declared* (pristine) type for a column.

    Falls back to the current (possibly stripped) type when the column was
    never a Geography column. This is deterministic regardless of whether any
    other test module has already called :func:`strip_geo_columns`.
    """
    pristine = _ORIGINAL_GEO.get((table_name, col_name))
    if pristine is not None:
        return pristine
    table = Base.metadata.tables.get(table_name)
    if table is not None and col_name in table.columns:
        return table.columns[col_name].type
    return None