'use client';

import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Switch, Alert } from '@mui/material';
import { Sliders } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { FeatureFlagItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

export default function FeatureFlagsPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 50 });

  const [toggleTarget, setToggleTarget] = useState<{ flag: FeatureFlagItem; nextState: boolean } | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: FeatureFlagItem[] }>({
    queryKey: ['admin', 'feature-flags'],
    queryFn: () => apiClient<{ items: FeatureFlagItem[] }>(API_ENDPOINTS.SYSTEM.FEATURE_FLAGS),
  });

  const toggleMutation = useMutation({
    mutationFn: ({ name, is_enabled }: { name: string; is_enabled: boolean }) =>
      apiClient(API_ENDPOINTS.SYSTEM.FEATURE_FLAG_NAME(name), {
        method: 'PUT',
        params: { is_enabled },
      }),
    onSuccess: () => {
      setToggleTarget(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'feature-flags'] });
    },
  });

  const handleConfirmToggle = async () => {
    if (!toggleTarget) return;
    await toggleMutation.mutateAsync({
      name: toggleTarget.flag.name,
      is_enabled: toggleTarget.nextState,
    });
  };

  const columns: GridColDef[] = [
    {
      field: 'name',
      headerName: 'Feature Flag',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Sliders size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'description', headerName: 'Description', flex: 2, minWidth: 240 },
    { field: 'scope', headerName: 'Scope', width: 120 },
    {
      field: 'is_enabled',
      headerName: 'State (Toggle)',
      width: 140,
      renderCell: (params) => {
        const item = params.row as FeatureFlagItem;
        return (
          <PermissionGuard capability={CAPABILITIES.SETTINGS_MANAGE}>
            <Switch
              checked={Boolean(item.is_enabled)}
              onChange={(e) => setToggleTarget({ flag: item, nextState: e.target.checked })}
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
          Platform Feature Flags
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 76 & 137: Dynamic feature toggles (`BARCODE_SEARCH`, `EXCEL_IMPORT`, `POS`, `OFFERS`).
        </Typography>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.items?.length ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
        error={isError}
      />

      {toggleTarget && (
        <ConfirmationDialog
          open={Boolean(toggleTarget)}
          title={`Toggle Feature Flag [${toggleTarget.flag.name}]`}
          affectedItem={`New Status: ${toggleTarget.nextState ? 'ENABLED' : 'DISABLED'}`}
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
