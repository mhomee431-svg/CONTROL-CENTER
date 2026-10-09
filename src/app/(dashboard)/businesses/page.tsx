'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel, GridRowSelectionModel } from '@mui/x-data-grid';
import { Box, Typography, Button, MenuItem, Select, FormControl, InputLabel, Checkbox, FormControlLabel, Alert, Dialog, DialogTitle, DialogContent, TextField } from '@mui/material';
import { ShieldCheck, ShieldAlert, Store, Eye, Pencil, Archive, XCircle, User } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem, CategoryItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';
import { describeRecency } from '@/core/privacy/masking';
import { SelectionScopeBanner } from '@/core/selection/SelectionScopeBanner';
import { useServerSelection } from '@/core/selection/useServerSelection';

type ShopDecision = 'VERIFY' | 'REJECT' | 'SUSPEND' | 'REACTIVATE' | 'ARCHIVE';

export default function BusinessesPage() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const selection = useServerSelection();
  const selectedIds = selection.selectedIds;
  const [bulkDecision, setBulkDecision] = useState<'VERIFY' | 'SUSPEND' | null>(null);
  const [editTarget, setEditTarget] = useState<ShopItem | null>(null);
  const [editName, setEditName] = useState('');
  const [editCategory, setEditCategory] = useState('');

  // Category options come from the backend taxonomy. They were previously
  // hardcoded, which meant the filter silently diverged from real categories
  // and returned nothing for any taxonomy the UI had not been taught about.
  const { data: categories } = useQuery<CategoryItem[]>({
    queryKey: ['admin', 'categories', 'filter-options'],
    queryFn: () => apiClient<CategoryItem[]>(API_ENDPOINTS.CATEGORIES.LIST),
    staleTime: 5 * 60 * 1000,
  });

  // Action modal
  const [targetShop, setTargetShop] = useState<{ id: number; name: string; decision: ShopDecision } | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: ShopItem[]; total: number }>({
    queryKey: ['admin', 'shops', { page: paginationModel.page, pageSize: paginationModel.pageSize, search, status: statusFilter, category: categoryFilter }],
    queryFn: () =>
      apiClient<{ items: ShopItem[]; total: number }>(API_ENDPOINTS.SHOPS.LIST, {
        params: {
          status: statusFilter || undefined,
          category: categoryFilter || undefined,
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const shopQuerySignature = JSON.stringify({ search, status: statusFilter, category: categoryFilter });
  const pageShopIds = useMemo(() => (data?.items ?? []).map((shop) => shop.id), [data]);
  const { bindQuery, syncPageRows } = selection;
  useEffect(() => {
    bindQuery(shopQuerySignature);
  }, [bindQuery, shopQuerySignature]);
  useEffect(() => {
    syncPageRows(pageShopIds);
  }, [pageShopIds, syncPageRows]);

  const verificationMutation = useMutation({
    mutationFn: ({ shopId, decision, reason }: { shopId: number; decision: string; reason: string }) =>
      apiClient(API_ENDPOINTS.SHOPS.VERIFICATION(shopId), {
        method: 'POST',
        body: JSON.stringify({ decision, reason }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleConfirmVerification = async (reason: string) => {
    if (!targetShop) return;
    await verificationMutation.mutateAsync({
      shopId: targetShop.id,
      decision: targetShop.decision,
      reason,
    });
  };

  // Edit master fields. The backend records who changed what.
  const updateMutation = useMutation({
    mutationFn: ({ shopId, patch }: { shopId: number; patch: Record<string, string> }) =>
      apiClient(API_ENDPOINTS.SHOPS.UPDATE(shopId), {
        method: 'PUT',
        body: JSON.stringify(patch),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops'] });
      setEditTarget(null);
    },
  });

  const bulkMutation = useMutation({
    mutationFn: ({ decision, reason, all_matching, filters }: { decision: string; reason: string; all_matching?: boolean; filters?: { search?: string; status?: string; category?: string } }) =>
      apiClient(API_ENDPOINTS.SHOPS.BULK, {
        method: 'POST',
        body: JSON.stringify({
          shop_ids: all_matching ? [] : selectedIds,
          decision,
          reason,
          ...(all_matching ? { all_matching: true, filters } : {}),
        }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
      selection.clear();
      setBulkDecision(null);
    },
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'name',
      headerName: 'Shop Name',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Store size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'category', headerName: 'Category', flex: 1, minWidth: 130 },
    {
      field: 'owner',
      headerName: 'Owner',
      flex: 1.1,
      minWidth: 150,
      // Prefers the backend-supplied owner name; falls back to the owner id so
      // the column is never silently blank when only the id is reported.
      valueGetter: (_v, row) => {
        const shop = row as unknown as ShopItem;
        return shop.owner_name || (shop.owner_id != null ? `#${shop.owner_id}` : '—');
      },
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <User size={15} color="#64748B" />
          <Typography variant="body2">{params.value as string}</Typography>
        </Box>
      ),
    },
    {
      field: 'location',
      headerName: 'Location',
      flex: 1,
      minWidth: 130,
      valueGetter: (_, row) => `${row.city || ''}, ${row.state || ''}`,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'verification_status',
      headerName: 'Verification',
      width: 140,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'product_count',
      headerName: 'Products',
      width: 90,
      align: 'right',
      headerAlign: 'right',
    },
    {
      field: 'inventory_count',
      headerName: 'Inventory',
      width: 100,
      align: 'right',
      headerAlign: 'right',
      valueGetter: (_v, row) => (row as unknown as ShopItem).inventory_count ?? '—',
    },
    {
      field: 'inventory_freshness',
      headerName: 'Inventory Freshness',
      width: 160,
      renderCell: (params) => (
        <StatusBadge status={(params.value as string) || 'UNKNOWN'} />
      ),
    },
    {
      field: 'created_at',
      headerName: 'Created',
      width: 130,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleDateString() : '—'),
    },
    {
      field: 'updated_at',
      headerName: 'Last Updated',
      width: 140,
      valueFormatter: (v) => (v ? describeRecency(v as string) : '—'),
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 420,
      sortable: false,
      renderCell: (params) => {
        const shop = params.row as ShopItem;
        const isVerified = shop.verification_status === 'VERIFIED';
        const isSuspended = shop.status === 'SUSPENDED';

        return (
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              size="small"
              variant="text"
              startIcon={<Eye size={14} />}
              onClick={() => router.push(ROUTES.BUSINESS_DETAIL(shop.id))}
            >
              View
            </Button>

            {!isVerified && (
              <PermissionGuard capability={CAPABILITIES.SHOPS_APPROVE}>
                <Button
                  size="small"
                  color="success"
                  variant="outlined"
                  startIcon={<ShieldCheck size={14} />}
                  onClick={() => setTargetShop({ id: shop.id, name: shop.name, decision: 'VERIFY' })}
                >
                  Verify
                </Button>
              </PermissionGuard>
            )}

            <PermissionGuard capability={CAPABILITIES.SHOPS_SUSPEND}>
              {isSuspended ? (
                <Button
                  size="small"
                  color="primary"
                  variant="outlined"
                  onClick={() => setTargetShop({ id: shop.id, name: shop.name, decision: 'REACTIVATE' })}
                >
                  Reactivate
                </Button>
              ) : (
                <Button
                  size="small"
                  color="error"
                  variant="outlined"
                  startIcon={<ShieldAlert size={14} />}
                  onClick={() => setTargetShop({ id: shop.id, name: shop.name, decision: 'SUSPEND' })}
                >
                  Suspend
                </Button>
              )}
            </PermissionGuard>

            {/* Reject — distinct from Suspend: it refuses verification outright
                rather than temporarily removing a previously valid shop. */}
            {!isVerified && (
              <PermissionGuard capability={CAPABILITIES.SHOPS_REJECT}>
                <Button
                  size="small"
                  color="warning"
                  variant="outlined"
                  startIcon={<XCircle size={14} />}
                  onClick={() => setTargetShop({ id: shop.id, name: shop.name, decision: 'REJECT' })}
                >
                  Reject
                </Button>
              </PermissionGuard>
            )}

            <PermissionGuard capability={CAPABILITIES.SHOPS_UPDATE}>
              <Button
                size="small"
                variant="outlined"
                startIcon={<Pencil size={14} />}
                onClick={(e) => {
                  e.stopPropagation();
                  setEditTarget(shop);
                  setEditName(shop.name ?? '');
                  setEditCategory(shop.category ?? '');
                }}
              >
                Edit
              </Button>
            </PermissionGuard>

            <PermissionGuard capability={CAPABILITIES.SHOPS_ARCHIVE}>
              <Button
                size="small"
                variant="outlined"
                startIcon={<Archive size={14} />}
                onClick={() => setTargetShop({ id: shop.id, name: shop.name, decision: 'ARCHIVE' })}
              >
                Archive
              </Button>
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
          Business & Shop Management
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Audit physical retail shops, govern merchant listings, and verify storefront operations.
        </Typography>
      </Box>

      {/* Filters */}
      <Box sx={{ mb: 2, display: 'flex', gap: 2 }}>
        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel>Status</InputLabel>
          <Select
            value={statusFilter}
            label="Status"
            onChange={(e) => setStatusFilter(e.target.value)}
          >
            <MenuItem value="">All Statuses</MenuItem>
            <MenuItem value="ACTIVE">Active</MenuItem>
            <MenuItem value="SUSPENDED">Suspended</MenuItem>
            <MenuItem value="PENDING">Pending</MenuItem>
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel>Category</InputLabel>
          <Select
            value={categoryFilter}
            label="Category"
            onChange={(e) => setCategoryFilter(e.target.value)}
          >
            <MenuItem value="">All Categories</MenuItem>
            {(categories || [])
              .filter((c) => c.is_active)
              .map((c) => (
                <MenuItem key={c.id} value={c.name}>
                  {c.name}
                </MenuItem>
              ))}
          </Select>
        </FormControl>
      </Box>

      <SelectionScopeBanner
        mode={selection.scope.mode}
        count={selection.scope.count}
        matchingCount={selection.scope.matchingCount}
        pageRowCount={data?.items.length ?? 0}
        offPageCount={selection.offPageCount}
        onClear={selection.clear}
      />

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search shop by name or address..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={isError}
        checkboxSelection
        rowSelectionModel={selectedIds}
        onRowSelectionModelChange={selection.toggleRow}
        selectionSummary={selection.scope.mode === 'none' ? undefined : selection.scopeLabel}
        bulkActions={selection.scope.mode !== 'none' ? (
          <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
            <PermissionGuard capability={CAPABILITIES.SHOPS_APPROVE}>
              <Button size="small" variant="outlined" onClick={() => setBulkDecision('VERIFY')} disabled={bulkMutation.isPending}>Bulk Verify</Button>
            </PermissionGuard>
            <PermissionGuard capability={CAPABILITIES.SHOPS_SUSPEND}>
              <Button size="small" color="error" variant="outlined" onClick={() => setBulkDecision('SUSPEND')} disabled={bulkMutation.isPending}>Bulk Suspend</Button>
            </PermissionGuard>
            <Button size="small" onClick={selection.clear}>Clear</Button>
          </Box>
        ) : undefined}
        totalMatching={data?.total ?? 0}
        allMatchingActive={selection.allMatching}
        pageSelectionActive={selection.scope.mode === 'page'}
        onSelectAllMatching={selection.allMatching
          ? selection.clear
          : () => selection.selectAllMatching(data?.total ?? 0)}
      />

      {bulkDecision && (
        <ConfirmationDialog
          open={Boolean(bulkDecision)}
          title={`Bulk ${bulkDecision} — ${selection.scopeLabel}`}
          affectedItem={selection.scopeLabel}
          actionSummary={`Action: ${bulkDecision} · Scope: ${selection.scopeLabel}`}
          consequence={
            bulkDecision === 'SUSPEND'
              ? 'All selected shops and their inventory will immediately disappear from customer discovery.'
              : 'All selected shops will be marked verified and become eligible for customer discovery.'
          }
          isDangerous={bulkDecision === 'SUSPEND'}
          requireReason
          isLoading={bulkMutation.isPending}
          onConfirm={async (reason) => {
            if (selection.scope.mode === 'none') return;
            await bulkMutation.mutateAsync({
              decision: bulkDecision,
              reason,
              all_matching: selection.allMatching,
              filters: selection.allMatching ? {
                search: search || undefined,
                status: statusFilter || undefined,
                category: categoryFilter || undefined,
              } : undefined,
            });
          }}
          onClose={() => setBulkDecision(null)}
        />
      )}

      {targetShop && (
        <ConfirmationDialog
          open={Boolean(targetShop)}
          title={`${targetShop.decision} Shop - ${targetShop.name}`}
          affectedItem={targetShop.name}
          consequence={
            targetShop.decision === 'SUSPEND'
              ? 'This shop and its inventory will immediately disappear from customer discovery and search results.'
              : targetShop.decision === 'ARCHIVE'
              ? 'Archiving permanently retires this shop. It will be removed from discovery and cannot be restored without a backend intervention.'
              : targetShop.decision === 'VERIFY'
              ? 'The shop will be publicly marked verified and eligible for high-confidence customer discovery.'
              : targetShop.decision === 'REJECT'
              ? 'Verification will be refused. The merchant will be notified and may resubmit documents.'
              : 'The operation will be recorded in the system audit trail.'
          }
          isDangerous={
            targetShop.decision === 'SUSPEND' ||
            targetShop.decision === 'REJECT' ||
            targetShop.decision === 'ARCHIVE'
          }
          requireReason
          isLoading={verificationMutation.isPending}
          onConfirm={handleConfirmVerification}
          onClose={() => setTargetShop(null)}
        />
      )}

      {/* Edit shop master fields — permission-gated by SHOPS_UPDATE. */}
      <Dialog open={Boolean(editTarget)} onClose={() => setEditTarget(null)} fullWidth maxWidth="sm">
        <DialogTitle>Edit Shop — {editTarget?.name}</DialogTitle>
        <DialogContent>
          <TextField
            label="Shop Name"
            value={editName}
            onChange={(e) => setEditName(e.target.value)}
            fullWidth
            required
            sx={{ mt: 1 }}
          />
          <TextField
            select
            label="Category"
            value={editCategory}
            onChange={(e) => setEditCategory(e.target.value)}
            fullWidth
            sx={{ mt: 2 }}
          >
            <MenuItem value="">Uncategorised</MenuItem>
            {(categories || [])
              .filter((c) => c.is_active)
              .map((c) => (
                <MenuItem key={c.id} value={c.name}>
                  {c.name}
                </MenuItem>
              ))}
          </TextField>
          <Alert severity="info" sx={{ mt: 2 }}>
            Changes are recorded in the audit trail with your operator identity.
          </Alert>
        </DialogContent>
        <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 1, p: 2 }}>
          <Button onClick={() => setEditTarget(null)} disabled={updateMutation.isPending}>
            Cancel
          </Button>
          <Button
            variant="contained"
            disabled={!editName.trim() || updateMutation.isPending}
            onClick={() =>
              editTarget &&
              updateMutation.mutate({
                shopId: editTarget.id,
                patch: { name: editName.trim(), category: editCategory },
              })
            }
          >
            {updateMutation.isPending ? 'Saving...' : 'Save Changes'}
          </Button>
        </Box>
      </Dialog>
    </Box>
  );
}
