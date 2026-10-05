'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Button,
  Tabs,
  Tab,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  TextField,
  Alert,
} from '@mui/material';
import { ShieldCheck, ShieldAlert, Eye, Store, X } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem, CategoryItem, AdminUserItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

/**
 * Central verification queue.
 *
 * The five tabs are five stages of one workflow rather than five unrelated
 * lists: a submission enters at Pending, passes through Under Review, and
 * lands on Approved, Rejected, or Needs Correction. Each tab is one filter on
 * `verification_status` over the same `/admin/shops` endpoint the Businesses
 * registry reads, so a decision recorded here is the same decision recorded
 * there — there is no second verification store to fall out of sync.
 *
 * `VERIFIED` is the backend's word for the stage operators call Approved: the
 * tab label speaks to the operator, the query parameter speaks to the API.
 */
const TABS = [
  { value: 'PENDING', label: 'Pending' },
  { value: 'UNDER_REVIEW', label: 'Under Review' },
  { value: 'VERIFIED', label: 'Approved' },
  { value: 'REJECTED', label: 'Rejected' },
  { value: 'NEEDS_CORRECTION', label: 'Needs Correction' },
] as const;

type TabStatus = (typeof TABS)[number]['value'];

/**
 * Account standing — deliberately separate from the stage the tab selects.
 * "Suspended" and "Under review" answer different questions, and folding both
 * into one control would let one hide the other. The dropdown is labelled
 * Status because that is the control operators reach for; its options are the
 * shop's `status`, never its `verification_status`, which the tab owns.
 */
const ACCOUNT_STATUSES = [
  { value: '', label: 'All Statuses' },
  { value: 'ACTIVE', label: 'Active' },
  { value: 'PENDING', label: 'Pending' },
  { value: 'SUSPENDED', label: 'Suspended' },
  { value: 'INACTIVE', label: 'Inactive' },
] as const;

