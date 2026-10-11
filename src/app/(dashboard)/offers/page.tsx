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
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  List,
  ListItem,
  ListItemText,
  Chip,
} from '@mui/material';
import {
  DollarSign,
  PauseCircle,
  Eye,
  ScrollText,
  Store,
} from 'lucide-react';
import { fetchList, ListResult } from '@/core/api/fetchList';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AuditLogItem, OfferItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';

// ---------------------------------------------------------------------------
// Section 41 — Offer Management
// ---------------------------------------------------------------------------
// Sections:  Active | Scheduled | Expired | Disabled | Review — one backend
//            route (GET /admin/offers?section=...), five section views. The
//            backend resolves each section from real stored columns (status +
//            starts_at/ends_at), so the page total is always the true count of
//            what the tab asked for.
//
// Actions:   View (open the offer), Disable if permitted (audited status change
//            to CANCELLED, requires offers.update), Investigate (open the
//            merchant behind the offer), Audit (this offer's governance trail).
// ---------------------------------------------------------------------------

/** The five sections, in tab order. `id` is the backend `section` param. */
const SECTIONS = [
  { id: 'active', label: 'Active' },
  { id: 'scheduled', label: 'Scheduled' },
  { id: 'expired', label: 'Expired' },
  { id: 'disabled', label: 'Disabled' },
  { id: 'review', label: 'Review' },
] as const;

type SectionId = (typeof SECTIONS)[number]['id'];

