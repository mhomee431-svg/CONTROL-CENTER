'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Divider, Alert, CircularProgress, Button, Typography } from '@mui/material';
import { Store, Phone, Mail, Calendar, ArrowLeft } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminUserItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function ShopkeeperDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data: shopkeeper, isLoading, isError } = useQuery<AdminUserItem | null>({
    queryKey: ['admin', 'shopkeepers', id],
    queryFn: async () => {
      const res = await apiClient<{ items: AdminUserItem[] }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: { role: 'shopkeeper', search: id, limit: 1 },
      });
      return res.items?.[0] || null;
    },
  });

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Shopkeepers', href: ROUTES.SHOPKEEPERS },
          { label: shopkeeper?.name ? shopkeeper.name : `Shopkeeper #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.SHOPKEEPERS)} sx={{ mb: 2 }}>
        Back to Shopkeepers
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && (
        <Alert severity="error">Could not load shopkeeper #{id}.</Alert>
      )}

      {shopkeeper && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <Store size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {shopkeeper.name || 'Registered Shopkeeper'}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Shopkeeper ID: #{shopkeeper.id}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={shopkeeper.status} size="medium" />
            </Box>

            <Divider sx={{ my: 2 }} />

            <DetailRow icon={<Phone size={16} color="#64748B" />} label="Phone" value={shopkeeper.phone || 'Not provided'} />
            <DetailRow icon={<Mail size={16} color="#64748B" />} label="Email" value={shopkeeper.email || 'Not provided'} />
            <DetailRow
              icon={<Calendar size={16} color="#64748B" />}
              label="Registered"
              value={shopkeeper.created_at ? new Date(shopkeeper.created_at).toLocaleString() : 'N/A'}
            />
          </CardContent>
        </Card>
      )}
    </Box>
  );
}

function DetailRow({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, py: 0.75 }}>
      {icon}
      <Typography variant="body2" color="text.secondary">
        {label}:
      </Typography>
      <Typography variant="body2" sx={{ fontWeight: 600 }}>
        {value}
      </Typography>
    </Box>
  );
}
