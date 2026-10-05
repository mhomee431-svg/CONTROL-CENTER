'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Alert,
  Grid,
  Divider,
  Chip,
  CircularProgress,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  Paper,
} from '@mui/material';
import {
  ArrowLeft,
  Plug,
  RefreshCw,
  PlugZap,
  Unplug,
  AlertTriangle,
  CheckCircle2,
  XCircle,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ROUTES } from '@/core/routes/routes';
import { PosIntegrationItem, providerDisplayName } from '@/core/types/pos';
import {
  canDisconnect,
  canReconnect,
  canTriggerSync,
  declaredCapabilities,
  formatSyncAge,
  hoursSinceSync,
  isStale,
  isSyncing,
  normalizePosStatus,
  toSyncRows,
  totalSynced,
} from '@/core/pos/connection';

export default function PosDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();
  const queryClient = useQueryClient();

  const [actionError, setActionError] = useState<string | null>(null);
  const [pendingAction, setPendingAction] = useState<'SYNC' | 'RECONNECT' | 'DISCONNECT' | null>(null);

  const { data: integration, isLoading, isError } = useQuery<PosIntegrationItem>({
    queryKey: ['admin', 'pos-integration', id],
    queryFn: () => apiClient<PosIntegrationItem>(API_ENDPOINTS.POS.DETAIL(id)),
    retry: false,
    refetchInterval: (query) => {
      const current = query.state.data as PosIntegrationItem | undefined;
      return current && isSyncing(current) ? 5000 : false;
    },
  });

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ['admin', 'pos-integration', id] });
    queryClient.invalidateQueries({ queryKey: ['admin', 'pos'] });
  };

  const runAction = (endpoint: string, reason: string) =>
    apiClient(endpoint, { method: 'POST', body: JSON.stringify({ reason }) });

  const syncMutation = useMutation({
    mutationFn: (reason: string) => runAction(API_ENDPOINTS.POS.SYNC(id), reason),
    onSuccess: () => {
      setPendingAction(null);
      setActionError(null);
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Sync request failed.'),
  });

  const reconnectMutation = useMutation({
    mutationFn: (reason: string) => runAction(API_ENDPOINTS.POS.RECONNECT(id), reason),
    onSuccess: () => {
      setPendingAction(null);
      setActionError(null);
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Reconnect failed.'),
  });

  const disconnectMutation = useMutation({
    mutationFn: (reason: string) => runAction(API_ENDPOINTS.POS.DISCONNECT(id), reason),
    onSuccess: () => {
      setPendingAction(null);
      setActionError(null);
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Disconnect failed.'),
  });

  const status = integration ? normalizePosStatus(integration.status) : 'UNKNOWN';
  const rows = toSyncRows(integration);
  const stale = integration ? isStale(integration) && !isSyncing(integration) : false;

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'POS Control Center', href: ROUTES.POS },
          { label: integration?.shop_name || `Integration #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.POS)} sx={{ mb: 2 }}>
        Back to POS Control Center
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Could not load POS integration #{id}. The integrations endpoint may not be available on this backend.
        </Alert>
      )}

      {actionError && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setActionError(null)}>
          {actionError}
        </Alert>
      )}

      {!isLoading && integration && (
        <>
          <Card sx={{ mb: 2 }}>
            <CardContent sx={{ p: 3 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#F5F3FF', color: '#8B5CF6' }}>
                    <Plug size={24} />
                  </Box>
                  <Box>
                    <Typography variant="h6" sx={{ fontWeight: 700 }}>
                      {integration.shop_name || (integration.shop_id ? `Shop #${integration.shop_id}` : 'POS Integration')}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      Provider: {providerDisplayName(integration)}
                    </Typography>
                  </Box>
                </Box>
                <StatusBadge status={integration.status || 'DISCONNECTED'} size="medium" />
              </Box>

              {integration.error_message && (
                <Alert severity={status === 'SYNC_FAILED' ? 'error' : 'warning'} sx={{ mb: 2 }}>
                  <strong>{status === 'SYNC_FAILED' ? 'Last sync failed: ' : 'Integration notice: '}</strong>
                  {integration.error_message}
                </Alert>
              )}

              {stale && (
                <Alert severity="warning" icon={<AlertTriangle size={18} />} sx={{ mb: 2 }}>
                  Data may be out of date — last successful sync {formatSyncAge(integration)}
                </Alert>
              )}

              <Divider sx={{ my: 2 }} />

              <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748B', letterSpacing: '0.04em' }}>
                DECLARED CAPABILITIES
              </Typography>
              <Box sx={{ display: 'flex', gap: 1, mt: 1, flexWrap: 'wrap' }}>
                {declaredCapabilities(integration).map((cap) => (
                  <Chip key={cap} size="small" label={cap} color="primary" variant="outlined" />
                ))}
                {declaredCapabilities(integration).length === 0 && (
                  <Typography variant="body2" color="text.secondary">
                    No capabilities reported by the backend for this integration.
                  </Typography>
                )}
              </Box>

              <Divider sx={{ my: 2 }} />
              <Grid container spacing={2}>
                <Grid item xs={12} sm={6}>
                  <Typography variant="caption" color="text.secondary">
                    Last Sync
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {integration.last_sync_at
                      ? new Date(integration.last_sync_at).toLocaleString()
                      : 'Never synced'}
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={6}>
                  <Typography variant="caption" color="text.secondary">
                    Connected Since
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {integration.connected_at ? new Date(integration.connected_at).toLocaleString() : 'Unknown'}
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={6}>
                  <Typography variant="caption" color="text.secondary">
                    Products Synced (cumulative)
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {integration.products_synced ?? 'N/A'}
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={6}>
                  <Typography variant="caption" color="text.secondary">
                    Inventory Synced (cumulative)
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {integration.inventory_synced ?? 'N/A'}
                  </Typography>
                </Grid>
              </Grid>
            </CardContent>
          </Card>

          {/* Actions */}
          <Card sx={{ mb: 2 }}>
            <CardContent sx={{ p: 2.5 }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
                Actions
              </Typography>
              <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
                <PermissionGuard capability={CAPABILITIES.INVENTORY_UPDATE}>
                  <Button
                    variant="contained"
                    startIcon={<RefreshCw size={15} />}
                    onClick={() => setPendingAction('SYNC')}
                    disabled={!canTriggerSync(integration)}
                  >
                    Trigger Sync
                  </Button>
                </PermissionGuard>

                <PermissionGuard capability={CAPABILITIES.INVENTORY_UPDATE}>
                  <Button
                    variant="outlined"
                    startIcon={<PlugZap size={15} />}
                    onClick={() => setPendingAction('RECONNECT')}
                    disabled={!canReconnect(integration)}
                  >
                    Reconnect
                  </Button>
                </PermissionGuard>

                <PermissionGuard capability={CAPABILITIES.INVENTORY_UPDATE}>
                  <Button
                    variant="outlined"
                    color="error"
                    startIcon={<Unplug size={15} />}
                    onClick={() => setPendingAction('DISCONNECT')}
                    disabled={!canDisconnect(integration)}
                  >
                    Disconnect
                  </Button>
                </PermissionGuard>
              </Box>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                Controls shown depend on this integration&apos;s connection state and the capabilities its provider declares.
              </Typography>
            </CardContent>
          </Card>

          {/* Per-capability sync breakdown */}
          <Card>
            <CardContent sx={{ p: 3 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 1 }}>
                <Typography variant="h6" sx={{ fontWeight: 700 }}>
                  Sync Breakdown
                </Typography>
                <Typography variant="body2" color="text.secondary">
                  {totalSynced(integration)} records in the latest run
                </Typography>
              </Box>

              {rows.length === 0 ? (
                <Alert severity="info">
                  This integration does not report per-capability sync results.
                </Alert>
              ) : (
                <Paper variant="outlined" sx={{ overflow: 'auto' }}>
                  <Table size="small">
                    <TableHead>
                      <TableRow sx={{ backgroundColor: '#F8FAFC' }}>
                        <TableCell sx={{ fontWeight: 700 }}>Capability</TableCell>
                        <TableCell sx={{ fontWeight: 700 }}>Status</TableCell>
                        <TableCell sx={{ fontWeight: 700 }} align="right">
                          Records
                        </TableCell>
                        <TableCell sx={{ fontWeight: 700 }}>Error</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {rows.map((row) => (
                        <TableRow key={row.id}>
                          <TableCell sx={{ fontWeight: 600 }}>{row.capability}</TableCell>
                          <TableCell>
                            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
                              {row.status === 'SUCCESS' ? (
                                <CheckCircle2 size={15} color="#10B981" />
                              ) : row.status === 'FAILED' ? (
                                <XCircle size={15} color="#EF4444" />
                              ) : (
                                <AlertTriangle size={15} color="#F59E0B" />
                              )}
                              <StatusBadge status={row.status} />
                            </Box>
                          </TableCell>
                          <TableCell align="right">
                            {row.records === null ? '—' : row.records}
                          </TableCell>
                          <TableCell>{row.error || '—'}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </Paper>
              )}
            </CardContent>
          </Card>
        </>
      )}

      {/* High-impact operations require an operator reason */}
      <ConfirmationDialog
        open={pendingAction === 'SYNC'}
        title="Trigger Manual Sync"
        affectedItem={integration?.shop_name || `Integration #${id}`}
        consequence="This requests a fresh catalog/inventory pull from the provider. Existing data may be overwritten."
        isLoading={syncMutation.isPending}
        onConfirm={async (reason) => {
          await syncMutation.mutateAsync(reason);
        }}
        onClose={() => setPendingAction(null)}
      />

      <ConfirmationDialog
        open={pendingAction === 'RECONNECT'}
        title="Reconnect Integration"
        affectedItem={integration?.shop_name || `Integration #${id}`}
        consequence="This re-establishes the provider link. Reconnection may require the merchant to re-authorise."
        isLoading={reconnectMutation.isPending}
        onConfirm={async (reason) => {
          await reconnectMutation.mutateAsync(reason);
        }}
        onClose={() => setPendingAction(null)}
      />

      <ConfirmationDialog
        open={pendingAction === 'DISCONNECT'}
        title="Disconnect Integration"
        affectedItem={integration?.shop_name || `Integration #${id}`}
        consequence="This severs the provider link. Product and inventory data will stop syncing and the shop's live catalog may become stale."
        isDangerous
        isLoading={disconnectMutation.isPending}
        onConfirm={async (reason) => {
          await disconnectMutation.mutateAsync(reason);
        }}
        onClose={() => setPendingAction(null)}
      />
    </Box>
  );
}
