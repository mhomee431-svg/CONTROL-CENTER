'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { Box, Card, CardContent, Button, Typography, Alert } from '@mui/material';
import { ArrowLeft, Bell } from 'lucide-react';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function NotificationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

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

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 2 }}>
            <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
              <Bell size={24} />
            </Box>
            <Typography variant="h6" sx={{ fontWeight: 700 }}>
              Notification Campaign #{id}
            </Typography>
          </Box>
          <Alert severity="info">
            Campaign delivery metrics and device-level results are served by the backend notifications endpoint.
          </Alert>
        </CardContent>
      </Card>
    </Box>
  );
}
