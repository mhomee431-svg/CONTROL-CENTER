'use client';

import React from 'react';
import {
  Box,
  Button,
  ButtonGroup,
  Chip,
  Paper,
  Stack,
  TextField,
  Typography,
} from '@mui/material';
import { CalendarRange } from 'lucide-react';
import { useDateRange } from './DateRangeContext';
import { DATE_RANGE_PRESETS, DateRangePreset } from './dateRange';

export interface DateRangePickerProps {
  /** Renders as a bordered card. Set false when nesting inside another card. */
  elevated?: boolean;
}

/**
 * The single date-range control for the whole control center.
 *
 * Every preset (Today, Yesterday, 7/30/90 Days) and the custom range picker
 * are defined once in `core/filters/dateRange.ts`; this component only renders
 * them. It is mounted on the dashboard and on every analytics surface, so no
 * screen can drift into its own hardcoded range options.
 */
export function DateRangePicker({ elevated = true }: DateRangePickerProps) {
  const {
    preset,
    setPreset,
    label,
    days,
    customDraft,
    setCustomRange,
    resetCustomDraft,
    isCustomValid,
  } = useDateRange();

  const body = (
    <>
      <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 1 }}>
        <CalendarRange size={16} aria-hidden />
        <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
          Date Range
        </Typography>
        <Chip size="small" variant="outlined" label={`${days} day window`} />
      </Stack>

      <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap alignItems="center">
        <ButtonGroup size="small" variant="outlined">
          {DATE_RANGE_PRESETS.filter((p) => p.value !== 'custom').map((p) => (
            <Button
              key={p.value}
              variant={preset === p.value ? 'contained' : 'outlined'}
              onClick={() => setPreset(p.value as DateRangePreset)}
              aria-pressed={preset === p.value}
            >
              {p.label}
            </Button>
          ))}
          <Button
            variant={preset === 'custom' ? 'contained' : 'outlined'}
            onClick={() => setPreset('custom')}
            aria-pressed={preset === 'custom'}
          >
            Custom Range
          </Button>
        </ButtonGroup>

        <Typography variant="caption" color="text.secondary" sx={{ ml: 1 }}>
          {label}
        </Typography>
      </Stack>

      {preset === 'custom' && (
        <Stack
          direction="row"
          spacing={1.5}
          sx={{ mt: 1.5 }}
          alignItems="center"
          flexWrap="wrap"
          useFlexGap
        >
          <TextField
            type="date"
            size="small"
            label="From"
            value={customDraft.start}
            onChange={(e) => setCustomRange(e.target.value, customDraft.end)}
            InputLabelProps={{ shrink: true }}
            slotProps={{
              htmlInput: {
                'aria-label': 'Custom range start date',
                max: customDraft.end,
              },
            }}
          />
          <TextField
            type="date"
            size="small"
            label="To"
            value={customDraft.end}
            onChange={(e) => setCustomRange(customDraft.start, e.target.value)}
            InputLabelProps={{ shrink: true }}
            slotProps={{
              htmlInput: {
                'aria-label': 'Custom range end date',
                min: customDraft.start,
              },
            }}
          />
          <Button size="small" onClick={resetCustomDraft}>
            Reset to last 30 days
          </Button>
          <Chip
            size="small"
            label={isCustomValid ? 'Valid range' : 'Invalid range'}
            color={isCustomValid ? 'success' : 'error'}
            variant="outlined"
          />
        </Stack>
      )}
    </>
  );

  if (!elevated) return <Box sx={{ mb: 2 }}>{body}</Box>;

  return (
    <Paper sx={{ p: 2, mb: 2, border: '1px solid #E2E8F0', borderRadius: 2 }}>{body}</Paper>
  );
}

export default DateRangePicker;