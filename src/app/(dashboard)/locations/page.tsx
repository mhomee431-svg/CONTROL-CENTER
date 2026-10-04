'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button } from '@mui/material';
import { useRouter } from 'next/navigation';
import { MapPin } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ShopItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function LocationsPage() {
  const router = useRouter();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const { data, isLoading, refetch } = useQuery<{ items: ShopItem[]; total: number }>({
    queryKey: ['admin', 'locations', paginationModel],
    queryFn: () =>
      apiClient<{ items: ShopItem[]; total: number }>(API_ENDPOINTS.SHOPS.LIST, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'Shop ID', width: 90 },
    { field: 'name', headerName: 'Shop Name', flex: 1.5, minWidth: 180 },
    { field: 'city', headerName: 'City', flex: 1, minWidth: 130 },
    { field: 'state', headerName: 'State', flex: 1, minWidth: 130 },
    { field: 'category', headerName: 'Category', flex: 1, minWidth: 140 },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Locations' },
        ]}
      />
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 3, flexWrap: 'wrap', gap: 2 }}>
        <Box>
          <Typography variant="h5" sx={{ fontWeight: 700 }}>
            Location Coverage Registry
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Geographic distribution of onboarded shops, cities, and regional coverage gaps.
          </Typography>
        </Box>
        <Button variant="outlined" onClick={() => router.push(ROUTES.LOCATIONS_MAP)}>
          Open Map View →
        </Button>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search locations..."
        onRefresh={() => refetch()}
        onRowClick={(params) => router.push(ROUTES.BUSINESS_DETAIL(params.row.id as number))}
      />
    </Box>
  );
}
