import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ThemeProvider } from '@mui/material/styles';
import { theme } from '@/core/theme/theme';
import { StatusBadge } from './StatusBadge';

const renderWithTheme = (ui: React.ReactElement) =>
  render(<ThemeProvider theme={theme}>{ui}</ThemeProvider>);

describe('StatusBadge (Section 88 centralized status system)', () => {
  it('renders the normalized status text', () => {
    renderWithTheme(<StatusBadge status="active" />);
    expect(screen.getByText('ACTIVE')).toBeInTheDocument();
  });

  it('falls back to UNKNOWN for empty status', () => {
    renderWithTheme(<StatusBadge status="" />);
    expect(screen.getByText('UNKNOWN')).toBeInTheDocument();
  });

  it('maps positive statuses to success color', () => {
    const { container } = renderWithTheme(<StatusBadge status="VERIFIED" />);
    expect(container.querySelector('.MuiChip-colorSuccess')).toBeInTheDocument();
  });

  it('maps blocking statuses to error color', () => {
    const { container } = renderWithTheme(<StatusBadge status="SUSPENDED" />);
    expect(container.querySelector('.MuiChip-colorError')).toBeInTheDocument();
  });

  it('maps stale statuses to secondary color', () => {
    const { container } = renderWithTheme(<StatusBadge status="STALE" />);
    expect(container.querySelector('.MuiChip-colorSecondary')).toBeInTheDocument();
  });
});
