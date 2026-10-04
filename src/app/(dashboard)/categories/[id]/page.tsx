'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Divider, Alert, CircularProgress, Grid } from '@mui/material';
import { ArrowLeft, Layers } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { CategoryItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function CategoryDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data, isLoading, isError } = useQuery<{ items: CategoryItem[] }>({
    queryKey: ['admin', 'categories'],
    queryFn: () => apiClient<{ items: CategoryItem[] }>(API_ENDPOINTS.CATEGORIES.LIST),
  });

  const category = data?.items?.find((c) => String(c.id) === String(id));

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Categories', href: ROUTES.CATEGORIES },
          { label: category?.name || `Category #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.CATEGORIES)} sx={{ mb: 2 }}>
        Back to Categories
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load category #{id}.</Alert>}
      {!isLoading && !category && <Alert severity="warning">Category #{id} was not found in the taxonomy.</Alert>}

      {category && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                  <Layers size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {category.name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Slug: {category.slug}
                  </Typography>
                </Box>
              </Box>
              <StatusBadge status={category.is_active ? 'ACTIVE' : 'INACTIVE'} size="medium" />
            </Box>
            <Divider sx={{ my: 2 }} />
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Description
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {category.description || 'No description provided'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={3}>
                <Typography variant="caption" color="text.secondary">
                  Sort Order
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {category.sort_order}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={3}>
                <Typography variant="caption" color="text.secondary">
                  Subcategory
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {category.is_subcategory ? 'Yes' : 'No'}
                </Typography>
              </Grid>
            </Grid>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
