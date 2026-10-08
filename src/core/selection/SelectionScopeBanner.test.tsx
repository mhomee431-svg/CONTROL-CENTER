import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ThemeProvider } from '@mui/material/styles';
import { theme } from '@/core/theme/theme';
import { SelectionScopeBanner } from './SelectionScopeBanner';

/**
 * The banner is the last line of defence before a bulk action fires: it must
 * state the scope in words, and it must warn when the selection is off-screen.
 */
function renderBanner(props: Partial<Parameters<typeof SelectionScopeBanner>[0]> = {}) {
  return render(
    <ThemeProvider theme={theme}>
      <SelectionScopeBanner
        mode="explicit"
        count={3}
        matchingCount={null}
        pageRowCount={25}
        offPageCount={0}
        onClear={() => { }}
        {...props}
      />
    </ThemeProvider>
  );
}

describe('SelectionScopeBanner', () => {
  it('renders nothing when nothing is selected', () => {
    const { container } = renderBanner({ mode: 'none' });
    expect(container.textContent).toBe('');
  });

  it('states the explicit scope in words', () => {
    renderBanner({ mode: 'explicit', count: 3 });
    expect(screen.getByText(/Bulk actions will apply to 3 selected records\./)).toBeInTheDocument();
  });

  it('singularises a single selected record', () => {
    renderBanner({ mode: 'explicit', count: 1 });
    expect(screen.getByText(/1 selected record\./)).toBeInTheDocument();
  });

  it('makes the all-matching scale explicit against the page size', () => {
    renderBanner({ mode: 'all-matching', count: 0, matchingCount: 5000, pageRowCount: 25 });
    expect(
      screen.getByText(/ALL 5,000 records matching the current query — not just the 25 on this page\./)
    ).toBeInTheDocument();
  });

  it('warns when selected records are not on the visible page', () => {
    renderBanner({ mode: 'explicit', count: 4, offPageCount: 4 });
    expect(screen.getByText(/4 selected records\./)).toBeInTheDocument();
    expect(
      screen.getByText(/4 of the selected records are not on this page\./)
    ).toBeInTheDocument();
  });

  it('offers a clear-selection escape hatch', () => {
    renderBanner();
    expect(screen.getByRole('button', { name: /clear selection/i })).toBeInTheDocument();
  });
});
