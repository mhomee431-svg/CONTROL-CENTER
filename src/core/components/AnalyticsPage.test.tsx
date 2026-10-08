import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { ThemeProvider } from '@mui/material/styles';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { theme } from '@/core/theme/theme';
import { AnalyticsPage, AnalyticsPageProps } from './AnalyticsPage';
import { DateRangeProvider } from '@/core/filters/DateRangeContext';

vi.mock('next/link', () => ({
  default: ({ children }: { children: React.ReactNode }) => children,
}));

function renderPage(props: Partial<AnalyticsPageProps> = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const full: AnalyticsPageProps = {
    title: 'Test Section',
    description: 'desc',
    kpis: [],
    chartTitle: 'Trend',
    chartData: [],
    chartKey: 'search:volume',
    isLoading: false,
    isError: false,
    ...props,
  };
  return render(
    <QueryClientProvider client={client}>
      <ThemeProvider theme={theme}>
        <DateRangeProvider>
          <AnalyticsPage {...full} />
        </DateRangeProvider>
      </ThemeProvider>
    </QueryClientProvider>
  );
}

describe('AnalyticsPage — shared section renderer', () => {
  it('renders KPI values and the shared date-range control', async () => {
    renderPage({
      kpis: [{ label: 'NEW CUSTOMERS', value: 42, color: '#000' }],
      chartTitle: 'Registrations by Day',
    });

    await waitFor(() => {
      expect(screen.getByText('NEW CUSTOMERS')).toBeInTheDocument();
      expect(screen.getByText('42')).toBeInTheDocument();
      expect(screen.getByText('Date Range')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Custom Range' })).toBeInTheDocument();
    });
  });

  it('renders a null metric as "Not collected", never as zero', async () => {
    renderPage({
      kpis: [{ label: 'DIRECTIONS', value: null, color: '#000' }],
    });

    await waitFor(() => {
      expect(screen.getByText('Not collected')).toBeInTheDocument();
    });
  });

  it('withholds figures on error rather than reporting zero', async () => {
    renderPage({
      isError: true,
      kpis: [{ label: 'COVERED CITIES', value: 0, color: '#000' }],
    });

    await waitFor(() => {
      // The error alert is shown and the value is replaced with an explicit
      // "Unavailable" state, so a failure is never mistaken for zero coverage.
      expect(
        screen.getByText(/This analytics endpoint is unavailable/i)
      ).toBeInTheDocument();
      expect(screen.getAllByText('Unavailable').length).toBeGreaterThan(0);
      expect(screen.queryByText('0')).not.toBeInTheDocument();
    });
  });

  it('renders breakdown lists with their values', async () => {
    renderPage({
      breakdowns: [
        {
          title: 'Shop Density by City',
          items: [
            { label: 'Mumbai', value: 12 },
            { label: 'Pune', value: 4 },
          ],
        },
      ],
    });

    await waitFor(() => {
      expect(screen.getByText('Shop Density by City')).toBeInTheDocument();
      expect(screen.getByText('Mumbai')).toBeInTheDocument();
      expect(screen.getByText('12')).toBeInTheDocument();
      expect(screen.getByText('Pune')).toBeInTheDocument();
    });
  });

  it('shows an empty state when a breakdown has no rows', async () => {
    renderPage({
      breakdowns: [
        { title: 'Top Merchants', items: [], emptyText: 'No merchants with storefronts yet.' },
      ],
    });

    await waitFor(() => {
      expect(screen.getByText('No merchants with storefronts yet.')).toBeInTheDocument();
    });
  });

  it('renders a chart only when the dataset earns one by policy', async () => {
    // A key mapped in the policy renders its chart; a key with no mapping
    // renders no chart at all — a number that is not a trend must not become
    // a chart for its own sake.
    const charted = renderPage({ chartKey: 'search:volume', chartData: [{ label: 'Mon', value: 4 }] });
    await waitFor(() => expect(charted.container.querySelectorAll('svg').length).toBeGreaterThan(0));

    const uncharted = renderPage({ chartKey: 'not-in-policy', chartData: [{ label: 'Mon', value: 4 }] });
    await waitFor(() =>
      expect(uncharted.getByText(/No trend data available for this window/i)).toBeInTheDocument()
    );
  });
});
