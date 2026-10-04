'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Divider, Alert, CircularProgress, Grid, Chip } from '@mui/material';
import { ArrowLeft, ShieldCheck } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminUserItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';

export default function AdminUserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data, isLoading, isError } = useQuery<{ items: AdminUserItem[] }>({
    queryKey: ['admin', 'admin-users', 'all'],
    queryFn: () =>
      apiClient<{ items: AdminUserItem[] }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: { role: 'admin', limit: 250 },
      }),
  });

  const admin = data?.items?.find((u) => String(u.id) === String(id));

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Admin Users', href: ROUTES.ADMIN_USERS },
          { label: admin?.name || `Admin #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.ADMIN_USERS)} sx={{ mb: 2 }}>
        Back to Admin Users
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load administrator #{id}.</Alert>}
      {!isLoading && !admin && <Alert severity="warning">Administrator #{id} was not found.</Alert>}

      {admin && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <ShieldCheck size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {admin.name || 'Administrator'}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Admin ID: #{admin.id}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={admin.status} size="medium" />
            </Box>
            <Divider sx={{ my: 2 }} />
            <Grid container spacing={2}>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Role
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {admin.role}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Phone
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {admin.phone || 'Not provided'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={4}>
                <Typography variant="caption" color="text.secondary">
                  Registered
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {admin.created_at ? new Date(admin.created_at).toLocaleString() : 'N/A'}
                </Typography>
              </Grid>
            </Grid>

            <Divider sx={{ my: 2 }} />

            {/* Sensitive: role/permission change is a protected operation */}
            <PermissionGuard capability={CAPABILITIES.ADMINS_ROLES_MANAGE}>
              <Box>
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1 }}>
                  Role & Permission Management
                </Typography>
                <Chip
                  label="Change Role / Permissions"
                  color="primary"
                  clickable
                  onClick={() => router.push(ROUTES.ADMIN_USER_DETAIL(admin.id))}
                />
              </Box>
            </PermissionGuard>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
