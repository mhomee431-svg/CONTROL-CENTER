'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import {
  Box,
  Typography,
  Grid,
  Card,
  CardContent,
  Alert,
  CircularProgress,
  Chip,
  List,
  ListItem,
  ListItemText,
  Divider,
} from '@mui/material';
import { Search, AlertCircle, TrendingUp, BarChart2, Users, Timer, MousePointerClick } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { SearchControlSummary } from '@/core/types/searchControl';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { useDateRange } from '@/core/filters/DateRangeContext';
import { DateRangePicker } from '@/core/filters/DateRangePicker';

// ---------------------------------------------------------------------------
// Search Control Center — the hub.
// ---------------------------------------------------------------------------
// Tiles:     Search Volume | Success Rate | Zero-Result Rate | Avg Results |
//            Unique Searchers | Click Rate (not collected) | Latency (not
//            collected). Every number comes from /admin/search/summary; the
//            not-collected panels render "Not collected", never zero.
//
// Funnel:    Search Started → Search Submitted → Results Returned → Product
//            Opened (lifetime rollup) → Shop Opened (lifetime) → Directions
//            (not collected) → Saved (not collected).
// ---------------------------------------------------------------------------

/** KPI tile; a null value renders "—" with a not-collected hint. */
function Kpi({
  label,
  value,
  notCollected,
  icon,
}: {
  label: string;
  value: string | null | undefined;
  notCollected?: boolean;
  icon: React.ReactElement;
}) {
  return (
    <Grid item xs={12} sm={6} md={3}>
      <Card sx={{ height: '100%' }}>
        <CardContent sx={{ p: 2.5 }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Box>
              <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
                {label}
              </Typography>
              <Typography variant="h5" sx={{ fontWeight: 800, mt: 0.5 }}>
                {value ?? '—'}
              </Typography>
              {notCollected && (
                <Typography variant="caption" color="text.disabled">
                  Not collected
                </Typography>
              )}
            </Box>
            {icon}
          </Box>
        </CardContent>
      </Card>
    </Grid>
  );
}

/** One funnel stage; `scope` marks lifetime rollups. */
function FunnelStage({ label, value, scope }: { label: string; value: number | null; scope?: string }) {
  return (
    <Box sx={{ textAlign: 'center', minWidth: 110, px: 1 }}>
      <Typography variant="caption" color="text.secondary" sx={{ fontWeight: 600 }}>
        {label}
      </Typography>
      <Typography variant="h6" sx={{ fontWeight: 800 }}>
        {value ?? '—'}
      </Typography>
      {scope === 'lifetime' && (
        <Chip size="small" label="lifetime" sx={{ height: 18, fontSize: 10 }} />
      )}
      {value === null && (
        <Typography variant="caption" color="text.disabled" sx={{ display: 'block' }}>
          Not collected
        </Typography>
      )}
    </Box>
  );
}

export default function SearchAnalyticsPage() {
  const router = useRouter();
  const { params: dateParams } = useDateRange();

  const { data, isLoading, isError } = useQuery<SearchControlSummary>({
    queryKey: ['admin', 'search-control', 'summary', dateParams],
    queryFn: () =>
      apiClient<SearchControlSummary>(API_ENDPOINTS.SEARCH_CONTROL.SUMMARY, { params: dateParams }),
    retry: false,
  });

  const volume = data?.volume;
  const quality = data?.quality;
  const funnel = data?.funnel;
  const num = (v: number | null | undefined) => (v != null ? v.toLocaleString() : null);
  const pct = (v: number | null | undefined) => (v != null ? `${v}%` : null);


  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Search Control Center' },
        ]}
      />
      <DateRangePicker />

      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Search Control Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          The highest-priority discovery module: search volume, zero-result demand, funnel
          conversion and quality — all from recorded searches.
          {data ? ` Window: ${data.window_start} → ${data.window_end}.` : ''}
        </Typography>
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          The search control endpoint is unavailable. No metrics are shown because inventing
          search statistics would misdirect catalog decisions.
        </Alert>
      )}
      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 3 }}>
          <CircularProgress />
        </Box>
      )}

      {/* Quality tiles */}
      <Grid container spacing={2.5} sx={{ mb: 2 }}>
        <Kpi label="SEARCH VOLUME" value={num(volume?.total_searches)} icon={<BarChart2 size={22} color="#0F52BA" />} />
        <Kpi label="SUCCESS RATE" value={pct(quality?.success_rate)} icon={<TrendingUp size={22} color="#10B981" />} />
        <Kpi label="ZERO-RESULT RATE" value={pct(quality?.zero_result_rate)} icon={<AlertCircle size={22} color="#EF4444" />} />
        <Kpi label="AVG RESULTS / SEARCH" value={num(quality?.avg_result_count)} icon={<Search size={22} color="#8B5CF6" />} />
        <Kpi label="UNIQUE SEARCHERS" value={num(volume?.unique_searchers)} icon={<Users size={22} color="#F59E0B" />} />
        <Kpi label="CLICK RATE" value={null} notCollected icon={<MousePointerClick size={22} color="#94A3B8" />} />
        <Kpi label="LATENCY (P50)" value={null} notCollected icon={<Timer size={22} color="#94A3B8" />} />
      </Grid>

      {/* Funnel */}
      <Card sx={{ p: 3, mb: 3 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>
          Search Funnel
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          Every stage is a recorded figure or an honest “not collected” — no stage is estimated.
        </Typography>
        {funnel && (
          <Box sx={{ display: 'flex', alignItems: 'flex-start', gap: 1, flexWrap: 'wrap' }}>
            <FunnelStage label="Search Started" value={funnel.search_started} />
            <Typography sx={{ mt: 2 }}>↓</Typography>
            <FunnelStage label="Results Returned" value={funnel.results_returned} />
            <Typography sx={{ mt: 2 }}>↓</Typography>
            <FunnelStage label="Product Opened" value={funnel.product_opened} scope={funnel.product_opened_scope} />
            <Typography sx={{ mt: 2 }}>↓</Typography>
            <FunnelStage label="Shop Opened" value={funnel.shop_opened} scope={funnel.shop_opened_scope} />
            <Typography sx={{ mt: 2 }}>↓</Typography>
            <FunnelStage label="Directions Clicked" value={funnel.directions_clicked} />
            <Typography sx={{ mt: 2 }}>↓</Typography>
            <FunnelStage label="Saved" value={funnel.saved} />
          </Box>
        )}
      </Card>


      {/* Top searches + zero-result demand, side by side */}
      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        <Grid item xs={12} md={6}>
          <Card sx={{ height: '100%' }}>
            <CardContent sx={{ p: 3 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                Top Searches
              </Typography>
              {(data?.top_searches?.length ?? 0) === 0 ? (
                <Typography variant="body2" color="text.secondary">
                  No searches recorded in this window.
                </Typography>
              ) : (
                <List dense>
                  {data!.top_searches.slice(0, 8).map((t) => (
                    <ListItem key={t.term} divider>
                      <ListItemText
                        primary={t.term}
                        secondary={`${t.zero_count} zero-result · avg ${t.avg_result_count ?? '—'} results`}
                      />
                      <Chip size="small" label={t.count.toLocaleString()} color="primary" variant="outlined" />
                    </ListItem>
                  ))}
                </List>
              )}
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} md={6}>
          <Card sx={{ height: '100%' }}>
            <CardContent sx={{ p: 3 }}>
              <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 1 }}>
                Zero-Result Demand
              </Typography>
              {(data?.zero_result_queries?.length ?? 0) === 0 ? (
                <Typography variant="body2" color="text.secondary">
                  No zero-result queries in this window — a real finding, not an error.
                </Typography>
              ) : (
                <List dense>
                  {data!.zero_result_queries.slice(0, 8).map((q) => (
                    <ListItem key={q.query} divider>
                      <ListItemText
                        primary={`“${q.query}”`}
                        secondary={[q.location, q.first_seen ? q.first_seen.slice(0, 10) : null]
                          .filter(Boolean)
                          .join(' · ')}
                      />
                      <Chip size="small" label={q.count.toLocaleString()} color="error" variant="outlined" />
                    </ListItem>
                  ))}
                </List>
              )}
              <Divider sx={{ my: 1.5 }} />
              <Typography
                variant="body2"
                sx={{ cursor: 'pointer', fontWeight: 600, color: 'primary.main' }}
                onClick={() => router.push(ROUTES.SEARCH_ZERO_RESULTS)}
              >
                Investigate all zero-result queries →
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Sub-surface navigation */}
      <Grid container spacing={2.5}>
        {[
          { label: 'Zero-Result Searches', desc: 'Catalog gaps with real demand evidence.', href: ROUTES.SEARCH_ZERO_RESULTS },
          { label: 'Search Quality', desc: 'Per-term success and zero-result rates.', href: ROUTES.SEARCH_QUALITY },
          { label: 'Search Trends', desc: 'Daily volume with zero-result overlay.', href: ROUTES.SEARCH_TRENDS },
        ].map((card) => (
          <Grid item xs={12} md={4} key={card.href}>
            <Card
              sx={{ height: '100%', cursor: 'pointer', '&:hover': { boxShadow: 6 } }}
              onClick={() => router.push(card.href)}
            >
              <CardContent sx={{ p: 3 }}>
                <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
                  {card.label}
                </Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                  {card.desc}
                </Typography>
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>
    </Box>
  );
}

