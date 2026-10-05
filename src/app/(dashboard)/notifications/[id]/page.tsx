'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
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
  LinearProgress,
} from '@mui/material';
import { ArrowLeft, Bell, Link2, ShieldCheck, ShieldAlert, Users, CheckCircle2, XCircle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { NotificationCampaignItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { validateExplicitUrl } from '@/core/notifications/deepLink';

export default function NotificationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data, isLoading, isError } = useQuery<NotificationCampaignItem>({
    queryKey: ['admin', 'campaign', id],
    queryFn: () => apiClient<NotificationCampaignItem>(API_ENDPOINTS.NOTIFICATIONS.CAMPAIGN_DETAIL(id)),
    retry: false,
  });

  // A stored deep link is re-validated on read too: never render an unvalidated
  // link as clickable, even if it was persisted by an older client version.
  const linkCheck = data?.deep_link ? validateExplicitUrl(data.deep_link) : null;

  const total = data?.recipients_total ?? 0;
  const sent = data?.recipients_sent ?? 0;
  const failed = data?.recipients_failed ?? 0;
  const deliveryRate = total > 0 ? Math.round((sent / total) * 100) : 0;

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

      {isError && (
        <Alert severity="error">
          Could not load campaign #{id}. The notification campaign endpoint may not be available on this backend.
        </Alert>
      )}

      {!isLoading && data && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <Bell size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {data.title || `Notification Campaign #${id}`}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    {String(data.notification_type || 'BROADCAST').replace(/_/g, ' ')} · Audience:{' '}
                    {String(data.audience || 'all').toUpperCase()}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={data.status || 'SENT'} size="medium" />
            </Box>

            {data.body && (
              <>
                <Divider sx={{ my: 2 }} />
                <Typography variant="caption" color="text.secondary">
                  Message Body
                </Typography>
                <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap', mb: 1 }}>
                  {data.body}
                </Typography>
              </>
            )}

            <Divider sx={{ my: 2 }} />

            <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748B', letterSpacing: '0.04em' }}>
              DELIVERY PERFORMANCE
            </Typography>
            <Grid container spacing={2} sx={{ mt: 0.5, mb: 1 }}>
              <Grid item xs={12} sm={4}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Users size={16} color="#64748B" />
                  <Box>
                    <Typography variant="caption" color="text.secondary">
                      Total Recipients
                    </Typography>
                    <Typography variant="body2" sx={{ fontWeight: 700 }}>
                      {total || 'N/A'}
                    </Typography>
                  </Box>
                </Box>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <CheckCircle2 size={16} color="#10B981" />
                  <Box>
                    <Typography variant="caption" color="text.secondary">
                      Delivered
                    </Typography>
                    <Typography variant="body2" sx={{ fontWeight: 700 }}>
                      {sent}
                    </Typography>
                  </Box>
                </Box>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <XCircle size={16} color="#EF4444" />
                  <Box>
                    <Typography variant="caption" color="text.secondary">
                      Failed
                    </Typography>
                    <Typography variant="body2" sx={{ fontWeight: 700 }}>
                      {failed}
                    </Typography>
                  </Box>
                </Box>
              </Grid>
            </Grid>
            {total > 0 && (
              <Box sx={{ mt: 1 }}>
                <LinearProgress variant="determinate" value={deliveryRate} sx={{ height: 8, borderRadius: 4 }} />
                <Typography variant="caption" color="text.secondary">
                  {deliveryRate}% delivery rate
                </Typography>
              </Box>
            )}

            <Divider sx={{ my: 2 }} />

            <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748B', letterSpacing: '0.04em' }}>
              DEEP LINK
            </Typography>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mt: 1, flexWrap: 'wrap' }}>
              {linkCheck ? (
                <>
                  <Chip
                    size="small"
                    icon={linkCheck.valid ? <ShieldCheck size={14} /> : <ShieldAlert size={14} />}
                    color={linkCheck.valid ? 'success' : 'error'}
                    variant="outlined"
                    label={linkCheck.valid ? 'Validated' : 'Blocked'}
                  />
                  <Chip
                    size="small"
                    icon={<Link2 size={14} />}
                    label={linkCheck.valid ? linkCheck.path : data.deep_link}
                    variant="outlined"
                    color={linkCheck.valid ? 'primary' : 'default'}
                  />
                </>
              ) : (
                <Typography variant="body2" color="text.secondary">
                  No deep link attached to this campaign.
                </Typography>
              )}
            </Box>

            <Divider sx={{ my: 2 }} />

            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Created
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {data.created_at ? new Date(data.created_at).toLocaleString() : 'N/A'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Sent
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {data.sent_at ? new Date(data.sent_at).toLocaleString() : 'Not yet sent'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Dispatched By
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {data.sent_by || 'Platform'}
                </Typography>
              </Grid>
            </Grid>
          </CardContent>
        </Card>
      )}

      {!isLoading && !data && !isError && (
        <Alert severity="warning">Campaign #{id} was not found.</Alert>
      )}
    </Box>
  );
}
