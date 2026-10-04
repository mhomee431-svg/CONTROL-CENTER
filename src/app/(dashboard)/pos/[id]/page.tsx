'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { Box, Card, CardContent, Button, Typography, Alert } from '@mui/material';
import { ArrowLeft, Plug } from 'lucide-react';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function PosDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'POS', href: ROUTES.POS },
          { label: `Integration #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.POS)} sx={{ mb: 2 }}>
        Back to POS Integrations
      </Button>

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 2 }}>
            <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
              <Plug size={24} />
            </Box>
            <Typography variant="h6" sx={{ fontWeight: 700 }}>
              POS Integration #{id}
            </Typography>
          </Box>
          <Alert severity="info">
            Detailed POS sync logs and SKU mapping are provided by the backend integration endpoint.
          </Alert>
        </CardContent>
      </Card>
    </Box>
  );
}
