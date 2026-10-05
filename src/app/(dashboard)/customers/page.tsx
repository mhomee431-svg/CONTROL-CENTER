'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button, MenuItem, Select, FormControl, InputLabel, Alert, Tabs, Tab } from '@mui/material';
import { UserX, CheckCircle, Eye } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CustomerDetail } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES, hasPermission } from '@/core/permissions/permissions';
import { useAuth } from '@/core/auth/AuthContext';
import { maskIdentifier, stripForbiddenFields, describeRecency } from '@/core/privacy/masking';
import { ROUTES } from '@/core/routes/routes';
import { resolvePreset, spanDays, toIsoDate } from '@/core/filters/dateRange';

/** Day windows for the recency quick-filters, derived from the shared
 *  date-range module so these numbers cannot drift from the analytics presets. */
const RECENT_DAYS = {
  week: spanDays(
    resolvePreset('7d').start,
    resolvePreset('7d').end
  ),
  month: spanDays(
    resolvePreset('30d').start,
    resolvePreset('30d').end
  ),
};

/**
 * Quick-filter views required by the spec. Each maps to a server-side flag so
 * pagination stays correct — filtering client-side over a single page would
 * silently under-report counts.
 *
 * Each filter declares which param it drives. `RECENT_ACTIVE` is about sign-in
 * recency, not registration, so it must NOT reuse the registration window.
 */
type QuickFilter = 'ALL' | 'ACTIVE' | 'INACTIVE' | 'SUSPENDED' | 'RECENT_REGISTERED' | 'RECENT_ACTIVE';

const QUICK_FILTERS: Array<{
  value: QuickFilter;
  label: string;
  status?: string;
  params?: Record<string, number>;
}> = [
  { value: 'ALL', label: 'All' },
  { value: 'ACTIVE', label: 'Active', status: 'ACTIVE' },
  { value: 'INACTIVE', label: 'Inactive', status: 'INACTIVE' },
  { value: 'SUSPENDED', label: 'Suspended', status: 'SUSPENDED' },
  { value: 'RECENT_REGISTERED', label: 'Recently Registered', params: { registered_within_days: RECENT_DAYS.week } },
  { value: 'RECENT_ACTIVE', label: 'Recently Active', params: { active_within_days: RECENT_DAYS.week } },
];

