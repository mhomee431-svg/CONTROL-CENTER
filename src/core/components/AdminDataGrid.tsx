'use client';

import React from 'react';
import {
  DataGrid,
  GridColDef,
  GridPaginationModel,
  GridSortModel,
  GridRowSelectionModel,
  GridToolbarContainer,
  GridToolbarColumnsButton,
  GridToolbarFilterButton,
  GridToolbarDensitySelector,
} from '@mui/x-data-grid';
import { Box, Paper, Typography, Button, TextField, InputAdornment, Alert } from '@mui/material';
import { Search as SearchIcon, RefreshCw as RefreshIcon } from 'lucide-react';
import { useGridPreferences } from '@/core/components/gridPreferences';

export interface AdminDataGridProps {
  rows: Record<string, unknown>[];
  columns: GridColDef[];
  totalRows: number;
  paginationModel: GridPaginationModel;
  onPaginationModelChange: (model: GridPaginationModel) => void;
  sortModel?: GridSortModel;
  onSortModelChange?: (model: GridSortModel) => void;
  loading?: boolean;
  searchPlaceholder?: string;
  searchValue?: string;
  onSearchChange?: (val: string) => void;
  onRefresh?: () => void;
  checkboxSelection?: boolean;
  rowSelectionModel?: GridRowSelectionModel;
  onRowSelectionModelChange?: (model: GridRowSelectionModel) => void;
  /**
   * When true the grid is replaced by an explicit failure notice.
   *
   * Without this a failed request renders an empty grid, which an operator
   * reads as "no records" rather than "backend unavailable" — a material
   * difference when deciding whether to escalate.
   */
  error?: boolean;
  /** Message shown when `error` is true. */
  errorMessage?: string;
    bulkActions?: React.ReactNode;
    onRowClick?: (params: { row: Record<string, unknown>; id: unknown }) => void;
  /**
   * Show MUI X's built-in toolbar: column visibility, filter and density
   * controls. Column visibility is the big one for wide registries — it lets an
   * operator hide the columns they do not need instead of scrolling sideways.
   */
  showToolbar?: boolean;
  /**
   * Export the currently loaded page to CSV. Only offered when the caller
   * provides it: the DATA GRID RULE allows export "if supported", and a grid
   * over server-side data must not pretend an export covers the whole dataset
   * when it only holds the current page.
   */
  onExport?: () => void;
  /**
   * Stable key used to remember column visibility per grid across visits.
   * Omit it and preferences are simply not persisted (e.g. ephemeral tabs).
   */
  gridId?: string;
  /**
   * When set, the toolbar gains "Select all matching" — an intent to act on
   * every record the current query returns, not just the visible page. The
   * caller owns what that resolves to server-side; this grid only surfaces the
   * intent and its scale. Omitted for grids without bulk actions.
   */
  totalMatching?: number;
  /** Called when the operator chooses "Select all matching". */
  onSelectAllMatching?: () => void;
  /** True while an all-matching intent is active (drives the banner). */
  allMatchingActive?: boolean;
  }

/**
 * A custom toolbar so the grid owns its column-visibility, filter and density
 * controls in one place, styled to match the control bar above it.
 */
function GridToolbar() {
  return (
    <GridToolbarContainer sx={{ p: 1, gap: 1 }}>
      <GridToolbarColumnsButton />
      <GridToolbarFilterButton />
      <GridToolbarDensitySelector />
    </GridToolbarContainer>
  );
}

/**
 * Section 69: Reusable AdminDataGrid Abstraction
 * Handles large-scale server-side pagination, sorting, search debounce, and row selection.
 */
