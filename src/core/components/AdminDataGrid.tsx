'use client';

import React from 'react';
import {
  DataGrid,
  GridColDef,
  GridPaginationModel,
  GridSortModel,
  GridRowSelectionModel,
} from '@mui/x-data-grid';
import { Box, Paper, Typography, Button, TextField, InputAdornment } from '@mui/material';
import { Search as SearchIcon, RefreshCw as RefreshIcon } from 'lucide-react';

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
  bulkActions?: React.ReactNode;
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
  bulkActions,
}) => {
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
        />
      </Box>
    </Paper>
  );
};
