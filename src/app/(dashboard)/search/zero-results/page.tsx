'use client';

import React, { useState } from 'react';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import { Box, Typography, Button, Alert } from '@mui/material';
import { AlertCircle, ExternalLink } from 'lucide-react';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';

interface ZeroResultItem {
  id: number;
  query: string;
  search_count: number;
  location: string;
  potential_category: string;
  last_searched: string;
}

export default function ZeroResultsPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  // Real backend search failure mock fallback when backend contract exposes it
  const sampleItems: ZeroResultItem[] = [
    {
      id: 1,
      query: 'bosch drill 10mm',
      search_count: 184,
      location: 'South Delhi, 110017',
      potential_category: 'Hardware',
      last_searched: new Date().toISOString(),
    },
    {
      id: 2,
      query: 'paracetamol 650mg strip',
      search_count: 142,
      location: 'Noida Sector 62',
      potential_category: 'Pharmacy & Healthcare',
      last_searched: new Date().toISOString(),
    },
    {
      id: 3,
      query: 'castrol magnatec 5w30 4l',
      search_count: 98,
      location: 'Gurugram Sector 29',
      potential_category: 'Automotive Parts & Tools',
      last_searched: new Date().toISOString(),
    },
  ];

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 70 },
    {
      field: 'query',
      headerName: 'Searched Term',
      flex: 1.5,
      minWidth: 180,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <AlertCircle size={16} color="#EF4444" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            &quot;{params.value as string}&quot;
          </Typography>
        </Box>
      ),
    },
    {
      field: 'search_count',
      headerName: 'Search Volume (0 Results)',
      width: 220,
      align: 'right',
      headerAlign: 'right',
      valueFormatter: (value) => `${Number(value).toLocaleString()} queries`,
    },
    { field: 'location', headerName: 'Shopper Location Area', flex: 1.2, minWidth: 160 },
    { field: 'potential_category', headerName: 'Likely Taxonomy', flex: 1, minWidth: 140 },
    {
      field: 'actions',
      headerName: 'Operational Actions',
      width: 200,
      sortable: false,
      renderCell: () => (
        <Button size="small" variant="outlined" startIcon={<ExternalLink size={14} />}>
          Review Catalog Gap
        </Button>
      ),
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Zero-Result Search Analysis
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 42: High customer demand with zero local stock. Identify merchant onboarding gaps and catalog deficiencies.
        </Typography>
      </Box>

      <Alert severity="info" sx={{ mb: 2 }}>
        These queries returned 0 nearby shops. Review these gaps to onboard target merchants or expand the canonical catalog.
      </Alert>

      <AdminDataGrid
        rows={sampleItems as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={sampleItems.length}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
      />
    </Box>
  );
}
