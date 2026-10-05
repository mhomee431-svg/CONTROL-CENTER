'use client';

import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Alert,
} from '@mui/material';
import { Settings, Edit2 } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { SystemSettingItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

export default function SystemSettingsPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 50 });

  const [editTarget, setEditTarget] = useState<SystemSettingItem | null>(null);
  const [newValue, setNewValue] = useState('');
  const [showConfirm, setShowConfirm] = useState(false);

  const { data, isLoading, isError, refetch } = useQuery<{ items: SystemSettingItem[] }>({
    queryKey: ['admin', 'system-settings'],
    queryFn: () => apiClient<{ items: SystemSettingItem[] }>(API_ENDPOINTS.SYSTEM.SETTINGS),
  });

  const updateMutation = useMutation({
    mutationFn: ({ key, value }: { key: string; value: string }) =>
      apiClient(API_ENDPOINTS.SYSTEM.SETTING_KEY(key), {
        method: 'PUT',
        params: { value },
      }),
    onSuccess: () => {
      setEditTarget(null);
      setShowConfirm(false);
      queryClient.invalidateQueries({ queryKey: ['admin', 'system-settings'] });
    },
  });

  const handleEditClick = (item: SystemSettingItem) => {
    setEditTarget(item);
    setNewValue(item.value);
  };

  const handleConfirmSave = async (reason: string) => {
    if (!editTarget) return;
    await updateMutation.mutateAsync({
      key: editTarget.key,
      value: newValue,
    });
  };

  const columns: GridColDef[] = [
    {
      field: 'key',
      headerName: 'Configuration Key',
      flex: 1.5,
      minWidth: 200,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Settings size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'value', headerName: 'Value', flex: 1.2, minWidth: 160 },
    { field: 'value_type', headerName: 'Type', width: 100 },
    { field: 'description', headerName: 'Operational Description', flex: 2, minWidth: 220 },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 120,
      sortable: false,
      renderCell: (params) => (
        <PermissionGuard capability={CAPABILITIES.SETTINGS_MANAGE}>
          <Button
            size="small"
            startIcon={<Edit2 size={14} />}
            onClick={() => handleEditClick(params.row as SystemSettingItem)}
          >
            Edit
          </Button>
        </PermissionGuard>
      ),
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          System Configuration
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 77 & 173: Controlled application settings. (Infrastructure secrets and master database credentials are strictly forbidden).
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

      {/* Edit Dialog */}
      {editTarget && (
        <Dialog open={Boolean(editTarget) && !showConfirm} onClose={() => setEditTarget(null)} maxWidth="sm" fullWidth>
          <DialogTitle sx={{ fontWeight: 600 }}>Edit Setting: {editTarget.key}</DialogTitle>
          <DialogContent>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
              {editTarget.description || 'Application configuration parameter'}
            </Typography>

            <TextField
              autoFocus
              margin="dense"
              label="New Value"
              fullWidth
              value={newValue}
              onChange={(e) => setNewValue(e.target.value)}
            />
          </DialogContent>
          <DialogActions sx={{ px: 3, pb: 2 }}>
            <Button onClick={() => setEditTarget(null)} color="inherit">
              Cancel
            </Button>
            <Button variant="contained" onClick={() => setShowConfirm(true)}>
              Proceed to Save
            </Button>
          </DialogActions>
        </Dialog>
      )}

      {/* High-Risk Confirm */}
      {showConfirm && editTarget && (
        <ConfirmationDialog
          open={showConfirm}
          title={`Update System Setting [${editTarget.key}]`}
          affectedItem={`Old: "${editTarget.value}" → New: "${newValue}"`}
          consequence="Section 188: Modifying runtime system configurations alters platform behavior globally and is audited."
          isDangerous
          requireReason
          isLoading={updateMutation.isPending}
          onConfirm={handleConfirmSave}
          onClose={() => setShowConfirm(false)}
        />
      )}
    </Box>
  );
}
