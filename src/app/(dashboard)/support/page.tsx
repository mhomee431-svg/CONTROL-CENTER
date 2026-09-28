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
  FormControl,
  InputLabel,
  Select,
  MenuItem,
} from '@mui/material';
import { AlertCircle, CheckCircle, Clock } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ComplaintItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';

export default function SupportPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [statusFilter, setStatusFilter] = useState('');

  // Triage dialog
  const [triageTarget, setTriageTarget] = useState<ComplaintItem | null>(null);
  const [newStatus, setNewStatus] = useState<'OPEN' | 'IN_PROGRESS' | 'RESOLVED' | 'CLOSED'>('RESOLVED');
  const [resolutionNotes, setResolutionNotes] = useState('');

  const { data, isLoading, refetch } = useQuery<{ items: ComplaintItem[]; total: number }>({
    queryKey: ['admin', 'complaints', { page: paginationModel.page, pageSize: paginationModel.pageSize, status: statusFilter }],
    queryFn: () =>
      apiClient<{ items: ComplaintItem[]; total: number }>(API_ENDPOINTS.COMPLAINTS.LIST, {
        params: {
          status: statusFilter || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, status, notes }: { id: number; status: string; notes: string }) =>
      apiClient(API_ENDPOINTS.COMPLAINTS.UPDATE(id), {
        method: 'PUT',
        body: JSON.stringify({ status, resolution_notes: notes }),
      }),
    onSuccess: () => {
      setTriageTarget(null);
      setResolutionNotes('');
      queryClient.invalidateQueries({ queryKey: ['admin', 'complaints'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleTriageSubmit = async () => {
    if (!triageTarget) return;
    await updateMutation.mutateAsync({
      id: triageTarget.id,
      status: newStatus,
      notes: resolutionNotes,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'complaint_type',
      headerName: 'Category / Type',
      flex: 1.2,
      minWidth: 150,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <AlertCircle size={16} color="#EC4899" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'description', headerName: 'Issue Description', flex: 2, minWidth: 240 },
    {
      field: 'priority',
      headerName: 'Priority',
      width: 110,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'created_at',
      headerName: 'Reported At',
      flex: 1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
    {
      field: 'actions',
      headerName: 'Triage',
      width: 130,
      sortable: false,
      renderCell: (params) => (
        <Button
          size="small"
          variant="outlined"
          onClick={() => {
            const row = params.row as ComplaintItem;
            setTriageTarget(row);
            setNewStatus(row.status === 'RESOLVED' ? 'CLOSED' : 'RESOLVED');
          }}
        >
          Resolve / Update
        </Button>
      ),
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Support & Complaints Triage Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 55 & 56: Unified customer and shopkeeper escalation queue.
        </Typography>
      </Box>

      <Box sx={{ mb: 2, display: 'flex', gap: 2 }}>
        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel>Status</InputLabel>
          <Select
            value={statusFilter}
            label="Status"
            onChange={(e) => setStatusFilter(e.target.value)}
          >
            <MenuItem value="">All Statuses</MenuItem>
            <MenuItem value="OPEN">Open</MenuItem>
            <MenuItem value="IN_PROGRESS">In Progress</MenuItem>
            <MenuItem value="RESOLVED">Resolved</MenuItem>
            <MenuItem value="CLOSED">Closed</MenuItem>
          </Select>
        </FormControl>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
      />

      {triageTarget && (
        <Dialog open={Boolean(triageTarget)} onClose={() => setTriageTarget(null)} maxWidth="sm" fullWidth>
          <DialogTitle sx={{ fontWeight: 600 }}>Triage Ticket #{triageTarget.id}</DialogTitle>
          <DialogContent>
            <Typography variant="body2" sx={{ mb: 2, fontWeight: 500 }}>
              {triageTarget.description}
            </Typography>

            <FormControl fullWidth margin="dense">
              <InputLabel>New Status</InputLabel>
              <Select
                value={newStatus}
                label="New Status"
                onChange={(e) => setNewStatus(e.target.value as any)}
              >
                <MenuItem value="IN_PROGRESS">In Progress</MenuItem>
                <MenuItem value="RESOLVED">Resolved</MenuItem>
                <MenuItem value="CLOSED">Closed</MenuItem>
              </Select>
            </FormControl>

            <TextField
              margin="dense"
              label="Resolution Notes"
              fullWidth
              multiline
              rows={3}
              value={resolutionNotes}
              onChange={(e) => setResolutionNotes(e.target.value)}
              placeholder="Record operational action taken..."
            />
          </DialogContent>
          <DialogActions sx={{ px: 3, pb: 2.5 }}>
            <Button onClick={() => setTriageTarget(null)} color="inherit">
              Cancel
            </Button>
            <Button
              variant="contained"
              onClick={handleTriageSubmit}
              disabled={updateMutation.isPending}
            >
              {updateMutation.isPending ? 'Updating...' : 'Save Resolution'}
            </Button>
          </DialogActions>
        </Dialog>
      )}
    </Box>
  );
}
