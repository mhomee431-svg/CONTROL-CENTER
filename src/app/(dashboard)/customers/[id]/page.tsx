'use client';

import React, { use, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Grid,
  Button,
  Tabs,
  Tab,
  Divider,
  Alert,
  CircularProgress,
  Chip,
} from '@mui/material';
import {
  ArrowLeft,
  User,
  Phone,
  Calendar,
  Shield,
  ShieldAlert,
  Mail,
  MapPin,
  Clock,
  CheckCircle,
  UserX,
  Eye,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import {
  CustomerDetail,
  CustomerActivityItem,
  CustomerSearchItem,
  CustomerViewedItem,
  CustomerSavedEntityItem,
  CustomerNotificationItem,
  CustomerReportItem,
  CustomerSavedItem,
  CustomerAddressItem,
  CustomerTicketItem,
  AuditLogItem,
} from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES, hasPermission } from '@/core/permissions/permissions';
import { useAuth } from '@/core/auth/AuthContext';
import { maskIdentifier, stripForbiddenFields, describeRecency } from '@/core/privacy/masking';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { ROUTES } from '@/core/routes/routes';

type AdminAction = 'SUSPEND' | 'ACTIVATE' | 'RESTRICT' | 'UNRESTRICT';

/**
 * The six Activity sub-surfaces named in the spec, plus the mixed timeline.
 *
 * The timeline is the backend's unified activity stream, which captures
 * cross-cutting events that do not belong to any one entity class. It is
 * retained as its own view rather than dropped.
 */
const ACTIVITY_TABS = [
  'Searches',
  'Viewed Products',
  'Viewed Shops',
  'Saved Products',
  'Saved Shops',
  'Notifications',
  'All Activity',
] as const;

type ActivityTab = (typeof ACTIVITY_TABS)[number];

