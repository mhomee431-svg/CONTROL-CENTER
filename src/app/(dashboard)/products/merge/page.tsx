'use client';

import React, { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Box, Typography, Button, Card, CardContent, Grid, TextField, Alert } from '@mui/material';
import { GitMerge } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ProductItem } from '@/core/types/admin';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { DetailField } from '@/core/components/BusinessDetailParts';

/**
 * PRODUCT MERGE WORKFLOW — Candidate A + Candidate B -> Compare -> Review ->
 * Confirm Merge. HIGH-RISK: confirm posts winner + loser + mandatory reason.
 */
interface ComparePayload {
  candidate_a: ProductItem & { variants?: Array<{ id: number | string; name?: string | null; sku?: string | null; barcode?: string | null }> };
  candidate_b: ProductItem & { variants?: Array<{ id: number | string; name?: string | null; sku?: string | null; barcode?: string | null }> };
}

function CandidateCard({ title, p }: { title: string; p: ComparePayload['candidate_a'] | null }) {
  if (!p) return null;
  return (
    <Card>
      <CardContent>
        <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>{title}: {p.name}</Typography>
        <DetailField label="Brand" value={p.brand_name} />
        <DetailField label="Category" value={p.category_name} />
        <DetailField label="Barcode" value={p.barcode} mono />
        <DetailField label="Status" value={p.status} />
        <DetailField label="Stocking shops" value={p.shop_count} />
      </CardContent>
    </Card>
  );
}

export default function ProductMergePage() {
  const queryClient = useQueryClient();
  const [idA, setIdA] = useState('');
  const [idB, setIdB] = useState('');
  const [winnerId, setWinnerId] = useState<number | null>(null);
  const [compare, setCompare] = useState<ComparePayload | null>(null);
  const [compareError, setCompareError] = useState<string | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const compareMutation = useMutation({
    mutationFn: (body: { product_a_id: number; product_b_id: number }) =>
      apiClient<ComparePayload>(API_ENDPOINTS.PRODUCTS.MERGE_COMPARE, { method: 'POST', body: JSON.stringify(body) }),
    onSuccess: (data) => { setCompare(data); setCompareError(null); setWinnerId(null); },
    onError: (err: unknown) => setCompareError(err instanceof Error ? err.message : 'Compare failed'),
  });
  const mergeMutation = useMutation({
    mutationFn: (body: { winner_id: number; loser_id: number; reason: string }) =>
      apiClient(API_ENDPOINTS.PRODUCTS.MERGE_CONFIRM, { method: 'POST', body: JSON.stringify(body) }),
    onSuccess: () => {
      setConfirmOpen(false); setCompare(null); setWinnerId(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'products'] });
    },
  });
  const loserId = compare && winnerId != null
    ? (winnerId === compare.candidate_a.id ? compare.candidate_b.id : compare.candidate_a.id)
    : null;
  return (
    <Box>
      <DrillDownBreadcrumbs items={[{ label: 'Dashboard', href: ROUTES.DASHBOARD }, { label: 'Products', href: ROUTES.PRODUCTS }, { label: 'Merge' }]} />
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>Product Merge Workflow</Typography>
        <Typography variant="body2" color="text.secondary">Compare two candidates, pick the winner, then confirm with a recorded reason. High-risk: the loser is archived.</Typography>
      </Box>
      <Card sx={{ mb: 2 }}>
        <CardContent sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center' }}>
          <TextField size="small" label="Candidate A ID" value={idA} onChange={(e) => setIdA(e.target.value)} sx={{ width: 160 }} />
          <TextField size="small" label="Candidate B ID" value={idB} onChange={(e) => setIdB(e.target.value)} sx={{ width: 160 }} />
          <Button variant="outlined" disabled={compareMutation.isPending || !idA || !idB}
            onClick={() => compareMutation.mutate({ product_a_id: Number(idA), product_b_id: Number(idB) })}>
            {compareMutation.isPending ? 'Comparing…' : 'Compare'}
          </Button>
        </CardContent>
      </Card>
      {compareError && (<Alert severity="error" sx={{ mb: 2 }}>{compareError}</Alert>)}
      {compare && (
        <>
          <Grid container spacing={2} sx={{ mb: 2 }}>
            <Grid item xs={12} md={6}>
              <CandidateCard title="Candidate A" p={compare.candidate_a} />
              <Button fullWidth sx={{ mt: 1 }} variant={winnerId === compare.candidate_a.id ? 'contained' : 'outlined'}
                color="success" onClick={() => setWinnerId(compare.candidate_a.id)}>Keep A</Button>
            </Grid>
            <Grid item xs={12} md={6}>
              <CandidateCard title="Candidate B" p={compare.candidate_b} />
              <Button fullWidth sx={{ mt: 1 }} variant={winnerId === compare.candidate_b.id ? 'contained' : 'outlined'}
                color="success" onClick={() => setWinnerId(compare.candidate_b.id)}>Keep B</Button>
            </Grid>
          </Grid>
          <PermissionGuard capability={CAPABILITIES.PRODUCTS_MERGE}>
            <Button variant="contained" color="error" startIcon={<GitMerge size={16} />} disabled={winnerId == null}
              onClick={() => setConfirmOpen(true)}>Review - Confirm Merge</Button>
          </PermissionGuard>
        </>
      )}
      {confirmOpen && winnerId != null && loserId != null && (
        <ConfirmationDialog
          open
          title={`Confirm Merge — keep #${winnerId}, archive #${loserId}`}
          affectedItem={`Winner #${winnerId} absorbs loser #${loserId}`}
          consequence="Variants and inventory re-point at the winner; the loser is archived, never deleted."
          isDangerous
          requireReason
          isLoading={mergeMutation.isPending}
          onConfirm={async (reason) => { await mergeMutation.mutateAsync({ winner_id: winnerId, loser_id: loserId, reason }); }}
          onClose={() => setConfirmOpen(false)}
        />
      )}
    </Box>
  );
}
