'use client';

import React, { useMemo } from 'react';
import {
  Box,
  Button,
  FormControl,
  InputLabel,
  MenuItem,
  Select,
  Chip,
  Stack,
  Typography,
  CircularProgress,
  Tooltip,
} from '@mui/material';
import { SlidersHorizontal, RotateCcw } from 'lucide-react';
import {
  DASHBOARD_FILTERS,
  DashboardFilterState,
  DashboardFilterKey,
  SelectOption,
  toFilterParams,
  countActiveFilters,
} from '@/core/filters/dashboardFilters';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';
import { DATE_RANGE_PARAM } from '@/core/filters/dashboardFilters';

export interface DashboardFiltersProps {
  filters: DashboardFilterState;
  onChange: (filters: DashboardFilterState) => void;
  /** Option lists for dynamic filters, keyed by filter key. */
  dynamicOptions?: Partial<Record<DashboardFilterKey, SelectOption[]>>;
  dynamicOptionsLoading?: boolean;
  disabled?: boolean;
}

/**
 * Renders only the filters declared in the backend contract registry.
 * Static enums come from the registry; taxonomy/geography lists are supplied
 * by the caller after being fetched from the backend.
 */
export function DashboardFilters({
  filters,
  onChange,
  dynamicOptions = {},
  dynamicOptionsLoading = false,
  disabled = false,
}: DashboardFiltersProps) {
  const activeCount = useMemo(() => countActiveFilters(filters), [filters]);
  const hasAnyFilter = activeCount > 0;

  // Date range lives in shared context so every analytics surface agrees.
  // Only the serialized params are needed here — the control itself renders
  // via <DateRangePicker />.
  const { params: dateParams } = useDateRange();

  // Reflect the shared window in the serialized filter state so the query
  // preview and the request both include it.
  const effectiveFilters: DashboardFilterState = { ...filters };
  if (dateParams[DATE_RANGE_PARAM]) {
    effectiveFilters.date_range = dateParams[DATE_RANGE_PARAM];
  }

  const setValue = (key: DashboardFilterKey, value: string) => {
    const next: DashboardFilterState = { ...filters };
    if (!value) {
      delete next[key];
    } else {
      next[key] = value;
    }
    onChange(next);
  };

  return (
    <Box
      component="section"
      aria-label="Dashboard filters"
      sx={{
        p: 2,
        mb: 3,
        backgroundColor: '#fff',
        borderRadius: 2,
        border: '1px solid #E2E8F0',
      }}
    >
      <Stack
        direction={{ xs: 'column', sm: 'row' }}
        spacing={1.5}
        alignItems={{ xs: 'stretch', sm: 'center' }}
        sx={{ mb: activeCount > 0 ? 2 : 0 }}
      >
        <Stack direction="row" spacing={1} alignItems="center">
          <SlidersHorizontal size={18} aria-hidden />
          <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
            Filters
          </Typography>
          {activeCount > 0 && (
            <Chip size="small" color="primary" label={`${activeCount} active`} />
          )}
        </Stack>
        <Box sx={{ flex: 1 }} />
        <Tooltip title="Clear all filters">
          <span>
            <Button
              size="small"
              variant="outlined"
              disabled={!hasAnyFilter || disabled}
              onClick={() => onChange({})}
              startIcon={<RotateCcw size={16} />}
            >
              Reset
            </Button>
          </span>
        </Tooltip>
      </Stack>

      <Box
              sx={{
                display: 'grid',
                gridTemplateColumns: {
                  xs: '1fr',
                  sm: 'repeat(2, 1fr)',
                  lg: 'repeat(3, 1fr)',
                  xl: 'repeat(6, 1fr)',
                },
                gap: 1.5,
              }}
            >
              {DASHBOARD_FILTERS.map((def) => {
                // The date-range control is rendered by the shared provider so its
                // presets and custom picker exist in exactly one component.
                if (def.key === 'date_range') return null;

                const options: SelectOption[] = def.options ?? dynamicOptions[def.key] ?? [];
          const value = filters[def.key] ?? '';
          const isLoading = Boolean(def.dynamicOptions) && dynamicOptionsLoading;
          const disabledForFilter = disabled || (Boolean(def.dynamicOptions) && options.length === 0);

          return (
            <FormControl key={def.key} fullWidth size="small" disabled={disabledForFilter}>
              <InputLabel id={`filter-${def.key}-label`}>{def.label}</InputLabel>
              <Select
                labelId={`filter-${def.key}-label`}
                id={`filter-${def.key}`}
                label={def.label}
                value={value}
                onChange={(e) => setValue(def.key, String(e.target.value))}
                inputProps={{ 'aria-label': def.label }}
              >
                <MenuItem value="">
                  <em>All</em>
                </MenuItem>
                {isLoading ? (
                  <MenuItem disabled>
                    <CircularProgress size={14} />
                  </MenuItem>
                ) : (
                  options.map((opt) => (
                    <MenuItem key={opt.value} value={opt.value}>
                      {opt.label}
                    </MenuItem>
                  ))
                )}
              </Select>
            </FormControl>
          );
        })}
      </Box>

      {/* Centralized date range. The control itself lives in
          core/filters/DateRangePicker.tsx and is shared with every analytics
          surface, so presets can never drift between components. */}
      <Box sx={{ mt: 2 }}>
        <DateRangePicker elevated={false} />
      </Box>

      {hasAnyFilter && (
        <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap sx={{ mt: 2 }}>
          {DASHBOARD_FILTERS.filter((def) => effectiveFilters[def.key]).map((def) => (
            <Chip
              key={def.key}
              size="small"
              variant="outlined"
              label={`${def.label}: ${effectiveFilters[def.key]}`}
              onDelete={() => setValue(def.key, '')}
              aria-label={`Remove ${def.label} filter`}
            />
          ))}
        </Stack>
      )}

      {/* Exposes exactly what will be sent to the backend — useful for operators
          verifying filter support, and keeps the contract auditable. */}
      <Typography
        variant="caption"
        color="text.secondary"
        sx={{ display: 'block', mt: 1.5, fontFamily: 'monospace' }}
      >
        query: {JSON.stringify(toFilterParams(effectiveFilters))}
      </Typography>
    </Box>
  );
}

export default DashboardFilters;