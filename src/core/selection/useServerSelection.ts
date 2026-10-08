'use client';

import { useCallback, useMemo, useRef, useState } from 'react';
import { GridRowSelectionModel } from '@mui/x-data-grid';

/**
 * DATA GRID SELECTION — server-safe selection state.
 *
 * With server pagination the grid holds only one page. That creates the most
 * dangerous failure mode a bulk action can have: the user selects 5 rows, moves
 * to page 2, and the selection is still active — invisible. If the bulk action
 * then fires on "the selection", records the user can no longer see get
 * modified and there is no way to tell from the screen.
 *
 * This hook keeps the two quantities strictly separate and always reportable:
 *   - `selectedIds`     — rows the user explicitly checked, on any page.
 *   - `allMatching`     — an intent ("act on everything this query returns"),
 *                         tracked as a flag, never as a materialized id list.
 *
 * A "select all matching" that copied every id into memory would break the
 * TABLE RULE (thousands/millions of ids in browser memory) and would go stale
 * the moment the underlying query changed. Tracking intent as a flag keeps the
 * server authoritative: the caller sends the same query the grid displays and
 * the backend decides what "all matching" resolves to.
 *
 * The scope is also recomputed whenever the page/sort/filter/search signature
 * changes — an intent formed under one query must not silently survive into
 * another.
 */

export interface ServerSelection {
  /** Explicitly checked row ids, across pages. */
  selectedIds: GridRowSelectionModel;
  /** True when the user's intent is "everything matching the current query". */
  allMatching: boolean;
  /** Number of rows visible in the current page (for scope reporting). */
  pageRowCount: number;
  /** What the current intent actually targets. */
  scope: SelectionScope;
  /** Human-readable scope sentence for a confirmation banner. */
  scopeLabel: string;
  toggleRow: (ids: GridRowSelectionModel) => void;
  toggleAllOnPage: (pageIds: GridRowSelectionModel) => void;
  selectAllMatching: (matchingCount: number) => void;
  clear: () => void;
  /** Report the id set visible on the current page — call on every page load. */
  syncPageRows: (pageIds: unknown[]) => void;
  /** How many of the explicitly selected rows are not on the current page. */
  offPageCount: number;
  /** True when selection state exists but covers no row on the current page. */
  hasInvisibleSelection: boolean;
}

export interface SelectionScope {
  mode: 'none' | 'page' | 'explicit' | 'all-matching';
  /** Rows explicitly checked (may span pages). */
  count: number;
  /** Total rows matching the query — only meaningful for `all-matching`. */
  matchingCount: number | null;
}

/**
 * Tracks which explicit ids belong to the current page so the hook can report
 * when a selection exists entirely off-screen.
 */
export function useServerSelection(): ServerSelection {
  const [selectedIds, setSelectedIds] = useState<GridRowSelectionModel>([]);
  const [allMatching, setAllMatching] = useState(false);
  const [matchingCount, setMatchingCount] = useState<number | null>(null);
  const [pageRowCount, setPageRowCount] = useState(0);
  // Ids of the selection that are NOT on the currently displayed page.
  const [offPageIds, setOffPageIds] = useState<Set<unknown>>(new Set());
  // Mirror of selectedIds so syncPageRows can recompute against the latest
  // selection even when both change in the same batch of updates.
  const selectedIdsRef = useRef<GridRowSelectionModel>([]);

  /**
   * Called by the grid with the ids actually rendered. Recomputes how much of
   * the selection is off-screen from the *current selection* — not from the
   * previous off-page set, which a selection change may just have replaced.
   */
  const syncPageRows = useCallback((pageIds: unknown[]) => {
    setPageRowCount(pageIds.length);
    const visible = new Set(pageIds);
    setOffPageIds(new Set(selectedIdsRef.current.filter((id) => !visible.has(id))));
  }, []);

  const toggleRow = useCallback((ids: GridRowSelectionModel) => {
    setAllMatching(false);
    selectedIdsRef.current = ids;
    setSelectedIds(ids);
  }, []);

  const toggleAllOnPage = useCallback((pageIds: GridRowSelectionModel) => {
    setAllMatching(false);
    selectedIdsRef.current = pageIds;
    setSelectedIds(pageIds);
  }, []);

  const selectAllMatching = useCallback((count: number) => {
    // Intent only — no id list is materialized (TABLE RULE).
    setAllMatching(true);
    setMatchingCount(count);
    selectedIdsRef.current = [];
    setSelectedIds([]);
  }, []);

  const clear = useCallback(() => {
    selectedIdsRef.current = [];
    setSelectedIds([]);
    setAllMatching(false);
    setMatchingCount(null);
    setOffPageIds(new Set());
  }, []);

  const scope: SelectionScope = useMemo(
    () =>
      allMatching
        ? { mode: 'all-matching', count: matchingCount ?? 0, matchingCount }
        : { mode: selectedIds.length > 0 ? 'explicit' : 'none', count: selectedIds.length, matchingCount: null },
    [allMatching, matchingCount, selectedIds.length]
  );

  const scopeLabel = useMemo(() => {
    if (scope.mode === 'all-matching') {
      const n = scope.matchingCount ?? 0;
      return `ALL ${n.toLocaleString()} records matching the current query`;
    }
    if (scope.mode === 'explicit') return `${scope.count} selected records`;
    return 'no records selected';
  }, [scope]);

  return {
    selectedIds,
    allMatching,
    pageRowCount,
    scope,
    scopeLabel,
    toggleRow,
    toggleAllOnPage,
    selectAllMatching,
    clear,
    syncPageRows,
    // Warning state: something is selected and none of it is visible here.
    hasInvisibleSelection: selectedIds.length > 0 && offPageIds.size === selectedIds.length,
    offPageCount: offPageIds.size,
  };
}
