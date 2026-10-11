'use client';

import React, { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Card,
  CardContent,
  Grid,
  Alert,
} from '@mui/material';
import { DollarSign, Tags, Percent, History as HistoryIcon } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { PriceSummary, PriceHistoryResponse } from '@/core/types/pricing';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';

/** Format a price as INR, or an em dash when the price is not recorded. */
function money(value: number | null | undefined): string {
  return value != null ? `₹${value.toLocaleString('en-IN', { maximumFractionDigits: 2 })}` : '—';
}

/** Format a share-of-base percentage, or an em dash when the base is empty. */
function pct(value: number | null): string {
  return value != null ? `${value}%` : '—';
}

/** Format an ISO timestamp as a locale string, or an em dash when absent. */
function when(iso: string | null | undefined): string {
  return iso ? new Date(iso).toLocaleString() : '—';
}

interface SummaryTileProps {
  label: string;
  value: string;
  sub: string;
  icon: React.ReactNode;
  color: string;
}

/**
 * One PRICE MANAGEMENT tile. The accent bar on the left matches the visual
 * language of the other control-center tiles, so the screen reads as part of
 * the console rather than a one-off.
 */
function SummaryTile({ label, value, sub, icon, color }: SummaryTileProps) {
  return (
    <Card sx={{ borderLeft: `4px solid ${color}`, height: '100%' }}>
      <CardContent sx={{ p: 2 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <Box>
            <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
              {label}
            </Typography>
            <Typography variant="h5" sx={{ fontWeight: 700, mt: 0.5 }}>
              {value}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              {sub}
            </Typography>
          </Box>
          <Box sx={{ color, mt: 0.5 }}>{icon}</Box>
        </Box>
      </CardContent>
    </Card>
  );
}


export default function PricingPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');

  const {
    data: summary,
    isLoading: summaryLoading,
    isError: summaryError,
  } = useQuery<PriceSummary>({
    queryKey: ['admin', 'pricing', 'summary'],
    queryFn: () => apiClient<PriceSummary>(API_ENDPOINTS.PRICING.SUMMARY),
  });

  const {
    data: history,
    isLoading: historyLoading,
    isError: historyError,
    refetch,
  } = useQuery<PriceHistoryResponse>({
    queryKey: ['admin', 'pricing', 'history', paginationModel.page, paginationModel.pageSize, search],
    queryFn: () =>
      apiClient<PriceHistoryResponse>(API_ENDPOINTS.PRICING.HISTORY, {
        params: {
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 90 },
    { field: 'shop_name', headerName: 'Shop', flex: 1.3, minWidth: 160, valueGetter: (_v, row) => row?.shop_name ?? '—' },
    { field: 'product_name', headerName: 'Product', flex: 1.5, minWidth: 180, valueGetter: (_v, row) => row?.product_name ?? '—' },
    {
      field: 'old_price',
      headerName: 'Old Price',
      width: 130,
      align: 'right',
      valueGetter: (_v, row) => money(row?.old_price),
    },
    {
      field: 'new_price',
      headerName: 'New Price',
      width: 130,
      align: 'right',
      valueGetter: (_v, row) => money(row?.new_price),
    },
    { field: 'changed_by', headerName: 'Changed By', flex: 1, minWidth: 140, valueGetter: (_v, row) => row?.changed_by ?? '—' },
    {
      field: 'changed_at',
      headerName: 'Changed At',
      width: 190,
      valueGetter: (_v, row) => when(row?.changed_at),
    },
    {
      field: 'source',
      headerName: 'Source',
      width: 150,
      renderCell: (params) => <StatusBadge status={(params.value as string) || 'UNKNOWN'} />,
    },
  ];

  const currency = summary?.currency ?? 'INR';

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Price Management
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Current, MRP and offer pricing across all shop inventories, with a full audit trail of every
          recorded price change.
        </Typography>
      </Box>

      {summaryError && (
        <Alert severity="error" sx={{ mb: 3 }}>
          Could not load the pricing summary. The price history table below may still be available.
        </Alert>
      )}

      {/* Summary tiles — Current Price, MRP, Offer Price, History */}
      <Grid container spacing={2.5} sx={{ mb: 1 }}>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryTile
            label="CURRENT PRICE"
            value={summaryLoading ? '…' : `${summary?.stats.current_price.count ?? 0}`}
            sub={summary ? `${pct(summary.stats.current_price.percent)} of priced base` : '—'}
            icon={<DollarSign size={22} />}
            color="#0F52BA"
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryTile
            label="MRP"
            value={summaryLoading ? '…' : `${summary?.stats.mrp.count ?? 0}`}
            sub={summary ? `${pct(summary.stats.mrp.percent)} of priced base` : '—'}
            icon={<Tags size={22} />}
            color="#10B981"
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryTile
            label="OFFER PRICE"
            value={summaryLoading ? '…' : `${summary?.stats.offer_price.count ?? 0}`}
            sub={summary ? `${pct(summary.stats.offer_price.percent)} below MRP` : '—'}
            icon={<Percent size={22} />}
            color="#F59E0B"
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryTile
            label="HISTORY"
            value={summaryLoading ? '…' : `${summary?.price_changes ?? 0}`}
            sub={summary ? `Last change ${when(summary.last_change_at)}` : '—'}
            icon={<HistoryIcon size={22} />}
            color="#6366F1"
          />
        </Grid>
      </Grid>

      {summary && (
        <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 3 }}>
          {summary.priced_items.toLocaleString('en-IN')} of {summary.total_items.toLocaleString('en-IN')} inventory
          rows carry a price ({currency}). Percentages are shares of the priced base.
        </Typography>
      )}

      <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1.5 }}>
        Price detail
      </Typography>

      <AdminDataGrid
        rows={(history?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={history?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={historyLoading}
        searchPlaceholder="Search by shop, product, or source..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={historyError}
        errorMessage="Could not load the price change history."
        gridId="pricing-history"
      />
    </Box>
  );
}

