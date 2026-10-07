'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Alert,
  Grid,
  Divider,
  Chip,
  CircularProgress,
} from '@mui/material';
import { ArrowLeft, MessageSquare, Check, EyeOff, Flag, Star } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ReviewItem, REVIEW_DECISIONS, ReviewDecision } from '@/core/types/reviews';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import {
  canApplyDecision,
  decisionCopy,
  displayRating,
  reportCount,
  resolveReviewState,
  requiresReason,
} from '@/core/reviews/moderation';

export default function ReviewDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();
  const queryClient = useQueryClient();

  const [pendingDecision, setPendingDecision] = useState<ReviewDecision | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const { data: review, isLoading, isError } = useQuery<ReviewItem>({
    queryKey: ['admin', 'review', id],
    queryFn: () => apiClient<ReviewItem>(API_ENDPOINTS.REVIEWS.DETAIL(id)),
    retry: false,
  });

  const moderateMutation = useMutation({
    mutationFn: ({ decision, reason }: { decision: string; reason: string }) =>
      apiClient(API_ENDPOINTS.REVIEWS.MODERATE(id), {
        method: 'POST',
        body: JSON.stringify({ decision, reason }),
      }),
    onSuccess: () => {
      setPendingDecision(null);
      setActionError(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'review', id] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'reviews'] });
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Moderation action failed.'),
  });

  const state = resolveReviewState(review);
  const stars = displayRating(review);
  const available = review ? (Object.values(REVIEW_DECISIONS) as ReviewDecision[]).filter((d) => canApplyDecision(d, review)) : [];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Reviews', href: ROUTES.REVIEWS },
          { label: review?.entity_name ? `${review.entity_name} review` : `Review #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.REVIEWS)} sx={{ mb: 2 }}>
        Back to Reviews
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Could not load review #{id}. The reviews endpoint may not be available on this backend.
        </Alert>
      )}

      {actionError && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setActionError(null)}>
          {actionError}
        </Alert>
      )}

      {!isLoading && review && (
        <>
          <Card sx={{ mb: 2 }}>
            <CardContent sx={{ p: 3 }}>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 2 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                  <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#EFF6FF', color: 'primary.main' }}>
                    <MessageSquare size={24} />
                  </Box>
                  <Box>
                    <Typography variant="h6" sx={{ fontWeight: 700 }}>
                      {review.entity_name || `Review #${review.id}`}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      {review.entity_type || 'REVIEW'} · by {review.reviewer_name || `user #${review.reviewer_id ?? 'unknown'}`}
                    </Typography>
                  </Box>
                </Box>
                <StatusBadge status={state} size="medium" />
              </Box>

              <Divider sx={{ my: 2 }} />

              {/* Rating + reports at a glance */}
              <Grid container spacing={2}>
                <Grid item xs={12} sm={4}>
                  <Typography variant="caption" color="text.secondary">
                    Rating
                  </Typography>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                    <Star size={16} color="#F59E0B" />
                    <Typography variant="body2" sx={{ fontWeight: 700 }}>
                      {stars ? `${stars} / 5` : 'Not rated'}
                    </Typography>
                  </Box>
                </Grid>
                <Grid item xs={12} sm={4}>
                  <Typography variant="caption" color="text.secondary">
                    Reports
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 700, color: reportCount(review) > 0 ? 'error.main' : 'text.primary' }}>
                    {reportCount(review)}
                  </Typography>
                </Grid>
                <Grid item xs={12} sm={4}>
                  <Typography variant="caption" color="text.secondary">
                    Submitted
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {review.created_at ? new Date(review.created_at).toLocaleString() : 'N/A'}
                  </Typography>
                </Grid>
              </Grid>

              <Divider sx={{ my: 2 }} />

              {review.title && (
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                  {review.title}
                </Typography>
              )}
              <Typography variant="body2" sx={{ whiteSpace: 'pre-wrap' }}>
                {review.body || '(No review body)'}
              </Typography>

              {review.report_reasons && review.report_reasons.length > 0 && (
                <>
                  <Divider sx={{ my: 2 }} />
                  <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748B', letterSpacing: '0.04em' }}>
                    REPORT REASONS
                  </Typography>
                  <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mt: 1 }}>
                    {review.report_reasons.map((r, idx) => (
                      <Chip
                        key={`${r.reason}-${idx}`}
                        size="small"
                        label={r.count ? `${r.reason} ×${r.count}` : r.reason}
                        color="error"
                        variant="outlined"
                      />
                    ))}
                  </Box>
                  <Divider sx={{ my: 2 }} />
                </>
              )}

              {review.moderation_notes && (
                <>
                  <Typography variant="caption" color="text.secondary">
                    Prior moderation note
                  </Typography>
                  <Typography variant="body2" sx={{ fontWeight: 600 }}>
                    {review.moderation_notes}
                  </Typography>
                </>
              )}
            </CardContent>
          </Card>

          {/* Moderation actions — HIDE and ESCALATE need a reason; there is no delete. */}
          <Card>
            <CardContent sx={{ p: 2.5 }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
                Moderation Actions
              </Typography>
              <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
                {available.map((decision) => (
                  <PermissionGuard key={decision} capability={CAPABILITIES.REVIEWS_MODERATE}>
                    <Button
                      variant={decision === REVIEW_DECISIONS.HIDE ? 'outlined' : 'contained'}
                      color={decision === REVIEW_DECISIONS.HIDE ? 'warning' : 'primary'}
                      startIcon={
                        decision === REVIEW_DECISIONS.KEEP ? (
                          <Check size={15} />
                        ) : decision === REVIEW_DECISIONS.HIDE ? (
                          <EyeOff size={15} />
                        ) : (
                          <Flag size={15} />
                        )
                      }
                      onClick={() => setPendingDecision(decision)}
                    >
                      {decisionCopy(decision).title}
                    </Button>
                  </PermissionGuard>
                ))}
              </Box>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>
                Hiding is reversible. Reviews are never permanently deleted from this console.
              </Typography>
            </CardContent>
          </Card>
        </>
      )}

      {/* Reason-capturing confirmation for each decision */}
      <ConfirmationDialog
        open={pendingDecision !== null}
        title={pendingDecision ? decisionCopy(pendingDecision).title : 'Moderate Review'}
        affectedItem={review?.entity_name || `Review #${id}`}
        consequence={pendingDecision ? decisionCopy(pendingDecision).consequence : undefined}
        isDangerous={pendingDecision ? decisionCopy(pendingDecision).dangerous : false}
        requireReason={pendingDecision ? requiresReason(pendingDecision) : true}
        isLoading={moderateMutation.isPending}
        onConfirm={async (reason) => {
          if (!pendingDecision) return;
          await moderateMutation.mutateAsync({ decision: pendingDecision, reason });
        }}
        onClose={() => setPendingDecision(null)}
      />
    </Box>
  );
}