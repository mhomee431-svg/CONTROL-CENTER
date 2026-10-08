'use client';

import { useCallback, useState } from 'react';

/**
 * Column-visibility preferences, persisted per grid.
 *
 * The DATA GRID RULE gives the grid column visibility; remembering the
 * operator's choices across visits is what makes that more than a one-off
 * toggle. Only a UI preference is stored — never any platform data.
 *
 * Storage is best-effort: private mode or a full quota degrades to per-session
 * state rather than breaking the grid.
 */

const STORAGE_KEY = 'admin_grid_preferences_v1';

/** MUI X's column visibility model: field name -> visible? */
export type ColumnVisibilityModel = Record<string, boolean>;

interface StoredPrefs {
  [gridId: string]: ColumnVisibilityModel;
}

function readPrefs(): StoredPrefs {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? (JSON.parse(raw) as StoredPrefs) : {};
  } catch {
    return {};
  }
}

function writePrefs(prefs: StoredPrefs): void {
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs));
  } catch {
    // Storage unavailable (private mode / quota) — preferences simply don't
    // persist, which is acceptable for a UI preference.
  }
}

/**
 * Grid-scoped column-visibility state.
 *
 * Holds the model in React state (so the grid responds immediately) and mirrors
 * it into storage under `gridId` when one is provided. Pass no `gridId` and you
 * get ephemeral state that is never written anywhere — right for the throwaway
 * tabs inside a detail page.
 */
export function useGridPreferences(gridId?: string) {
  const [columnVisibility, setModel] = useState<ColumnVisibilityModel>(() =>
    gridId ? readPrefs()[gridId] ?? {} : {}
  );

  const setColumnVisibility = useCallback(
    (model: ColumnVisibilityModel) => {
      setModel(model);
      if (!gridId) return;
      const prefs = readPrefs();
      prefs[gridId] = model;
      writePrefs(prefs);
    },
    [gridId]
  );

  return { columnVisibility, setColumnVisibility };
}