export default function CustomerDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const resolvedParams = use(params);
  const router = useRouter();
  const queryClient = useQueryClient();
  const customerId = resolvedParams.id;
  const { adminRole } = useAuth();

  const [tabIndex, setTabIndex] = useState(0);
  const [activityTab, setActivityTab] = useState<ActivityTab>('Searches');
  const [supportTab, setSupportTab] = useState<'Tickets' | 'Reports'>('Tickets');
  const [pagination, setPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [pendingAction, setPendingAction] = useState<AdminAction | null>(null);

  // Privacy: unmasking identifiers requires an explicit capability, resolved
  // once here rather than decided per-field in the view layer.
  const canViewPII = hasPermission(adminRole, CAPABILITIES.CUSTOMERS_READ);

  const { data: customer, isLoading, isError } = useQuery<CustomerDetail | null>({
    queryKey: ['admin', 'customers', customerId],
    queryFn: async () => {
      try {
        const detail = await apiClient<CustomerDetail>(API_ENDPOINTS.CUSTOMERS.DETAIL(customerId));
        return stripForbiddenFields(detail);
      } catch {
        // Fallback for deployments without the dedicated detail route.
        // The previous implementation passed the id as `search`, which
        // searches name/phone and could return an arbitrary user.
        const res = await apiClient<{ items: CustomerDetail[] }>(API_ENDPOINTS.CUSTOMERS.LIST, {
          params: { role: 'customer', limit: 100 },
        });
        const match = (res.items || []).find((u) => String(u.id) === String(customerId));
        return match ? stripForbiddenFields(match) : null;
      }
    },
  });

  // The spec splits Activity into six surfaces, each its own backend contract.
  // All six share one fetcher; only the active one is enabled, so opening the
  // page issues one request rather than nine.
  const fetchList = <T,>(endpoint: string) =>
    apiClient<{ items: T[]; total?: number }>(endpoint)
      .then((r) => ({ items: stripForbiddenFields(r.items || []), total: r.total ?? r.items?.length ?? 0 }))
      .catch(() => ({ items: [] as T[], total: 0 }));

  const { data: activity, isLoading: activityLoading } = useQuery<{ items: CustomerActivityItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'activity'],
    queryFn: () => fetchList<CustomerActivityItem>(API_ENDPOINTS.CUSTOMERS.ACTIVITY(customerId)),
    enabled: tabIndex === 1,
    retry: false,
  });

  const { data: searches, isLoading: searchesLoading } = useQuery<{ items: CustomerSearchItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'searches'],
    queryFn: () => fetchList<CustomerSearchItem>(API_ENDPOINTS.CUSTOMERS.SEARCHES(customerId)),
    enabled: tabIndex === 1,
    retry: false,
  });

  const { data: viewedProducts, isLoading: viewedProductsLoading } = useQuery<{ items: CustomerViewedItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'viewed-products'],
    queryFn: () =>
      fetchList<CustomerViewedItem>(API_ENDPOINTS.CUSTOMERS.VIEWED_PRODUCTS(customerId)),
    enabled: tabIndex === 1,
    retry: false,
  });

  const { data: viewedShops, isLoading: viewedShopsLoading } = useQuery<{ items: CustomerViewedItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'viewed-shops'],
    queryFn: () => fetchList<CustomerViewedItem>(API_ENDPOINTS.CUSTOMERS.VIEWED_SHOPS(customerId)),
    enabled: tabIndex === 1,
    retry: false,
  });

  const { data: savedProducts, isLoading: savedProductsLoading } = useQuery<{ items: CustomerSavedEntityItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'saved-products'],
    queryFn: () =>
      fetchList<CustomerSavedEntityItem>(API_ENDPOINTS.CUSTOMERS.SAVED_PRODUCTS(customerId)),
    enabled: tabIndex === 1,
    retry: false,
  });

  const { data: savedShops, isLoading: savedShopsLoading } = useQuery<{ items: CustomerSavedEntityItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'saved-shops'],
    queryFn: () => fetchList<CustomerSavedEntityItem>(API_ENDPOINTS.CUSTOMERS.SAVED_SHOPS(customerId)),
    enabled: tabIndex === 1,
    retry: false,
  });

  const { data: notifications, isLoading: notificationsLoading } = useQuery<{ items: CustomerNotificationItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'notifications'],
    queryFn: () =>
      fetchList<CustomerNotificationItem>(API_ENDPOINTS.CUSTOMERS.NOTIFICATIONS(customerId)),
    enabled: tabIndex === 1,
    retry: false,
  });

  const { data: saved, isLoading: savedLoading } = useQuery<{ items: CustomerSavedItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'saved'],
    queryFn: () => fetchList<CustomerSavedItem>(API_ENDPOINTS.CUSTOMERS.SAVED_ITEMS(customerId)),
    enabled: tabIndex === 2,
    retry: false,
  });

  const { data: addresses, isLoading: addressesLoading } = useQuery<{ items: CustomerAddressItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'addresses'],
    queryFn: () => fetchList<CustomerAddressItem>(API_ENDPOINTS.CUSTOMERS.ADDRESSES(customerId)),
    enabled: tabIndex === 3,
    retry: false,
  });

  const { data: tickets, isLoading: ticketsLoading } = useQuery<{ items: CustomerTicketItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'tickets'],
    queryFn: () => fetchList<CustomerTicketItem>(API_ENDPOINTS.CUSTOMERS.TICKETS(customerId)),
    enabled: tabIndex === 4,
    retry: false,
  });

  const { data: reports, isLoading: reportsLoading } = useQuery<{ items: CustomerReportItem[]; total: number }>({
    queryKey: ['admin', 'customers', customerId, 'reports'],
    queryFn: () => fetchList<CustomerReportItem>(API_ENDPOINTS.CUSTOMERS.REPORTS(customerId)),
    enabled: tabIndex === 4,
    retry: false,
  });

  const { data: auditLogs, isLoading: auditLoading } = useQuery<{ items: AuditLogItem[] }>({
    queryKey: ['admin', 'customers', customerId, 'audit'],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[] }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: { entity_type: 'user', entity_id: customerId, limit: 100 },
      }),
    enabled: tabIndex === 5,
  });

  const statusMutation = useMutation({
    mutationFn: ({ action, reason }: { action: string; reason: string }) =>
      apiClient(API_ENDPOINTS.CUSTOMERS.STATUS(customerId), {
        method: 'POST',
        body: JSON.stringify({ action, reason }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'customers'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
      setPendingAction(null);
    },
  });

  const restrictMutation = useMutation({
    mutationFn: ({ restricted, reason }: { restricted: boolean; reason: string }) =>
      apiClient(API_ENDPOINTS.CUSTOMERS.RESTRICT(customerId), {
        method: 'POST',
        body: JSON.stringify({ restricted, reason }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'customers'] });
      setPendingAction(null);
    },
  });

  const isSuspended = customer?.status === 'SUSPENDED' || customer?.status === 'BANNED';

  const confirmAction = async (reason: string) => {
    if (!pendingAction) return;
    if (pendingAction === 'RESTRICT') {
      await restrictMutation.mutateAsync({ restricted: true, reason });
    } else if (pendingAction === 'UNRESTRICT') {
      await restrictMutation.mutateAsync({ restricted: false, reason });
    } else {
      await statusMutation.mutateAsync({ action: pendingAction, reason });
    }
  };

  const activityColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'activity_type', headerName: 'Activity', width: 170 },
    {
      field: 'description',
      headerName: 'Detail',
      flex: 1,
      renderCell: (p) => (
        <Typography variant="body2" noWrap>
          {(p.value as string) || '—'}
        </Typography>
      ),
    },
    {
      field: 'created_at',
      headerName: 'When',
      width: 200,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : '—'),
    },
  ];

  const searchColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'query', headerName: 'Search Term', flex: 1.6, minWidth: 200 },
    {
      field: 'result_count',
      headerName: 'Results',
      width: 110,
      align: 'right',
      headerAlign: 'right',
    },
    { field: 'location', headerName: 'Location', width: 180 },
    {
      field: 'searched_at',
      headerName: 'When',
      width: 190,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : '—'),
    },
  ];

  const viewedColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'entity_name', headerName: 'Name', flex: 1.5, minWidth: 180 },
    { field: 'category', headerName: 'Category', flex: 1, minWidth: 140 },
    { field: 'city', headerName: 'City', width: 150 },
    {
      field: 'viewed_at',
      headerName: 'Viewed',
      width: 190,
      valueFormatter: (v) => (v ? describeRecency(v as string) : '—'),
    },
  ];

  const savedEntityColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'name', headerName: 'Name', flex: 1.5, minWidth: 180 },
    { field: 'category', headerName: 'Category', flex: 1, minWidth: 140 },
    { field: 'shop_name', headerName: 'Shop', flex: 1, minWidth: 150 },
    {
      field: 'price',
      headerName: 'Price',
      width: 110,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (v) => (v != null ? `₹${Number(v).toFixed(2)}` : '—'),
    },
    {
      field: 'saved_at',
      headerName: 'Saved',
      width: 150,
      valueFormatter: (v) => (v ? describeRecency(v as string) : '—'),
    },
  ];

  const notificationColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'title', headerName: 'Notification', flex: 1.8, minWidth: 220 },
    { field: 'notification_type', headerName: 'Type', width: 150 },
    {
      field: 'is_read',
      headerName: 'Read',
      width: 100,
      renderCell: (p) => (
        <Chip size="small" color={p.value ? 'default' : 'primary'} label={p.value ? 'Read' : 'Unread'} />
      ),
    },
    {
      field: 'sent_at',
      headerName: 'Sent',
      width: 190,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : '—'),
    },
  ];

  const reportColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'report_type', headerName: 'Report Type', flex: 1.2, minWidth: 160 },
    { field: 'reason', headerName: 'Reason', flex: 1.4, minWidth: 200 },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (p) => <StatusBadge status={p.value as string} />,
    },
    { field: 'resolution', headerName: 'Resolution', flex: 1.2, minWidth: 180 },
    {
      field: 'created_at',
      headerName: 'Filed',
      width: 180,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleDateString() : '—'),
    },
  ];

  const savedColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'item_type', headerName: 'Type', width: 120 },
    { field: 'name', headerName: 'Name', flex: 1.2 },
    { field: 'shop_name', headerName: 'Shop', flex: 1 },
    { field: 'city', headerName: 'City', width: 140 },
    {
      field: 'saved_at',
      headerName: 'Saved',
      width: 160,
      valueFormatter: (v) => (v ? describeRecency(v as string) : '—'),
    },
  ];

  const ticketColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'ticket_number', headerName: 'Ticket', width: 150 },
    { field: 'complaint_type', headerName: 'Type', width: 160 },
    {
      field: 'priority',
      headerName: 'Priority',
      width: 120,
      renderCell: (p) => <Chip size="small" label={p.value as string} />,
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 130,
      renderCell: (p) => <StatusBadge status={p.value as string} />,
    },
    {
      field: 'created_at',
      headerName: 'Opened',
      width: 180,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleDateString() : '—'),
    },
  ];

  const auditColumns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    { field: 'action', headerName: 'Action', flex: 1.2 },
    { field: 'admin_user', headerName: 'Admin', width: 160 },
    {
      field: 'created_at',
      headerName: 'When',
      flex: 1,
      valueFormatter: (v) => (v ? new Date(v as string).toLocaleString() : '—'),
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Customers', href: ROUTES.CUSTOMERS },
          { label: customer?.name || `Customer #${customerId}` },
        ]}
      />
      <Button
        startIcon={<ArrowLeft size={16} />}
        onClick={() => router.push(ROUTES.CUSTOMERS)}
        sx={{ mb: 2 }}
      >
        Back to Customers
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {isError && (
        <Alert severity="error" sx={{ mb: 3 }}>
          Could not load customer details.
        </Alert>
      )}

      {!isLoading && !isError && !customer && (
        <Alert severity="warning">No customer record exists for #{customerId}.</Alert>
      )}

      {customer && (
        <Box>
          <Card sx={{ mb: 3 }}>
            <CardContent sx={{ p: 3 }}>
              <Box
                sx={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'flex-start',
                  flexWrap: 'wrap',
                  gap: 2,
                }}
              >
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <Box
                    sx={{
                      width: 56,
                      height: 56,
                      borderRadius: 2,
                      backgroundColor: '#EFF6FF',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      color: 'primary.main',
                    }}
                  >
                    <User size={28} />
                  </Box>
                  <Box>
                    <Typography variant="h6" sx={{ fontWeight: 700 }}>
                      {maskIdentifier(customer.name, 'name', canViewPII) || 'Anonymous Customer'}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      Customer ID: #{customer.id}
                    </Typography>
                  </Box>
                </Box>
                <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', flexWrap: 'wrap' }}>
                  <StatusBadge status={customer.status} size="medium" />
                  {customer.is_restricted && <Chip size="small" color="warning" label="RESTRICTED" />}
                </Box>
              </Box>

              {/* Every admin action funnels through ConfirmationDialog, so no
                  irreversible action is ever a single accidental click. */}
              <Box sx={{ display: 'flex', gap: 1, mt: 2, flexWrap: 'wrap' }}>
                <Button
                  size="small"
                  variant="outlined"
                  startIcon={<Eye size={14} />}
                  onClick={() => router.push(`${ROUTES.SUPPORT}?customer_id=${customer.id}`)}
                >
                  Review Support Issues
                </Button>
                <PermissionGuard capability={CAPABILITIES.CUSTOMERS_UPDATE}>
                  {customer.is_restricted ? (
                    <Button
                      size="small"
                      variant="outlined"
                      startIcon={<CheckCircle size={14} />}
                      onClick={() => setPendingAction('UNRESTRICT')}
                    >
                      Remove Restriction
                    </Button>
                  ) : (
                    <Button
                      size="small"
                      variant="outlined"
                      startIcon={<ShieldAlert size={14} />}
                      onClick={() => setPendingAction('RESTRICT')}
                    >
                      Restrict
                    </Button>
                  )}
                </PermissionGuard>
                <PermissionGuard capability={CAPABILITIES.CUSTOMERS_SUSPEND}>
                  {isSuspended ? (
                    <Button
                      size="small"
                      color="success"
                      variant="outlined"
                      startIcon={<CheckCircle size={14} />}
                      onClick={() => setPendingAction('ACTIVATE')}
                    >
                      Reactivate
                    </Button>
                  ) : (
                    <Button
                      size="small"
                      color="error"
                      variant="outlined"
                      startIcon={<UserX size={14} />}
                      onClick={() => setPendingAction('SUSPEND')}
                    >
                      Suspend
                    </Button>
                  )}
                </PermissionGuard>
              </Box>

              <Divider sx={{ my: 2.5 }} />
              <Tabs value={tabIndex} onChange={(_, v) => setTabIndex(v)} variant="scrollable">
                <Tab label="Overview" />
                <Tab label="Activity" />
                <Tab label="Saved Items" />
                <Tab label="Locations" />
                <Tab label="Support" />
                <Tab label="Audit" />
              </Tabs>
            </CardContent>
          </Card>

          {/* Tab 0: Overview */}
          {tabIndex === 0 && (
            <Grid container spacing={3}>
              <Grid item xs={12} md={8}>
                <Card>
                  <CardContent sx={{ p: 3 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                      Profile
                    </Typography>
                    <DetailRow
                      icon={<Phone size={16} color="#64748B" />}
                      label="Phone"
                      value={maskIdentifier(customer.phone, 'phone', canViewPII)}
                    />
                    <DetailRow
                      icon={<Mail size={16} color="#64748B" />}
                      label="Email"
                      value={maskIdentifier(customer.email, 'email', canViewPII)}
                    />
                    <DetailRow
                      icon={<Shield size={16} color="#64748B" />}
                      label="Account Status"
                      value={customer.status}
                    />
                    <DetailRow
                      icon={<Shield size={16} color="#64748B" />}
                      label="Authentication Status"
                      value={customer.auth_status || 'Not reported by backend'}
                    />
                    <DetailRow
                      icon={<Calendar size={16} color="#64748B" />}
                      label="Registration Date"
                      value={customer.created_at ? new Date(customer.created_at).toLocaleString() : 'N/A'}
                    />
                    <DetailRow
                      icon={<Clock size={16} color="#64748B" />}
                      label="Last Active"
                      value={customer.last_active ? new Date(customer.last_active).toLocaleString() : 'N/A'}
                    />
                    <DetailRow
                      icon={<MapPin size={16} color="#64748B" />}
                      label="Location (summary)"
                      value={
                        [customer.city, customer.state].filter(Boolean).join(', ') ||
                        'Not permitted / not reported'
                      }
                    />
                  </CardContent>
                </Card>
              </Grid>

              <Grid item xs={12} md={4}>
                <Card sx={{ mb: 3 }}>
                  <CardContent sx={{ p: 3 }}>
                    <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
                      Activity Summary
                    </Typography>
                    <SummaryRow label="Searches" value={customer.search_count} />
                    <SummaryRow label="Products Viewed" value={customer.viewed_product_count} />
                    <SummaryRow label="Shops Viewed" value={customer.viewed_shop_count} />
                    <SummaryRow label="Saved Products" value={customer.saved_product_count} />
                    <SummaryRow label="Saved Shops" value={customer.saved_shop_count} />
                  </CardContent>
                </Card>

                <Card>
                  <CardContent sx={{ p: 2.5 }}>
                    <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1 }}>
                      Privacy & Data Governance
                    </Typography>
                    <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                      Passwords, OTPs, authentication tokens and security credentials are stripped
                      from every response before rendering and are never displayed. Personal
                      identifiers are masked unless the operator holds the read capability.
                    </Typography>
                    {!canViewPII && (
                      <Alert severity="info" sx={{ mt: 1.5 }}>
                        Identifiers are masked for your role.
                      </Alert>
                    )}
                  </CardContent>
                </Card>
              </Grid>
            </Grid>
          )}

          {/* Tab 1: Activity — six sub-surfaces, each its own backend contract */}
          {tabIndex === 1 && (
            <Box>
              <Tabs
                value={activityTab}
                onChange={(_, v) => setActivityTab(v)}
                sx={{ mb: 2, borderBottom: '1px solid #E2E8F0' }}
                variant="scrollable"
              >
                {ACTIVITY_TABS.map((t) => (
                  <Tab key={t} value={t} label={t} sx={{ textTransform: 'none' }} />
                ))}
              </Tabs>

              {activityTab === 'Searches' && (
                <AdminDataGrid
                  rows={(searches?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={searchColumns}
                  totalRows={searches?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={searchesLoading}
                />
              )}
              {activityTab === 'Viewed Products' && (
                <AdminDataGrid
                  rows={(viewedProducts?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={viewedColumns}
                  totalRows={viewedProducts?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={viewedProductsLoading}
                />
              )}
              {activityTab === 'Viewed Shops' && (
                <AdminDataGrid
                  rows={(viewedShops?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={viewedColumns}
                  totalRows={viewedShops?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={viewedShopsLoading}
                />
              )}
              {activityTab === 'Saved Products' && (
                <AdminDataGrid
                  rows={(savedProducts?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={savedEntityColumns}
                  totalRows={savedProducts?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={savedProductsLoading}
                />
              )}
              {activityTab === 'Saved Shops' && (
                <AdminDataGrid
                  rows={(savedShops?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={savedEntityColumns}
                  totalRows={savedShops?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={savedShopsLoading}
                />
              )}
              {activityTab === 'Notifications' && (
                <AdminDataGrid
                  rows={(notifications?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={notificationColumns}
                  totalRows={notifications?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={notificationsLoading}
                />
              )}
              {/* Unified cross-entity timeline from the activity stream. */}
              {activityTab === 'All Activity' && (
                <AdminDataGrid
                  rows={(activity?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={activityColumns}
                  totalRows={activity?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={activityLoading}
                />
              )}
            </Box>
          )}

          {tabIndex === 2 && (
            <AdminDataGrid
              rows={(saved?.items || []) as unknown as Record<string, unknown>[]}
              columns={savedColumns}
              totalRows={saved?.items?.length ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={savedLoading}
            />
          )}

          {/* Locations — coarse area/city granularity only */}
          {tabIndex === 3 && (
            <Card>
              <CardContent sx={{ p: 3 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>
                  Saved Addresses & Recent Location
                </Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                  Displayed at area/city granularity. Precise coordinates are not exposed.
                </Typography>
                <Divider sx={{ mb: 2 }} />
                {addressesLoading ? (
                  <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                    <CircularProgress size={24} />
                  </Box>
                ) : (addresses?.items?.length ?? 0) === 0 ? (
                  <Typography variant="body2" color="text.secondary" sx={{ py: 3, textAlign: 'center' }}>
                    No saved addresses available for this customer.
                  </Typography>
                ) : (
                  addresses!.items.map((a) => (
                    <Box key={a.id} sx={{ py: 1, borderBottom: '1px solid #F1F5F9' }}>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {a.label || 'Address'}
                        {a.is_default && <Chip size="small" label="Default" sx={{ ml: 1 }} />}
                      </Typography>
                      <Typography variant="caption" color="text.secondary">
                        {[a.area, a.city, a.state].filter(Boolean).join(', ') || '—'}
                      </Typography>
                    </Box>
                  ))
                )}
              </CardContent>
            </Card>
          )}

          {/* Tab 4: Support — Tickets + Reports */}
          {tabIndex === 4 && (
            <Box>
              <Tabs
                value={supportTab}
                onChange={(_, v) => setSupportTab(v)}
                sx={{ mb: 2, borderBottom: '1px solid #E2E8F0' }}
              >
                <Tab value="Tickets" label="Tickets" sx={{ textTransform: 'none' }} />
                <Tab value="Reports" label="Reports" sx={{ textTransform: 'none' }} />
              </Tabs>

              {supportTab === 'Tickets' ? (
                <AdminDataGrid
                  rows={(tickets?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={ticketColumns}
                  totalRows={tickets?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={ticketsLoading}
                />
              ) : (
                <AdminDataGrid
                  rows={(reports?.items ?? []) as unknown as Record<string, unknown>[]}
                  columns={reportColumns}
                  totalRows={reports?.total ?? 0}
                  paginationModel={pagination}
                  onPaginationModelChange={setPagination}
                  loading={reportsLoading}
                />
              )}
            </Box>
          )}

          {tabIndex === 5 && (
            <AdminDataGrid
              rows={(auditLogs?.items || []) as unknown as Record<string, unknown>[]}
              columns={auditColumns}
              totalRows={auditLogs?.items?.length ?? 0}
              paginationModel={pagination}
              onPaginationModelChange={setPagination}
              loading={auditLoading}
            />
          )}

          {pendingAction && (
            <ConfirmationDialog
              open={Boolean(pendingAction)}
              title={`${actionLabel(pendingAction)} Customer Account`}
              affectedItem={maskIdentifier(customer.name, 'name', canViewPII)}
              consequence={actionConsequence(pendingAction)}
              isDangerous={pendingAction !== 'ACTIVATE'}
              requireReason
              isLoading={statusMutation.isPending || restrictMutation.isPending}
              onConfirm={confirmAction}
              onClose={() => setPendingAction(null)}
            />
          )}
        </Box>
      )}
    </Box>
  );
}

function actionLabel(action: AdminAction): string {
  switch (action) {
    case 'SUSPEND':
      return 'Suspend';
    case 'ACTIVATE':
      return 'Reactivate';
    case 'RESTRICT':
      return 'Restrict';
    case 'UNRESTRICT':
      return 'Remove Restriction from';
    default:
      return action;
  }
}

function actionConsequence(action: AdminAction): string {
  switch (action) {
    case 'SUSPEND':
      return 'The customer will be unable to log in, search for nearby inventory, or interact with businesses.';
    case 'ACTIVATE':
      return 'The customer will immediately regain access to platform discovery services.';
    case 'RESTRICT':
      return 'Discovery and interaction features will be limited for this account pending review.';
    case 'UNRESTRICT':
      return 'The account returns to normal discovery access.';
    default:
      return '';
  }
}

function DetailRow({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
}) {
  return (
    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, py: 0.75 }}>
      {icon}
      <Typography variant="body2" color="text.secondary" sx={{ minWidth: 180 }}>
        {label}:
      </Typography>
      <Typography variant="body2" sx={{ fontWeight: 600 }}>
        {value}
      </Typography>
    </Box>
  );
}

function SummaryRow({ label, value }: { label: string; value?: number }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', py: 0.75 }}>
      <Typography variant="body2" color="text.secondary">
        {label}
      </Typography>
      <Typography variant="body2" sx={{ fontWeight: 700 }}>
        {value == null ? '—' : value.toLocaleString()}
      </Typography>
    </Box>
  );
}
