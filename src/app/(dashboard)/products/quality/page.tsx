'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, FormControl, InputLabel, Select, MenuItem, Alert } from '@mui/material';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';


/**
 * PRODUCT QUALITY CONTROL — duplicate candidates, missing images / brand /
 * category, invalid barcodes, unmatched identifiers, inactive products,
 * products with no shop, and suspicious data.
 */
interface QualityRow {
  key: string;
  check: string;
  title: string;
  product_id: number;
  product_name: string;
  detail: string;
}

const CHECKS = [
  { value: '', label: 'All Checks' },
  { value: 'duplicates', label: 'Duplicate candidates' },
  { value: 'missing-images', label: 'Missing images' },
  { value: 'missing-brand', label: 'Missing brand' },
  { value: 'missing-category', label: 'Missing category' },
  { value: 'invalid-barcode', label: 'Invalid barcode' },
  { value: 'unmatched-identifiers', label: 'Unmatched identifiers' },
  { value: 'inactive', label: 'Inactive products' },
  { value: 'no-shop', label: 'Products with no shop' },
  { value: 'suspicious', label: 'Suspicious data' },
];

export default function ProductQualityPage() {
  const router = useRouter();
  const [pm, setPm] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [checkFilter, setCheckFilter] = useState('');
  const { data, isLoading, isError, refetch } = useQuery<{ items: QualityRow[]; total: number }>({
    queryKey: ['admin', 'products', 'quality', { page: pm.page, pageSize: pm.pageSize, check: checkFilter }],
    queryFn: () =>
      apiClient<{ items: QualityRow[]; total: number }>(API_ENDPOINTS.PRODUCTS.QUALITY, {
        params: { check: checkFilter || undefined, limit: pm.pageSize, offset: pm.page * pm.pageSize },
      }),
  });
  const rows = (data?.items || []).map((r) => ({ ...r, id: r.key }));
  const columns: GridColDef[] = [
    { field: 'check', headerName: 'Check', width: 180 },
    { field: 'product_name', headerName: 'Product', flex: 1.4, minWidth: 200 },
    { field: 'product_id', headerName: 'ID', width: 80 },
    { field: 'detail', headerName: 'Finding', flex: 2, minWidth: 260 },
  ];
  return (
    <Box>
      <DrillDownBreadcrumbs items={[{ label: 'Dashboard', href: ROUTES.DASHBOARD }, { label: 'Products', href: ROUTES.PRODUCTS }, { label: 'Quality Control' }]} />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>Product Quality Control</Typography>
        <Typography variant="body2" color="text.secondary">Catalog-hygiene findings across the nine spec checks. Click a row to open the product.</Typography>
      </Box>
      <Box sx={{ mb: 2, display: 'flex', gap: 2 }}>
        <FormControl size="small" sx={{ minWidth: 220 }}>
          <InputLabel>Check</InputLabel>
          <Select value={checkFilter} label="Check" onChange={(e) => { setCheckFilter(e.target.value); setPm((m) => ({ ...m, page: 0 })); }}>
            {CHECKS.map((o) => (<MenuItem key={o.value} value={o.value}>{o.label}</MenuItem>))}
          </Select>
        </FormControl>
      </Box>
      {isError && (<Alert severity="error" sx={{ mb: 2 }}>Quality findings could not be loaded. Retry, and escalate if it keeps failing.</Alert>)}
      <AdminDataGrid
        rows={rows as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={pm}
        onPaginationModelChange={setPm}
        loading={isLoading}
        onRefresh={() => refetch()}
        error={isError}
        errorMessage="The quality findings could not be loaded."
        onRowClick={(params) => router.push(ROUTES.PRODUCT_DETAIL(params.row.product_id as number))}
      />
    </Box>
  );
}
