import { describe, it, expect } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import React from 'react';
import { useServerSelection } from './useServerSelection';
import type { GridRowSelectionModel } from '@mui/x-data-grid';

/**
 * DATA GRID SELECTION — the safety contract.
 *
 * The one unforgivable failure is acting on records the operator did not know
 * they were targeting. These tests pin the separation between "checked these
 * rows" and "act on everything matching", and the off-screen warning.
 */

/** Harness exposing the hook's live state and actions as plain values. */
function useHarness() {
  const selection = useServerSelection();
  return {
    scope: selection.scope,
    allMatching: selection.allMatching,
    selectedCount: selection.selectedIds.length,
    scopeLabel: selection.scopeLabel,
    offPageCount: selection.offPageCount,
    hasInvisibleSelection: selection.hasInvisibleSelection,
    toggleRow: selection.toggleRow,
    selectAllMatching: selection.selectAllMatching,
    bindQuery: selection.bindQuery,
    syncPageRows: selection.syncPageRows,
    clear: selection.clear,
  };
}

function renderHarness(): {
  current: ReturnType<typeof useHarness>;
  rerender: () => void;
} {
  const ref = { current: undefined as unknown as ReturnType<typeof useHarness> };
  function Probe() {
    ref.current = useHarness();
    return null;
  }
  const view = render(<Probe />);
  return {
    get current() {
      return ref.current as unknown as ReturnType<typeof useHarness>;
    },
    rerender: () => view.rerender(<Probe />),
  };
}
describe('useServerSelection', () => {
  it('starts with nothing selected and no intent', () => {
    const h = renderHarness();
    expect(h.current.scope.mode).toBe('none');
    expect(h.current.selectedCount).toBe(0);
    expect(h.current.allMatching).toBe(false);
  });

  it('tracks explicit row checks as an explicit scope', () => {
    const h = renderHarness();
    const ids: GridRowSelectionModel = [1, 2, 3];
    act(() => h.current.toggleRow(ids));
    expect(h.current.scope).toEqual({ mode: 'explicit', count: 3, matchingCount: null });
    expect(h.current.scopeLabel).toBe('3 selected records');
  });

  it('distinguishes selecting the current page from selecting explicit records', () => {
    const h = renderHarness();
    act(() => h.current.syncPageRows([1, 2, 3]));
    act(() => h.current.toggleRow([1, 2, 3]));
    expect(h.current.scope.mode).toBe('page');
  });

  it('clears stale all-matching counts when switching back to explicit selection', () => {
    const h = renderHarness();
    act(() => h.current.selectAllMatching(5000));
    act(() => h.current.toggleRow([7]));
    expect(h.current.scope).toEqual({ mode: 'explicit', count: 1, matchingCount: null });
  });

  it('tracks select-all-matching as intent, never as an id list', () => {
    const h = renderHarness();
    act(() => h.current.selectAllMatching(5000));
    // The intent is recorded with its scale...
    expect(h.current.allMatching).toBe(true);
    expect(h.current.scope.mode).toBe('all-matching');
    expect(h.current.scope.matchingCount).toBe(5000);
    // ...but NO id list is materialized (TABLE RULE: the server decides what
    // "all matching" resolves to).
    expect(h.current.selectedCount).toBe(0);
    expect(h.current.scopeLabel).toContain('ALL 5,000 records');
  });

  it('selecting rows after an all-matching intent reverts to explicit scope', () => {
    const h = renderHarness();
    act(() => h.current.selectAllMatching(5000));
    act(() => h.current.toggleRow([7]));
    expect(h.current.allMatching).toBe(false);
    expect(h.current.scope.mode).toBe('explicit');
  });

  it('clears selection when the filter/search query changes', () => {
    const h = renderHarness();
    act(() => h.current.bindQuery('search=soap'));
    act(() => h.current.selectAllMatching(17));
    act(() => h.current.bindQuery('search=milk'));
    expect(h.current.scope.mode).toBe('none');
    expect(h.current.allMatching).toBe(false);
  });

  it('clear resets every form of selection', () => {
    const h = renderHarness();
    act(() => h.current.selectAllMatching(5000));
    act(() => h.current.clear());
    expect(h.current.scope.mode).toBe('none');
    expect(h.current.allMatching).toBe(false);
  });

  it('warns when the whole selection is off the visible page', () => {
    // The server-pagination trap: rows checked on page 1, operator now on page 2.
    const h = renderHarness();
    act(() => h.current.toggleRow([1, 2]));
    expect(h.current.hasInvisibleSelection).toBe(false);

    act(() => h.current.syncPageRows([3, 4]));
    expect(h.current.offPageCount).toBe(2);
    expect(h.current.hasInvisibleSelection).toBe(true);
  });

  it('does not warn when the selection is (at least partly) on screen', () => {
    const h = renderHarness();
    act(() => h.current.toggleRow([1, 2, 3]));
    act(() => h.current.syncPageRows([2, 3, 4]));
    // One selected row is visible, so the operator can see what they hit.
    expect(h.current.hasInvisibleSelection).toBe(false);
    expect(h.current.offPageCount).toBe(1);
  });

  it('syncPageRows is called per page and stays consistent across pages', () => {
    const h = renderHarness();
    act(() => h.current.toggleRow([10, 11]));
    // Move to a page where none of the selection lives...
    act(() => h.current.syncPageRows([20, 21]));
    expect(h.current.hasInvisibleSelection).toBe(true);
    // ...and back to where it does.
    act(() => h.current.syncPageRows([10, 11]));
    expect(h.current.hasInvisibleSelection).toBe(false);
    expect(h.current.offPageCount).toBe(0);
  });
});
