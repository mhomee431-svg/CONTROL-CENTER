'use client';

import { createTheme } from '@mui/material/styles';

/**
 * Module augmentation so `MuiDataGrid` is accepted in the theme's `components`
 * map. @mui/x-data-grid ships DataGrid styleOverrides, but the key is not part
 * of Material UI's own Components type, so it must be declared here.
 */
declare module '@mui/material/styles' {
  interface Components {
    MuiDataGrid?: {
      styleOverrides?: Record<string, unknown>;
    };
  }
}

/**
 * Section 129: Centralized Admin Design System
 * Visual Direction: Deep blue, electric blue, white, light gray, green, orange, red for destructive errors.
 */
export const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#0F52BA', // Deep sapphire electric blue
      light: '#3B82F6',
      dark: '#0A2540',
      contrastText: '#FFFFFF',
    },
    secondary: {
      main: '#6366F1', // Indigo accent
      light: '#818CF8',
      dark: '#4338CA',
      contrastText: '#FFFFFF',
    },
    background: {
      default: '#F8FAFC', // Slate 50
      paper: '#FFFFFF',
    },
    text: {
      primary: '#0F172A', // Slate 900
      secondary: '#475569', // Slate 600
    },
    error: {
      main: '#EF4444',
      light: '#F87171',
      dark: '#B91C1C',
    },
    warning: {
      main: '#F59E0B',
      light: '#FBBF24',
      dark: '#B45309',
    },
    info: {
      main: '#0284C7',
      light: '#38BDF8',
      dark: '#0369A1',
    },
    success: {
      main: '#10B981',
      light: '#34D399',
      dark: '#047857',
    },
    divider: '#E2E8F0',
  },
  typography: {
    fontFamily: [
      '-apple-system',
      'BlinkMacSystemFont',
      '"Segoe UI"',
      'Roboto',
      '"Helvetica Neue"',
      'Arial',
      'sans-serif',
    ].join(','),
    h5: {
      fontWeight: 600,
      letterSpacing: '-0.02em',
    },
    h6: {
      fontWeight: 600,
      letterSpacing: '-0.01em',
    },
    subtitle1: {
      fontSize: '0.95rem',
      fontWeight: 500,
    },
    subtitle2: {
      fontSize: '0.85rem',
      fontWeight: 600,
      textTransform: 'uppercase',
      letterSpacing: '0.05em',
    },
    body1: {
      fontSize: '0.875rem',
    },
    body2: {
      fontSize: '0.8125rem',
    },
    button: {
      textTransform: 'none',
      fontWeight: 600,
    },
  },
  shape: {
    borderRadius: 8,
  },
  components: {
    MuiButton: {
      styleOverrides: {
        root: {
          borderRadius: 8,
          boxShadow: 'none',
          '&:hover': {
            boxShadow: 'none',
          },
        },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          borderRadius: 12,
          border: '1px solid #E2E8F0',
          boxShadow: '0 1px 3px 0 rgb(0 0 0 / 0.05)',
        },
      },
    },
    MuiPaper: {
      styleOverrides: {
        root: {
          backgroundImage: 'none',
        },
      },
    },
    MuiDataGrid: {
      styleOverrides: {
        // Drill-down highlight: /shopkeepers?highlight=123 marks the row via
        // cellClassName. Without this rule the class was emitted but inert,
        // so drilling from a shop/inventory record silently did nothing.
        '.highlighted-row': {
          backgroundColor: '#DBEAFE',
          fontWeight: 700,
          '&:hover': {
            backgroundColor: '#BFDBFE',
          },
        },
      },
    },
  },
});
