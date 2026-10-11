'use client';

import React, { useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Switch, Alert, MenuItem, FormControl, InputLabel, Select } from '@mui/material';
import { Sliders } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { FeatureFlagItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

/**
 * FEATURE FLAGS.
 *
 * Columns: Flag · Status · Environment · Last Changed · Changed By.
 *
 * The spec's example flags (BARCODE_SEARCH, EXCEL_IMPORT, POS, OFFERS,
 * AI_SEARCH, NEW_SEARCH_UI) are seeded server-side when absent, so the console
 * shows a meaningful set on a fresh deployment without inventing rows.
 *
 * Only flags the backend exposes are rendered, and a value the backend did not
 * supply reads as "Not reported" rather than being guessed. Raw backend secrets
 * are never exposed: this grid reads only the flag projection.
 */

const ENVIRONMENTS = ['DEVELOPMENT', 'STAGING', 'PRODUCTION'];

const NOT_REPORTED = 'Not reported';

function formatWhen(value?: string | null): string {
  if (!value) return NOT_REPORTED;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return NOT_REPORTED;
  return d.toLocaleString();
}

export default function FeatureFlagsPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 50 });
  const [environmentFilter, setEnvironmentFilter] = useState('');

  const [toggleTarget, setToggleTarget] = useState<{ flag: FeatureFlagItem; nextState: boolean } | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: FeatureFlagItem[] }>({
    queryKey: ['admin', 'feature-flags'],
    queryFn: () => apiClient<{ items: FeatureFlagItem[] }>(API_ENDPOINTS.SYSTEM.FEATURE_FLAGS),
  });

  const toggleMutation = useMutation({
    mutationFn: ({ name, is_enabled, reason }: { name: string; is_enabled: boolean; reason: string }) =>
      apiClient(API_ENDPOINTS.SYSTEM.FEATURE_FLAG_NAME(name), {
        method: 'PATCH',
        body: JSON.stringify({ is_enabled, reason }),
      }),
    onSuccess: () => {
      setToggleTarget(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'feature-flags'] });
    },
  });

  const handleConfirmToggle = async (reason: string) => {
    if (!toggleTarget) return;
    await toggleMutation.mutateAsync({
      name: toggleTarget.flag.name,
      is_enabled: toggleTarget.nextState,
      reason,
    });
  };

  const rows = useMemo(() => {
    const items = data?.items ?? [];
    if (!environmentFilter) return items;
    return items.filter(
      (f) => (f.environment || '').toUpperCase() === environmentFilter.toUpperCase()
    );
  }, [data, environmentFilter]);

  const columns: GridColDef[] = [
    {
      field: 'name',
      headerName: 'Flag',
      flex: 1.4,
      minWidth: 200,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Sliders size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600, fontFamily: 'monospace' }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'description', headerName: 'Description', flex: 2, minWidth: 240 },
    {
      field: 'is_enabled',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => (
        <StatusBadge status={params.row.is_enabled ? 'ACTIVE' : 'INACTIVE'} />
      ),
    },
    {
      field: 'environment',
      headerName: 'Environment',
      width: 150,
      renderCell: (params) =>
        params.value ? (
          <Typography variant="body2">{params.value as string}</Typography>
        ) : (
          <Typography variant="body2" sx={{ color: '#94A3B8', fontStyle: 'italic' }}>
            {NOT_REPORTED}
          </Typography>
        ),
    },
    {
      field: 'updated_at',
      headerName: 'Last Changed',
      width: 190,
      valueGetter: (_v, row) => (row as unknown as FeatureFlagItem).updated_at,
      renderCell: (params) => (
        <Typography variant="body2">{formatWhen(params.value as string | null)}</Typography>
      ),
    },
    {
      field: 'changed_by',
      headerName: 'Changed By',
      width: 170,
      renderCell: (params) =>
        params.value ? (
          <Typography variant="body2">{params.value as string}</Typography>
        ) : (
          <Typography variant="body2" sx={{ color: '#94A3B8', fontStyle: 'italic' }}>
            {NOT_REPORTED}
          </Typography>
        ),
    },
    {
      field: 'toggle',
      headerName: 'Toggle',
      width: 110,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as unknown as FeatureFlagItem;
        return (
          <PermissionGuard capability={CAPABILITIES.SETTINGS_MANAGE} fallback={null}>
            <Switch
              checked={Boolean(item.is_enabled)}
              onChange={(e) => setToggleTarget({ flag: item, nextState: e.target.checked })}
              inputProps={{ 'aria-label': `Toggle flag ${item.name}` }}
            />
          </PermissionGuard>
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Feature Flags
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Dynamic feature toggles (BARCODE_SEARCH, EXCEL_IMPORT, POS, OFFERS, AI_SEARCH, NEW_SEARCH_UI).
          Every change is recorded in the audit log with the acting operator.
        </Typography>
      </Box>

      <Box sx={{ mb: 2, display: 'flex', gap: 2, flexWrap: 'wrap' }}>
        <FormControl size="small" sx={{ minWidth: 190 }}>
          <InputLabel>Environment</InputLabel>
          <Select
            value={environmentFilter}
            label="Environment"
            onChange={(e) => setEnvironmentFilter(e.target.value)}
          >
            <MenuItem value="">All Environments</MenuItem>
            {ENVIRONMENTS.map((env) => (
              <MenuItem key={env} value={env}>
                {env}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
      </Box>

      <AdminDataGrid
        rows={rows as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={rows.length}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
        error={isError}
        // A feature flag's primary key is its name, not an `id`. Without this
        // the grid throws "A row was provided without id" and the panel fails.
        getRowId={(row) => String(row.name)}
      />

      {toggleTarget && (
        <ConfirmationDialog
          open={Boolean(toggleTarget)}
          title={`Toggle Feature Flag [${toggleTarget.flag.name}]`}
          affectedItem={`New Status: ${toggleTarget.nextState ? 'ENABLED' : 'DISABLED'}`}
          actionSummary={`Environment: ${toggleTarget.flag.environment || 'Not reported'}`}
          consequence="Toggling this feature flag affects end-user functionality platform-wide."
          isDangerous={!toggleTarget.nextState}
          requireReason
          isLoading={toggleMutation.isPending}
          onConfirm={handleConfirmToggle}
          onClose={() => setToggleTarget(null)}
        />
      )}
    </Box>
  );
}
