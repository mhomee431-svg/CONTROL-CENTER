'use client';

import React, {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
} from 'react';
import {
  DateRange,
  DateRangePreset,
  DEFAULT_DATE_RANGE_PRESET,
  IsoDate,
  defaultCustomDraft,
  describeRange,
  isSameRange,
  isValidCustomRange,
  normalizeRange,
  resolvePreset,
  toDateParams,
} from './dateRange';

/**
 * Shared analytics date-range state.
 *
 * Centralizing this is what stops each component from hardcoding its own
 * "7 / 30 / 90" options and date arithmetic: pages consume the resolved range
 * and its backend params from context, so changing the window in one place
 * keeps every analytics surface consistent.
 */
interface DateRangeContextValue {
  range: DateRange;
  preset: DateRangePreset;
  /** Inclusive span in days — the backend's `days` parameter. */
  days: number;
  /** Ready-to-spread backend query params. */
  params: Record<string, string>;
  label: string;
  /** Draft dates while the operator is editing a custom range. */
  customDraft: { start: IsoDate; end: IsoDate };
  setPreset: (preset: DateRangePreset) => void;
  setCustomRange: (start: IsoDate, end: IsoDate) => boolean;
  resetCustomDraft: () => void;
  isCustomValid: boolean;
}

const DateRangeContext = createContext<DateRangeContextValue | undefined>(undefined);

export const DateRangeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [preset, setPresetState] = useState<DateRangePreset>(DEFAULT_DATE_RANGE_PRESET);
  const [customStart, setCustomStart] = useState<IsoDate>(() => defaultCustomDraft().start);
  const [customEnd, setCustomEnd] = useState<IsoDate>(() => defaultCustomDraft().end);

  const customDraft = useMemo(() => ({ start: customStart, end: customEnd }), [customStart, customEnd]);

  const range = useMemo(
    () => resolvePreset(preset, { start: customStart, end: customEnd }),
    [preset, customStart, customEnd]
  );

  const params = useMemo(() => toDateParams(range), [range]);

  const setPreset = useCallback((next: DateRangePreset) => {
    // Selecting "Custom" seeds the draft from the trailing 30 days so the
    // operator starts from a sensible, valid window.
    if (next === 'custom') {
      const draft = defaultCustomDraft();
      setCustomStart(draft.start);
      setCustomEnd(draft.end);
    }
    setPresetState(next);
  }, []);

  const setCustomRange = useCallback(
    (start: IsoDate, end: IsoDate) => {
      setCustomStart(start);
      setCustomEnd(end);
      setPresetState('custom');
      return isValidCustomRange(start, end);
    },
    []
  );

  const resetCustomDraft = useCallback(() => {
    const draft = defaultCustomDraft();
    setCustomStart(draft.start);
    setCustomEnd(draft.end);
  }, []);

  const value = useMemo<DateRangeContextValue>(
    () => ({
      range,
      preset,
      days: params.days ? Number(params.days) : 0,
      params,
      label: describeRange(range),
      customDraft,
      setPreset,
      setCustomRange,
      resetCustomDraft,
      isCustomValid: isValidCustomRange(customStart, customEnd),
    }),
    [range, preset, params, customStart, customEnd, customDraft, setPreset, setCustomRange, resetCustomDraft]
  );

  return <DateRangeContext.Provider value={value}>{children}</DateRangeContext.Provider>;
};

export function useDateRange(): DateRangeContextValue {
  const ctx = useContext(DateRangeContext);
  if (!ctx) {
    throw new Error('useDateRange must be used within a DateRangeProvider');
  }
  return ctx;
}

/** Convenience selector for consumers that only need backend params. */
export function useDateRangeParams(): Record<string, string> {
  return useDateRange().params;
}

/** Re-exported so callers need a single import for comparisons. */
export { isSameRange, normalizeRange };