export const AdminDataGrid: React.FC<AdminDataGridProps> = ({
  rows,
  columns,
  totalRows,
  paginationModel,
  onPaginationModelChange,
  sortModel,
  onSortModelChange,
  loading = false,
  searchPlaceholder = 'Search records...',
  searchValue = '',
  onSearchChange,
  onRefresh,
  checkboxSelection = false,
  rowSelectionModel,
  onRowSelectionModelChange,
      error = false,
      errorMessage = 'This list could not be loaded. The registry is unreachable or returned an error.',
      bulkActions,
      onRowClick,
      showToolbar = false,
      onExport,
      gridId,
      totalMatching,
      onSelectAllMatching,
      allMatchingActive = false,
    }) => {
  // Column visibility is remembered per grid (keyed by `gridId`) so an
  // operator's choices survive a reload. It is a UI preference only — no
  // platform data is ever persisted.
  const { columnVisibility, setColumnVisibility } = useGridPreferences(gridId);

  const exportButton = onExport ? (
    <Button
      size="small"
      variant="outlined"
      onClick={onExport}
      sx={{ borderColor: '#CBD5E1', color: '#475569' }}
    >
      Export CSV
    </Button>
  ) : null;

  // A failed request must never look like an empty result set.
  if (error) {
        return (
          <Paper
            elevation={0}
            sx={{ width: '100%', border: '1px solid #FECACA', borderRadius: 2, p: 2 }}
          >
            <Alert
              severity="error"
              action={
                onRefresh ? (
                  <Button color="inherit" size="small" onClick={onRefresh} startIcon={<RefreshIcon size={14} />}>
                    Retry
                  </Button>
                ) : undefined
              }
              sx={{ '& .MuiAlert-message': { width: '100%' } }}
            >
              {errorMessage}
            </Alert>
          </Paper>
        );
      }

      return (
    <Paper
      elevation={0}
      sx={{
        width: '100%',
        border: '1px solid #E2E8F0',
        borderRadius: 2,
        overflow: 'hidden',
      }}
    >
      {/* Control Bar */}
      <Box
        sx={{
          p: 2,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexWrap: 'wrap',
          gap: 2,
          borderBottom: '1px solid #E2E8F0',
          backgroundColor: '#FFFFFF',
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, flex: 1, minWidth: 260 }}>
          {onSearchChange && (
            <TextField
              size="small"
              placeholder={searchPlaceholder}
              value={searchValue}
              onChange={(e) => onSearchChange(e.target.value)}
              sx={{ maxWidth: 360, width: '100%' }}
              slotProps={{
                input: {
                  startAdornment: (
                    <InputAdornment position="start">
                      <SearchIcon size={16} color="#64748B" />
                    </InputAdornment>
                  ),
                },
              }}
            />
          )}

          {onRefresh && (
            <Button
              size="small"
              variant="outlined"
              onClick={onRefresh}
              startIcon={<RefreshIcon size={14} />}
              sx={{ borderColor: '#CBD5E1', color: '#475569' }}
            >
              Refresh
            </Button>
          )}
          {exportButton}
          {onSelectAllMatching && (
            <Button
              size="small"
              variant={allMatchingActive ? 'contained' : 'outlined'}
              onClick={onSelectAllMatching}
              // Announced as a state change so screen readers know that the
              // scope of a following bulk action has changed.
              aria-pressed={allMatchingActive}
              sx={{ borderColor: '#CBD5E1', color: '#475569' }}
            >
              {allMatchingActive
                ? `All matching (${(totalMatching ?? 0).toLocaleString()}) selected`
                : 'Select all matching'}
            </Button>
          )}
        </Box>

        {/* Bulk Action Slot */}
        {bulkActions && <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>{bulkActions}</Box>}
      </Box>

      {/* Grid */}
      <Box sx={{ height: 580, width: '100%', backgroundColor: '#FFFFFF' }}>
        <DataGrid
          rows={rows}
          columns={columns}
          rowCount={totalRows}
          loading={loading}
          paginationMode="server"
          paginationModel={paginationModel}
          onPaginationModelChange={onPaginationModelChange}
          pageSizeOptions={[10, 25, 50, 100]}
          sortingMode="server"
          sortModel={sortModel}
          onSortModelChange={onSortModelChange}
          checkboxSelection={checkboxSelection}
          rowSelectionModel={rowSelectionModel}
          onRowSelectionModelChange={onRowSelectionModelChange}
          disableRowSelectionOnClick
          onRowClick={onRowClick}
          columnVisibilityModel={columnVisibility}
          onColumnVisibilityModelChange={setColumnVisibility}
          sx={{
            border: 'none',
            '& .MuiDataGrid-columnHeaders': {
              backgroundColor: '#F8FAFC',
              borderBottom: '1px solid #E2E8F0',
              fontWeight: 600,
              fontSize: '0.8125rem',
              color: '#334155',
            },
            '& .MuiDataGrid-row': {
              borderBottom: '1px solid #F1F5F9',
              '&:hover': {
                backgroundColor: '#F8FAFC',
              },
            },
            '& .MuiDataGrid-cell': {
              fontSize: '0.8125rem',
              color: '#1E293B',
              display: 'flex',
              alignItems: 'center',
            },
          }}
          slots={{
            toolbar: showToolbar ? GridToolbar : undefined,
            noRowsOverlay: () => (
              <Box
                sx={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  height: '100%',
                }}
              >
                <Typography variant="body2" color="text.secondary">
                  No records found
                </Typography>
              </Box>
            ),
          }}
          slotProps={{
            toolbar: { showQuickFilter: false },
          }}
        />
      </Box>
    </Paper>
  );
};