export default function OffersPage() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const [sectionIndex, setSectionIndex] = useState(0);
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [disableTarget, setDisableTarget] = useState<OfferItem | null>(null);
  const [auditTarget, setAuditTarget] = useState<OfferItem | null>(null);
  const section: SectionId = SECTIONS[sectionIndex].id;

  // `fetchList` reports an unpublished route as `unavailable`, so a deployment
  // lag reads as "not published" instead of "no offers exist".
  const { data, isLoading, isError, refetch } = useQuery<ListResult<OfferItem>>({
    queryKey: ['admin', 'offers', 'list', section, paginationModel, search],
    queryFn: () =>
      fetchList<OfferItem>(API_ENDPOINTS.OFFERS.LIST, {
        params: {
          section,
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  // Disable is an audited status change to CANCELLED. The backend route is
  // PATCH /offers/{id} with { status } — capability-gated to offers.update.
  const disableMutation = useMutation({
    mutationFn: ({ id, status }: { id: number; status: string }) =>
      apiClient(API_ENDPOINTS.OFFERS.UPDATE_STATUS(id), {
        method: 'PATCH',
        body: JSON.stringify({ status }),
      }),
    onSuccess: () => {
      setDisableTarget(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'offers'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'offers', 'audit'] });
    },
  });

  // The Audit action: this offer's governance trail, newest first.
  const { data: auditData, isFetching: auditLoading } = useQuery<{ items: AuditLogItem[]; total: number }>({
    queryKey: ['admin', 'offers', 'audit', auditTarget?.id],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[]; total: number }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: { entity_type: 'offer', entity_id: auditTarget!.id, limit: 50 },
      }),
    enabled: auditTarget != null,
  });


  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'title',
      headerName: 'Offer Campaign',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <DollarSign size={16} color="#10B981" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    { field: 'shop_name', headerName: 'Retail Shop', flex: 1.2, minWidth: 150 },
    {
      field: 'discount_value',
      headerName: 'Discount',
      width: 120,
      valueGetter: (_, row) =>
        `${row.discount_value}${String(row.discount_type).toUpperCase().startsWith('PERCENT') ? '%' : ' OFF'}`,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => <StatusBadge status={params.value as string} />,
    },
    {
      field: 'valid_from',
      headerName: 'Window',
      flex: 1,
      minWidth: 180,
      valueFormatter: (_, row) => {
        const fmt = (v: unknown) => (v ? new Date(v as string).toLocaleDateString() : '—');
        return `${fmt(row.valid_from)} → ${fmt(row.valid_until)}`;
      },
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 330,
      sortable: false,
      renderCell: (params) => {
        const item = params.row as OfferItem;
        // Only a live offer can be disabled; a CANCELLED/EXPIRED row has
        // nothing left to take down.
        const canDisable = item.status === 'ACTIVE' || item.status === 'PAUSED';
        return (
          <Box sx={{ display: 'flex', gap: 0.5, alignItems: 'center', height: '100%' }}>
            <Button
              size="small"
              startIcon={<Eye size={14} />}
              onClick={() => router.push(ROUTES.OFFER_DETAIL(item.id))}
            >
              View
            </Button>
            {canDisable && (
              <PermissionGuard capability={CAPABILITIES.OFFERS_UPDATE}>
                <Button
                  size="small"
                  color="warning"
                  startIcon={<PauseCircle size={14} />}
                  onClick={() => setDisableTarget(item)}
                >
                  Disable
                </Button>
              </PermissionGuard>
            )}
            {item.shop_id != null && (
              <PermissionGuard capability={CAPABILITIES.SHOPS_READ} fallback={<Button size="small" disabled>Investigate</Button>}>
                <Button
                  size="small"
                  startIcon={<Store size={14} />}
                  onClick={() => router.push(ROUTES.BUSINESS_DETAIL(item.shop_id))}
                >
                  Investigate
                </Button>
              </PermissionGuard>
            )}
            <PermissionGuard capability={CAPABILITIES.AUDIT_READ} fallback={<Button size="small" disabled>Audit</Button>}>
              <Button
                size="small"
                startIcon={<ScrollText size={14} />}
                onClick={() => setAuditTarget(item)}
              >
                Audit
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
          Offer Management
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Govern promotional campaigns across every merchant: what is running, what is queued, what
          ended, what was taken down, and what awaits a decision.
        </Typography>
      </Box>

      {/* Five sections; switching resets pagination and the search box. */}
      <Tabs
        value={sectionIndex}
        onChange={(_, val) => {
          setSectionIndex(val);
          setPaginationModel({ page: 0, pageSize: paginationModel.pageSize });
          setSearch('');
        }}
        variant="scrollable"
        scrollButtons="auto"
        sx={{ mb: 2 }}
      >
        {SECTIONS.map((s) => (
          <Tab key={s.id} label={s.label} />
        ))}
      </Tabs>

      <AdminDataGrid
        rows={(data?.items ?? []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search offers by title or discount type..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={isError || !!data?.unavailable}
        errorMessage={
          data?.unavailable
            ? 'The offers route is not published on this deployment. Offer Management needs the control-center backend.'
            : 'The offer list could not be loaded. Retry, and escalate if it keeps failing.'
        }
      />

      {disableTarget && (
        <ConfirmationDialog
          open
          title="Disable Offer"
          affectedItem={disableTarget.title}
          consequence="The offer stops being shown to shoppers immediately. Its audit trail is preserved."
          isDangerous
          requireReason
          isLoading={disableMutation.isPending}
          onConfirm={() => disableMutation.mutate({ id: disableTarget.id, status: 'CANCELLED' })}
          onClose={() => setDisableTarget(null)}
        />
      )}

      <Dialog open={auditTarget != null} onClose={() => setAuditTarget(null)} maxWidth="sm" fullWidth>
        <DialogTitle>Audit — {auditTarget?.title}</DialogTitle>
        <DialogContent dividers>
          {auditLoading ? (
            <Typography color="text.secondary">Loading trail…</Typography>
          ) : (auditData?.items?.length ?? 0) === 0 ? (
            <Typography color="text.secondary">
              No governance events recorded for this offer yet.
            </Typography>
          ) : (
            <List dense>
              {auditData!.items.map((log) => (
                <ListItem key={log.id} divider>
                  <ListItemText
                    primary={log.action}
                    secondary={`${log.admin_user ?? 'system'} · ${new Date(log.created_at).toLocaleString()}`}
                  />
                  <Chip
                    size="small"
                    label={String(log.details?.['status'] ?? '—')}
                    color={log.details?.['status'] ? 'info' : 'default'}
                  />
                </ListItem>
              ))}
            </List>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAuditTarget(null)}>Close</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
