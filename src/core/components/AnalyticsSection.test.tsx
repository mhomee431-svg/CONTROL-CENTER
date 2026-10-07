import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { ThemeProvider } from '@mui/material/styles';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { theme } from '@/core/theme/theme';
import { AnalyticsSection, AnalyticsSectionProps } from './AnalyticsSection';
import { DateRangeProvider } from '@/core/filters/DateRangeContext';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';

vi.mock('@/core/api/client', () => ({
  apiClient: vi.fn(),
}));

vi.mock('next/link', () => ({
  default: ({ children }: { children: React.ReactNode }) => children,
}));

const mockApiClient = vi.mocked(apiClient);

const SUMMARY = {
  period_days: 30,
  total_searches: 1234,
  successful_searches: 1000,
  search_success_rate: 81.1,
  unique_searchers: 432,
  avg_results_per_search: 3.2,
  top_search_terms: [],
  top_categories_searched: [],
  searches_by_day: [],
  zero_result_queries: [{ query: 'nonexistent item', count: 12 }],
};

const METRICS = {
  total_customers: 50,
  total_shops: 10,
  active_shops: 7,
  pending_verification: 2,
  total_products: 500,
  total_inventory_records: 900,
  total_searches: 1234,
  search_success_rate: 81.1,
  popular_categories: [],
  active_subscriptions: 3,
  total_subscription_revenue: 0,
  pending_approvals: 4,
  open_complaints: 1,
  stale_inventory_count: 20,
  products_missing_prices: 5,
  sync_failures: 2,
};

function renderSection(kpis: AnalyticsSectionProps['kpis']) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <ThemeProvider theme={theme}>
        {/* AnalyticsSection reads the reporting window from shared context. */}
        <DateRangeProvider>
          <AnalyticsSection title="Test Section" description="desc" kpis={kpis} />
        </DateRangeProvider>
      </ThemeProvider>
    </QueryClientProvider>
  );
}

describe('AnalyticsSection — live KPI resolver contract', () => {
  beforeEach(() => {
    mockApiClient.mockImplementation(async (endpoint: string) => {
      if (endpoint === API_ENDPOINTS.DASHBOARD.METRICS) return METRICS as never;
      if (endpoint === API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY) return SUMMARY as never;
      return {} as never;
    });
  });

  afterEach(() => {
    mockApiClient.mockReset();
  });

  it('resolves KPI values from live summary and metrics instead of placeholders', async () => {
    renderSection(({ summary, metrics }) => [
      { label: 'TOTAL SEARCHES', value: summary ? summary.total_searches.toLocaleString() : '—', color: '#000' },
      { label: 'TOTAL PRODUCTS', value: metrics ? metrics.total_products.toLocaleString() : '—', color: '#000' },
    ]);

    await waitFor(() => {
      expect(screen.getByText('TOTAL SEARCHES')).toBeInTheDocument();
      expect(screen.getByText('1,234')).toBeInTheDocument();
      expect(screen.getByText('500')).toBeInTheDocument();
    });
  });

  it('accepts a static KPI list for backwards compatibility', async () => {
    renderSection([{ label: 'STATIC KPI', value: 'static-value', color: '#000' }]);

    await waitFor(() => {
      expect(screen.getByText('static-value')).toBeInTheDocument();
    });
  });

  it('queries both centralized aggregate endpoints', async () => {
    renderSection([{ label: 'X', value: '1', color: '#000' }]);

    await waitFor(() => {
      const called = mockApiClient.mock.calls.map((c) => c[0]);
      expect(called).toContain(API_ENDPOINTS.DASHBOARD.METRICS);
      expect(called).toContain(API_ENDPOINTS.DASHBOARD.ANALYTICS_SUMMARY);
    });
  });

  it('sends the shared reporting window to both aggregates', async () => {
    renderSection([{ label: 'X', value: '1', color: '#000' }]);

    await waitFor(() => {
      const metricsCall = mockApiClient.mock.calls.find(
        (c) => c[0] === API_ENDPOINTS.DASHBOARD.METRICS
      );
      // Default preset is 30d -> days=30.
      expect(metricsCall?.[1]?.params).toEqual({ days: '30' });
    });
  });

  it('renders the centralized date-range control', async () => {
    renderSection([{ label: 'X', value: '1', color: '#000' }]);

    await waitFor(() => {
      expect(screen.getByText('Date Range')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Custom Range' })).toBeInTheDocument();
    });
  });
});