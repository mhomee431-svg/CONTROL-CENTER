'use client';

import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { Box, Typography, Grid, Card, CardContent, Chip, Alert, CircularProgress } from '@mui/material';
import { Activity, Database, Server, Zap } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { DashboardMetrics } from '@/core/types/admin';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { useRealtimeEvents } from '@/core/realtime/useRealtimeEvents';
import { ROUTES } from '@/core/routes/routes';

export default function SystemHealthPage() {
  const { data, isLoading, isError } = useQuery<DashboardMetrics>({
    queryKey: ['admin', 'dashboard', 'metrics'],
    queryFn: () => apiClient<DashboardMetrics>(API_ENDPOINTS.DASHBOARD.METRICS),
  });

  // Realtime Stream status is derived from the shared live transport rather than
  // being asserted as always operational.
  const { transport } = useRealtimeEvents();
  const realtimeStatus = transport === 'offline' ? 'UNKNOWN' : 'OPERATIONAL';

  const services = [
    { name: 'Admin API', icon: <Server size={18} />, status: isError ? 'DOWN' : 'OPERATIONAL' },
    { name: 'Database Layer', icon: <Database size={18} />, status: isError ? 'UNKNOWN' : 'OPERATIONAL' },
    { name: 'Realtime Stream', icon: <Zap size={18} />, status: realtimeStatus },
    { name: 'Search Index', icon: <Activity size={18} />, status: isError ? 'UNKNOWN' : 'OPERATIONAL' },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'System', href: ROUTES.SETTINGS },
          { label: 'Health' },
        ]}
      />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          System Health Monitor
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Live status of platform services and critical dependencies.
        </Typography>
      </Box>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Admin API unreachable. Some health signals cannot be verified.
        </Alert>
      )}

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        {services.map((s) => (
          <Grid item xs={12} sm={6} md={3} key={s.name}>
            <Card>
              <CardContent sx={{ p: 2.5 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                  <Box sx={{ color: '#0F52BA' }}>{s.icon}</Box>
                  <Chip
                    size="small"
                    label={s.status}
                    color={s.status === 'OPERATIONAL' ? 'success' : s.status === 'DOWN' ? 'error' : 'default'}
                    sx={{ fontWeight: 700, fontSize: '0.6875rem' }}
                  />
                </Box>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {s.name}
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      {data && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 2 }}>
              Operational Signals
            </Typography>
            <Grid container spacing={2}>
              <Signal label="Inventory Sync Failures" value={data.sync_failures} danger />
              <Signal label="Stale Inventory Records" value={data.stale_inventory_count} danger />
              <Signal label="Total Inventory Records" value={data.total_inventory_records} />
              <Signal label="Search Success Rate" value={`${data.search_success_rate}%`} />
            </Grid>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}

function Signal({ label, value, danger }: { label: string; value: number | string; danger?: boolean }) {
  return (
    <Grid item xs={12} sm={6} md={3}>
      <Typography variant="caption" color="text.secondary">
        {label}
      </Typography>
      <Typography variant="h5" sx={{ fontWeight: 700, color: danger ? 'error.main' : 'text.primary' }}>
        {typeof value === 'number' ? value.toLocaleString() : value}
      </Typography>
    </Grid>
  );
}
