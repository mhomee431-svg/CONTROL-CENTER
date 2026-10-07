'use client';

import React, { useMemo, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useRouter } from 'next/navigation';
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
  Alert,
} from '@mui/material';
import { AlertCircle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ComplaintItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';
import {
  TICKET_CATEGORIES,
  TICKET_STATUSES,
  allowedTransitions,
  categoryFor,
  categoryLabel,
  isAged,
} from '@/core/support/tickets';

export default function SupportPage() {
  const queryClient = useQueryClient();
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [statusFilter, setStatusFilter] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');

  // Triage dialog
  const [triageTarget, setTriageTarget] = useState<ComplaintItem | null>(null);
  const [newStatus, setNewStatus] = useState('');
  const [resolutionNotes, setResolutionNotes] = useState('');

  const { data, isLoading, refetch } = useQuery<{ items: ComplaintItem[]; total: number }>({
    queryKey: [
      'admin',
      'complaints',
      { page: paginationModel.page, pageSize: paginationModel.pageSize, status: statusFilter, category: categoryFilter },
    ],
    queryFn: () =>
      apiClient<{ items: ComplaintItem[]; total: number }>(API_ENDPOINTS.COMPLAINTS.LIST, {
        params: {
          status: statusFilter || undefined,
          category: categoryFilter || undefined,
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
    if (!triageTarget || !newStatus) return;
    await updateMutation.mutateAsync({
      id: triageTarget.id,
      status: newStatus,
      notes: resolutionNotes,
    });
  };

  /** Default the dialog to the first sensible next step for this ticket. */
  const openTriage = (ticket: ComplaintItem) => {
    setTriageTarget(ticket);
    const transitions = allowedTransitions(ticket.status);
    setNewStatus(transitions.includes('RESOLVED') ? 'RESOLVED' : transitions[0] || '');
    setResolutionNotes('');
  };

  const items = useMemo(() => data?.items || [], [data]);
  const counts = useMemo(
    () => ({
      open: items.filter((t) => (t.status || '').toUpperCase() === 'OPEN').length,
      inProgress: items.filter((t) => (t.status || '').toUpperCase() === 'IN_PROGRESS').length,
      escalated: items.filter((t) => (t.status || '').toUpperCase() === 'ESCALATED').length,
      resolved: items.filter((t) => (t.status || '').toUpperCase() === 'RESOLVED').length,
      closed: items.filter((t) => (t.status || '').toUpperCase() === 'CLOSED').length,
    }),
    [items]
  );

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'complaint_type',
      headerName: 'Category / Type',
      flex: 1.2,
      minWidth: 170,
      renderCell: (params) => {
        const ticket = params.row as ComplaintItem;
        return (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, minWidth: 0 }}>
            <AlertCircle size={16} color="#EC4899" />
            <Box sx={{ minWidth: 0 }}>
              <Typography variant="body2" sx={{ fontWeight: 600 }} noWrap>
                {ticket.complaint_type || '—'}
              </Typography>
              <Typography variant="caption" color="text.secondary" noWrap>
                {categoryLabel(categoryFor(ticket))}
              </Typography>
            </Box>
          </Box>
        );
      },
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
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'aged',
      headerName: 'Age Flag',
      width: 100,
      sortable: false,
      valueGetter: (_, row) => (isAged((row as ComplaintItem).status, (row as ComplaintItem).created_at) ? 'AGED' : ''),
      renderCell: (params) => (params.value ? <StatusBadge status="STALE" /> : <Typography variant="body2">—</Typography>),
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
      width: 160,
      sortable: false,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', gap: 0.5 }}>
          <PermissionGuard capability={CAPABILITIES.SUPPORT_UPDATE}>
            <Button size="small" variant="outlined" onClick={() => openTriage(params.row as ComplaintItem)}>
              Triage
            </Button>
          </PermissionGuard>
          <Button size="small" onClick={() => router.push(ROUTES.SUPPORT_DETAIL((params.row as ComplaintItem).id))}>
            View
          </Button>
        </Box>
      ),
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[{ label: 'Dashboard', href: ROUTES.DASHBOARD }, { label: 'Support Center' }]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Support Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Unified customer and shopkeeper escalation queue — triage tickets across the full lifecycle (Open → In Progress
          → Escalated → Resolved → Closed).
        </Typography>
      </Box>

      {/* Lifecycle summary rail — every documented status visible at a glance. */}
      <Box sx={{ display: 'flex', gap: 1, mb: 2, flexWrap: 'wrap' }}>
        <SummaryTile label="Open" value={counts.open} color="#EF4444" />
        <SummaryTile label="In Progress" value={counts.inProgress} color="#F59E0B" />
        <SummaryTile label="Escalated" value={counts.escalated} color="#EF4444" />
        <SummaryTile label="Resolved" value={counts.resolved} color="#10B981" />
        <SummaryTile label="Closed" value={counts.closed} color="#64748B" />
      </Box>

      <Box sx={{ mb: 2, display: 'flex', gap: 2, flexWrap: 'wrap' }}>
        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel>Status</InputLabel>
          <Select value={statusFilter} label="Status" onChange={(e) => setStatusFilter(e.target.value)}>
            <MenuItem value="">All Statuses</MenuItem>
            {TICKET_STATUSES.map((status) => (
              <MenuItem key={status} value={status}>
                {status.charAt(0) + status.slice(1).replace('_', ' ').toLowerCase()}
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 170 }}>
          <InputLabel>Category</InputLabel>
          <Select value={categoryFilter} label="Category" onChange={(e) => setCategoryFilter(e.target.value)}>
            <MenuItem value="">All Categories</MenuItem>
            {TICKET_CATEGORIES.map((cat) => (
              <MenuItem key={cat} value={cat}>
                {categoryLabel(cat)}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
      </Box>

      <AdminDataGrid
        rows={items as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.SUPPORT_DETAIL(params.row.id as number))}
      />

      {triageTarget && (
        <Dialog open={Boolean(triageTarget)} onClose={() => setTriageTarget(null)} maxWidth="sm" fullWidth>
          <DialogTitle sx={{ fontWeight: 600 }}>Triage Ticket #{triageTarget.id}</DialogTitle>
          <DialogContent>
            <Typography variant="body2" sx={{ mb: 2, fontWeight: 500 }}>
              {triageTarget.description}
            </Typography>

            {(() => {
              const transitions = allowedTransitions(triageTarget.status);
              if (transitions.length === 0) {
                return (
                  <Alert severity="info" sx={{ mb: 1 }}>
                    This ticket is CLOSED — a terminal state. No further transitions are available.
                  </Alert>
                );
              }
              return (
                <FormControl fullWidth margin="dense">
                  <InputLabel>New Status</InputLabel>
                  <Select value={newStatus} label="New Status" onChange={(e) => setNewStatus(e.target.value)}>
                    {transitions.map((s) => (
                      <MenuItem key={s} value={s}>
                        {s.replace('_', ' ')}
                      </MenuItem>
                    ))}
                  </Select>
                </FormControl>
              );
            })()}

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
              disabled={updateMutation.isPending || !newStatus}
            >
              {updateMutation.isPending ? 'Updating...' : 'Save Resolution'}
            </Button>
          </DialogActions>
        </Dialog>
      )}
    </Box>
  );
}

const SummaryTile: React.FC<{ label: string; value: number; color: string }> = ({ label, value, color }) => (
  <Box
    sx={{
      px: 2,
      py: 1,
      borderRadius: 1.5,
      border: '1px solid #E2E8F0',
      backgroundColor: '#FFFFFF',
      minWidth: 110,
    }}
  >
    <Typography variant="caption" color="text.secondary">
      {label}
    </Typography>
    <Typography variant="h6" sx={{ fontWeight: 700, color, lineHeight: 1.2 }}>
      {value}
    </Typography>
  </Box>
);
