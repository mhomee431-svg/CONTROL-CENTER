'use client';

import React, { use } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Alert, CircularProgress, Divider, Grid } from '@mui/material';
import { ArrowLeft, Bell } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AuditLogItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function NotificationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();

  // Campaign detail resolved from the same authoritative action trail that
  // backs the campaign registry, so the drill-down shows real records.
  const { data, isLoading, isError } = useQuery<{ items: AuditLogItem[] }>({
    queryKey: ['admin', 'campaigns', 'detail', id],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[] }>(API_ENDPOINTS.AUDIT.ACTIONS, {
        params: { entity_type: 'notification', limit: 250 },
      }),
  });

  const campaign = data?.items?.find((c) => String(c.id) === String(id));
  const detailTitle =
    (campaign?.details?.title as string | undefined) ?? (campaign?.details?.subject as string | undefined);

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Notifications', href: ROUTES.NOTIFICATIONS },
          { label: `Campaign #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.NOTIFICATION_CAMPAIGNS)} sx={{ mb: 2 }}>
        Back to Campaigns
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load campaign #{id}.</Alert>}
      {!isLoading && !isError && !campaign && (
        <Alert severity="warning">Campaign #{id} was not found in the broadcast history.</Alert>
      )}

      {campaign && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <Bell size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {detailTitle || campaign.action || `Notification Campaign #${campaign.id}`}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Campaign #{campaign.id}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={campaign.action || 'SENT'} size="medium" />
            </Box>

            <Divider sx={{ my: 2 }} />

            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Action
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {campaign.action || 'Unknown'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Entity Type
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {campaign.entity_type || 'notification'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Issued By
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {campaign.admin_user || (campaign.user_id ? `User #${campaign.user_id}` : 'System')}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Created At
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {campaign.created_at ? new Date(campaign.created_at).toLocaleString() : 'N/A'}
                </Typography>
              </Grid>
            </Grid>

            {campaign.details && Object.keys(campaign.details).length > 0 && (
              <>
                <Divider sx={{ my: 2 }} />
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1 }}>
                  Campaign Payload
                </Typography>
                <Box
                  component="pre"
                  sx={{
                    m: 0,
                    p: 2,
                    backgroundColor: '#F8FAFC',
                    border: '1px solid #E2E8F0',
                    borderRadius: 2,
                    fontSize: '0.75rem',
                    overflowX: 'auto',
                    whiteSpace: 'pre-wrap',
                    wordBreak: 'break-word',
                  }}
                >
                  {JSON.stringify(campaign.details, null, 2)}
                </Box>
              </>
            )}

            <Alert severity="info" sx={{ mt: 2.5 }}>
              Device-level delivery metrics are emitted by the backend notifications pipeline. The record above is
              served by the authoritative admin action trail.
            </Alert>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