export default function VerificationPage() {
  const router = useRouter();
  const queryClient = useQueryClient();

  const [tab, setTab] = useState<TabStatus>('PENDING');
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');

  // Every filter is part of the query key. Without that, changing a filter
  // would serve the previous filter's cached rows while the new request is in
  // flight, and the operator would read stale results as the new answer.
  const [categoryFilter, setCategoryFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [reviewerFilter, setReviewerFilter] = useState('');
  const [locationFilter, setLocationFilter] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');

  const [selectedCase, setSelectedCase] = useState<{
    id: number;
    name: string;
    decision: 'VERIFY' | 'REJECT';
  } | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: ShopItem[]; total: number }>({
    queryKey: [
      'admin',
      'verification-queue',
      {
        tab,
        category: categoryFilter,
        status: statusFilter,
        reviewer: reviewerFilter,
        location: locationFilter,
        dateFrom,
        dateTo,
        search,
        page: paginationModel.page,
        pageSize: paginationModel.pageSize,
      },
    ],
    queryFn: () =>
      apiClient<{ items: ShopItem[]; total: number }>(API_ENDPOINTS.SHOPS.LIST, {
        params: {
          verification_status: tab,
          status: statusFilter || undefined,
          category: categoryFilter || undefined,
          reviewer: reviewerFilter || undefined,
          city: locationFilter || undefined,
          created_from: dateFrom || undefined,
          created_to: dateTo || undefined,
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  // Filter options come from the backend, never from a hardcoded list: a
  // baked-in category or city silently diverges from what is actually stored
  // and filters out records the UI never offered to select.
  const { data: categories, isError: categoriesError } = useQuery<CategoryItem[]>({
    queryKey: ['admin', 'categories', 'filter-options'],
    queryFn: () => apiClient<CategoryItem[]>(API_ENDPOINTS.CATEGORIES.LIST),
    staleTime: 5 * 60 * 1000,
  });

  const { data: reviewers, isError: reviewersError } = useQuery<{
    items: AdminUserItem[];
    total: number;
  }>({
    // Same source and role filter the Admin Users registry reads, so the
    // reviewer dropdown offers exactly the operators who can be assigned.
    queryKey: ['admin', 'verification-reviewers'],
    queryFn: () =>
      apiClient<{ items: AdminUserItem[]; total: number }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: { role: 'admin', limit: 100 },
      }),
    staleTime: 5 * 60 * 1000,
  });

  const verificationMutation = useMutation({
    mutationFn: ({ shopId, decision, reason }: { shopId: number; decision: string; reason: string }) =>
      apiClient(API_ENDPOINTS.SHOPS.VERIFICATION(shopId), {
        method: 'POST',
        body: JSON.stringify({ decision, reason }),
      }),
    onSuccess: () => {
      // The case leaves whichever tab it was on, and the dashboard's pending
      // counter moves with it — invalidating only the queue would leave the
      // two surfaces disagreeing until a hard reload.
      queryClient.invalidateQueries({ queryKey: ['admin', 'verification-queue'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  const handleDecision = async (reason: string) => {
    if (!selectedCase) return;
    await verificationMutation.mutateAsync({
      shopId: selectedCase.id,
      decision: selectedCase.decision,
      reason,
    });
  };

  /** Back to page 1: the new result set is shorter, so page N may not exist. */
  const resetPage = () => setPaginationModel((p) => ({ ...p, page: 0 }));

  const hasActiveFilter = Boolean(
    categoryFilter || statusFilter || reviewerFilter || locationFilter || dateFrom || dateTo || search
  );

  const clearFilters = () => {
    setCategoryFilter('');
    setStatusFilter('');
    setReviewerFilter('');
    setLocationFilter('');
    setDateFrom('');
    setDateTo('');
    setSearch('');
    resetPage();
  };

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
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
    { field: 'category', headerName: 'Category', flex: 1, minWidth: 140 },
    {
      field: 'city',
      headerName: 'Location',
      flex: 1,
      minWidth: 130,
      valueGetter: (_, row) => [row.city, row.state].filter(Boolean).join(', ') || '—',
    },
    {
      field: 'verification_status',
      headerName: 'Stage',
      width: 160,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'verified_by',
      headerName: 'Reviewer',
      width: 150,
      // Only a case that has reached a decision carries an operator name.
      // Everything still in the queue is genuinely unassigned — that is a real
      // state, not a missing field, so it is labelled rather than blanked.
      valueGetter: (value) => (value ? String(value) : 'Unassigned'),
    },
    {
      field: 'created_at',
      headerName: 'Submitted',
      flex: 1,
      minWidth: 160,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
    {
      field: 'actions',
      headerName: 'Triage Actions',
      width: 240,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as ShopItem;
        return (
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              size="small"
              variant="text"
              startIcon={<Eye size={14} />}
              onClick={() => router.push(`/businesses/${item.id}`)}
            >
              Review
            </Button>
            <PermissionGuard capability={CAPABILITIES.SHOPS_APPROVE}>
              <Button
                size="small"
                color="success"
                variant="contained"
                startIcon={<ShieldCheck size={14} />}
                onClick={() => setSelectedCase({ id: item.id, name: item.name, decision: 'VERIFY' })}
              >
                Approve
              </Button>
            </PermissionGuard>
            <PermissionGuard capability={CAPABILITIES.SHOPS_REJECT}>
              <Button
                size="small"
                color="error"
                variant="outlined"
                startIcon={<ShieldAlert size={14} />}
                onClick={() => setSelectedCase({ id: item.id, name: item.name, decision: 'REJECT' })}
              >
                Reject
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
          Verification Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Central verification queue — triage storefront applications, carry cases through review, and
          record the decision.
        </Typography>
      </Box>

      {/* Stage tabs: one workflow, five states. */}
      <Tabs
        value={tab}
        onChange={(_, value) => {
          setTab(value as TabStatus);
          resetPage();
        }}
        sx={{ mb: 2, borderBottom: '1px solid #E2E8F0' }}
        variant="scrollable"
      >
        {TABS.map((t) => (
          <Tab key={t.value} value={t.value} label={t.label} sx={{ textTransform: 'none' }} />
        ))}
      </Tabs>

      {/* Filters */}
      <Box sx={{ mb: 2, display: 'flex', flexWrap: 'wrap', gap: 2, alignItems: 'center' }}>
        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel id="verification-category-label">Category</InputLabel>
          <Select
            labelId="verification-category-label"
            value={categoryFilter}
            label="Category"
            onChange={(e) => {
              setCategoryFilter(e.target.value);
              resetPage();
            }}
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

        <TextField
          size="small"
          type="date"
          label="From"
          value={dateFrom}
          onChange={(e) => {
            setDateFrom(e.target.value);
            resetPage();
          }}
          slotProps={{ inputLabel: { shrink: true } }}
          sx={{ minWidth: 150 }}
        />

        <TextField
          size="small"
          type="date"
          label="To"
          value={dateTo}
          onChange={(e) => {
            setDateTo(e.target.value);
            resetPage();
          }}
          slotProps={{ inputLabel: { shrink: true } }}
          sx={{ minWidth: 150 }}
        />

        <FormControl size="small" sx={{ minWidth: 160 }}>
          <InputLabel id="verification-status-label">Status</InputLabel>
          <Select
            labelId="verification-status-label"
            value={statusFilter}
            label="Status"
            onChange={(e) => {
              setStatusFilter(e.target.value);
              resetPage();
            }}
          >
            {ACCOUNT_STATUSES.map((s) => (
              <MenuItem key={s.value} value={s.value}>
                {s.label}
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 180 }}>
          <InputLabel id="verification-reviewer-label">Reviewer</InputLabel>
          <Select
            labelId="verification-reviewer-label"
            value={reviewerFilter}
            label="Reviewer"
            onChange={(e) => {
              setReviewerFilter(e.target.value);
              resetPage();
            }}
          >
            <MenuItem value="">All Reviewers</MenuItem>
            {(reviewers?.items || []).map((r) => (
              <MenuItem key={r.id} value={String(r.id)}>
                {r.name || `Admin #${r.id}`}
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        <TextField
          size="small"
          label="Location"
          placeholder="City"
          value={locationFilter}
          onChange={(e) => {
            setLocationFilter(e.target.value);
            resetPage();
          }}
          sx={{ minWidth: 150 }}
        />

        {hasActiveFilter && (
          <Button size="small" variant="outlined" startIcon={<X size={14} />} onClick={clearFilters}>
            Clear
          </Button>
        )}
      </Box>

      {/* A failed options request reads as "there are no categories" unless
          it is said out loud, while the rows below remain valid. */}
      {(categoriesError || reviewersError) && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          {categoriesError && 'Category options could not be loaded, so that filter is empty. '}
          {reviewersError && 'Reviewer options could not be loaded, so that filter is empty.'}
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search the verification queue..."
        searchValue={search}
        onSearchChange={(value) => {
          setSearch(value);
          resetPage();
        }}
        onRefresh={() => refetch()}
        // Replaces the grid with a failure notice rather than showing an empty
        // one: "0 pending" and "the registry is down" must never look alike.
        error={isError}
        errorMessage="The verification queue could not be loaded. The registry is unreachable or returned an error — retry, and escalate if it keeps failing."
      />

      {selectedCase && (
        <ConfirmationDialog
          open={Boolean(selectedCase)}
          title={`${selectedCase.decision === 'VERIFY' ? 'Approve' : 'Reject'} Merchant Verification`}
          affectedItem={selectedCase.name}
          consequence={
            selectedCase.decision === 'VERIFY'
              ? 'Approving marks this business as verified across the platform, publishing its local catalog to active shopper search.'
              : 'Rejecting rejects this verification attempt and notifies the shopkeeper with the specified feedback reason.'
          }
          isDangerous={selectedCase.decision === 'REJECT'}
          requireReason
          isLoading={verificationMutation.isPending}
          onConfirm={handleDecision}
          onClose={() => setSelectedCase(null)}
        />
      )}
    </Box>
  );
}