export default function CustomersPage() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [quickFilter, setQuickFilter] = useState<QuickFilter>('ALL');
  const { adminRole } = useAuth();
  const canViewPII = hasPermission(adminRole, CAPABILITIES.CUSTOMERS_READ);

  const quick = QUICK_FILTERS.find((q) => q.value === quickFilter);

  // Confirmation modal state
  const [actionTarget, setActionTarget] = useState<{ id: number; name: string; action: 'SUSPEND' | 'ACTIVATE' | 'BAN' } | null>(null);

  // TanStack Query for Customers
  const { data, isLoading, isError, refetch } = useQuery<{ items: CustomerDetail[]; total: number }>({
    queryKey: [
      'admin',
      'customers',
      { page: paginationModel.page, pageSize: paginationModel.pageSize, search, status: statusFilter, quickFilter },
    ],
    queryFn: () =>
      apiClient<{ items: CustomerDetail[]; total: number }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: {
          role: 'customer',
          status: (quick?.status ?? statusFilter) || undefined,
          search: search || undefined,
          // Recency filters are applied server-side so counts stay truthful,
          // and each one drives its own backend param.
          ...(quick?.params ?? {}),
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }).then((res) => ({ ...res, items: stripForbiddenFields(res.items || []) })),
  });

  // Status Change Mutation
  const statusMutation = useMutation({
    mutationFn: ({ userId, action, reason }: { userId: number; action: string; reason: string }) =>
      apiClient(API_ENDPOINTS.CUSTOMERS.STATUS(userId), {
        method: 'POST',
        // The reason is the audit record for a sanctions action, so it travels
        // in the request body where it cannot be truncated or dropped.
        body: JSON.stringify({ action, reason }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'customers'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleConfirmAction = async (reason: string) => {
    if (!actionTarget) return;
    await statusMutation.mutateAsync({
      userId: actionTarget.id,
      action: actionTarget.action,
      reason,
    });
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'name',
      headerName: 'Name',
      flex: 1.2,
      minWidth: 160,
      renderCell: (params) => (
        <Typography variant="body2" sx={{ fontWeight: 600 }}>
          {maskIdentifier(params.value as string, 'name', canViewPII) || 'Anonymous Customer'}
        </Typography>
      ),
    },
    {
      field: 'contact',
      headerName: 'Phone / Email',
      flex: 1.2,
      minWidth: 170,
      // "as permitted" — masked unless the operator holds the read capability.
      valueGetter: (_v, row) => {
        const c = row as unknown as CustomerDetail;
        return maskIdentifier(c.phone, 'phone', canViewPII);
      },
      renderCell: (params) => (
        <Box>
          <Typography variant="body2">{String(params.value)}</Typography>
          {(params.row as unknown as CustomerDetail).email && (
            <Typography variant="caption" color="text.secondary">
              {maskIdentifier((params.row as unknown as CustomerDetail).email, 'email', canViewPII)}
            </Typography>
          )}
        </Box>
      ),
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'created_at',
      headerName: 'Registered At',
      width: 150,
      valueFormatter: (value) => (value ? describeRecency(value as string) : 'N/A'),
    },
    {
      field: 'last_active',
      headerName: 'Last Active',
      width: 140,
      valueFormatter: (value) => (value ? describeRecency(value as string) : 'Never'),
    },
    {
      field: 'location',
      headerName: 'Location',
      width: 160,
      // Coarse summary only, and only where the backend/policy discloses it.
      valueGetter: (_v, row) => {
        const c = row as unknown as CustomerDetail;
        return [c.city, c.state].filter(Boolean).join(', ') || '—';
      },
    },
    {
      field: 'saved',
      headerName: 'Saved Items',
      width: 130,
      align: 'right',
      headerAlign: 'right',
      valueGetter: (_v, row) => {
        const c = row as unknown as CustomerDetail;
        const total = (c.saved_product_count ?? 0) + (c.saved_shop_count ?? 0);
        return total > 0 ? total.toLocaleString() : '—';
      },
    },
    {
      field: 'search_count',
      headerName: 'Searches',
      width: 110,
      align: 'right',
      headerAlign: 'right',
      valueGetter: (_v, row) => {
        const c = row as unknown as CustomerDetail;
        return c.search_count != null ? c.search_count.toLocaleString() : '—';
      },
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 220,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as unknown as CustomerDetail;
        const isSuspended = item.status === 'SUSPENDED';

        return (
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              size="small"
              variant="text"
              startIcon={<Eye size={14} />}
              onClick={() => router.push(ROUTES.CUSTOMER_DETAIL(item.id))}
            >
              View
            </Button>
            <PermissionGuard capability={CAPABILITIES.CUSTOMERS_SUSPEND}>
              {isSuspended ? (
                <Button
                  size="small"
                  color="success"
                  variant="outlined"
                  startIcon={<CheckCircle size={14} />}
                  onClick={() => setActionTarget({ id: item.id, name: item.name || `User #${item.id}`, action: 'ACTIVATE' })}
                >
                  Reactivate
                </Button>
              ) : (
                <Button
                  size="small"
                  color="error"
                  variant="outlined"
                  startIcon={<UserX size={14} />}
                  onClick={() => setActionTarget({ id: item.id, name: item.name || `User #${item.id}`, action: 'SUSPEND' })}
                >
                  Suspend
                </Button>
              )}
            </PermissionGuard>
          </Box>
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Customer Management
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Monitor customer accounts, review registration activity, and govern account standing.
        </Typography>
      </Box>

      <Tabs
        value={quickFilter}
        onChange={(_, v) => {
          setQuickFilter(v);
          setPaginationModel((p) => ({ ...p, page: 0 }));
        }}
        sx={{ mb: 2, borderBottom: '1px solid #E2E8F0' }}
        variant="scrollable"
      >
        {QUICK_FILTERS.map((q) => (
          <Tab key={q.value} value={q.value} label={q.label} sx={{ textTransform: 'none' }} />
        ))}
      </Tabs>

      {/* Filter Bar */}
      <Box sx={{ mb: 2, display: 'flex', gap: 2 }}>
        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel>Status</InputLabel>
          <Select
            value={statusFilter}
            label="Status"
            onChange={(e) => setStatusFilter(e.target.value)}
            disabled={Boolean(quick?.status)}
          >
            <MenuItem value="">All Statuses</MenuItem>
            <MenuItem value="ACTIVE">Active</MenuItem>
            <MenuItem value="SUSPENDED">Suspended</MenuItem>
            <MenuItem value="INACTIVE">Inactive</MenuItem>
            <MenuItem value="BANNED">Banned</MenuItem>
          </Select>
        </FormControl>
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Could not load customers.
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search by name or phone..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
      />

      {/* Confirmation Modal */}
      {actionTarget && (
        <ConfirmationDialog
          open={Boolean(actionTarget)}
          title={`${actionTarget.action === 'ACTIVATE' ? 'Reactivate' : 'Suspend'} Customer Account`}
          affectedItem={maskIdentifier(actionTarget.name, 'name', canViewPII)}
          consequence={
            actionTarget.action === 'SUSPEND'
              ? 'Suspended customers cannot log in, search for nearby inventory, or interact with businesses.'
              : 'The customer will immediately regain access to platform discovery services.'
          }
          isDangerous={actionTarget.action === 'SUSPEND'}
          requireReason
          isLoading={statusMutation.isPending}
          onConfirm={handleConfirmAction}
          onClose={() => setActionTarget(null)}
        />
      )}
    </Box>
  );
}
