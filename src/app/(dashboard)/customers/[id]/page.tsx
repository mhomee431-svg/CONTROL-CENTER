'use client';

import React, { use } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Grid,
  Button,
  Divider,
  Alert,
  CircularProgress,
} from '@mui/material';
import { ArrowLeft, User, Phone, Calendar, Shield } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminUserItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';

export default function CustomerDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const resolvedParams = use(params);
  const router = useRouter();
  const customerId = resolvedParams.id;

  const { data: customer, isLoading, isError } = useQuery<AdminUserItem>({
    queryKey: ['admin', 'customers', customerId],
    queryFn: async () => {
      const res = await apiClient<{ items: AdminUserItem[] }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: { search: customerId, limit: 1 },
      });
      return res.items?.[0] || null;
    },
  });

  return (
    <Box>
      <Button
        startIcon={<ArrowLeft size={16} />}
        onClick={() => router.push('/customers')}
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

      {customer && (
        <Grid container spacing={3}>
          {/* Main Info */}
          <Grid item xs={12} md={8}>
            <Card>
              <CardContent sx={{ p: 3 }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                    <Box
                      sx={{
                        width: 48,
                        height: 48,
                        borderRadius: 2,
                        backgroundColor: '#EFF6FF',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        color: 'primary.main',
                      }}
                    >
                      <User size={24} />
                    </Box>
                    <Box>
                      <Typography variant="h6" sx={{ fontWeight: 700 }}>
                        {customer.name || 'Anonymous Customer'}
                      </Typography>
                      <Typography variant="body2" color="text.secondary">
                        Customer ID: #{customer.id}
                      </Typography>
                    </Box>
                  </Box>
                  <StatusBadge status={customer.status} size="medium" />
                </Box>

                <Divider sx={{ my: 2 }} />

                <Grid container spacing={2}>
                  <Grid item xs={12} sm={6}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                      <Phone size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Phone:
                      </Typography>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {customer.phone || 'Not provided'}
                      </Typography>
                    </Box>
                  </Grid>

                  <Grid item xs={12} sm={6}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                      <Calendar size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Registered:
                      </Typography>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {customer.created_at ? new Date(customer.created_at).toLocaleString() : 'N/A'}
                      </Typography>
                    </Box>
                  </Grid>

                  <Grid item xs={12} sm={6}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                      <Shield size={16} color="#64748B" />
                      <Typography variant="body2" color="text.secondary">
                        Account Role:
                      </Typography>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {customer.role}
                      </Typography>
                    </Box>
                  </Grid>
                </Grid>
              </CardContent>
            </Card>
          </Grid>

          {/* Privacy & Governance notice */}
          <Grid item xs={12} md={4}>
            <Card>
              <CardContent sx={{ p: 2.5 }}>
                <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1 }}>
                  Privacy & Data Governance
                </Typography>
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 2 }}>
                  Section 22: Passwords, OTPs, and authentication tokens are strictly protected by the backend
                  and never rendered in the Admin Control Center.
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      )}
    </Box>
  );
}
