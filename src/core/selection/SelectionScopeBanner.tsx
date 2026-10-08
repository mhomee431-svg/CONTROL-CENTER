'use client';

import React from 'react';
import { Alert, Box, Button, Typography } from '@mui/material';
import { AlertTriangle, X } from 'lucide-react';

/**
 * DATA GRID SELECTION — the scope banner.
 *
 * The rule: never accidentally operate on all records when the user selected
 * only visible records, and never the reverse. This banner is the one place
 * that states, in words, exactly what a bulk action will hit before it is
 * allowed to run.
 *
 * Three states, each unambiguous:
 *   - explicit   -> "N selected records" (even if some are on other pages)
 *   - all-matching -> "ALL n records matching the current query" + the page
 *                     count, so the scale of the intent is visible
 *   - off-screen  -> a warning that the selection is not on this page, which is
 *                     the classic server-pagination trap
 */

export interface SelectionScopeBannerProps {
  mode: 'none' | 'page' | 'explicit' | 'all-matching';
  /** Explicitly checked rows (may span pages). */
  count: number;
  /** Rows matching the query — set for `all-matching`. */
  matchingCount: number | null;
  /** Rows on the page the user is actually looking at. */
  pageRowCount: number;
  /** Explicitly selected rows that are not on the current page. */
  offPageCount: number;
  onClear: () => void;
  /** Optional slot: the bulk action buttons themselves. */
  actions?: React.ReactNode;
}

export function SelectionScopeBanner({
  mode,
  count,
  matchingCount,
  pageRowCount,
  offPageCount,
  onClear,
  actions,
}: SelectionScopeBannerProps) {
  if (mode === 'none') return null;

  const isAllMatching = mode === 'all-matching';
  const offScreen = !isAllMatching && offPageCount > 0;

  return (
    <Alert
      severity={offScreen ? 'warning' : 'info'}
      icon={offScreen ? <AlertTriangle size={18} /> : undefined}
      sx={{ mb: 2 }}
      action={
        <Button
          color="inherit"
          size="small"
          startIcon={<X size={14} />}
          onClick={onClear}
          aria-label="Clear selection"
        >
          Clear
        </Button>
      }
    >
      <Box>
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {isAllMatching
            ? `Bulk actions will apply to ALL ${(
              matchingCount ?? 0
            ).toLocaleString()} records matching the current query — not just the ${pageRowCount.toLocaleString()} on this page.`
            : `Bulk actions will apply to ${count.toLocaleString()} selected record${count === 1 ? '' : 's'
            }.`}
        </Typography>
        {offScreen && (
          <Typography variant="caption" sx={{ display: 'block', mt: 0.5 }}>
            {offPageCount.toLocaleString()} of the selected records are not on this page. Verify the
            scope before continuing, or clear the selection.
          </Typography>
        )}
        {actions && <Box sx={{ mt: 1 }}>{actions}</Box>}
      </Box>
    </Alert>
  );
}

export default SelectionScopeBanner;
