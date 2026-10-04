'use client';

import React from 'react';
import Link from 'next/link';
import Breadcrumbs from '@mui/material/Breadcrumbs';
import Typography from '@mui/material/Typography';
import MuiLink from '@mui/material/Link';
import NavigateNextIcon from '@mui/icons-material/NavigateNext';
import { Box } from '@mui/material';

export interface DrillDownCrumb {
  label: string;
  href?: string;
}

/**
 * Drill-down trail shared across all dashboard metric drill-downs.
 * Every major dashboard metric → list → entity → sub-record uses this
 * so no view in the control center is an orphan.
 */
export const DrillDownBreadcrumbs: React.FC<{ items: DrillDownCrumb[] }> = ({ items }) => {
  return (
    <Box sx={{ mb: 2 }}>
      <Breadcrumbs
        separator={<NavigateNextIcon fontSize="small" />}
        aria-label="drill-down breadcrumb"
        sx={{ '& .MuiBreadcrumbs-li': { fontSize: '0.8125rem' } }}
      >
        {items.map((item, idx) => {
          const isLast = idx === items.length - 1;
          if (item.href && !isLast) {
            return (
              <MuiLink
                key={idx}
                component={Link}
                href={item.href}
                underline="hover"
                color="inherit"
                sx={{ fontWeight: 500 }}
              >
                {item.label}
              </MuiLink>
            );
          }
          return (
            <Typography
              key={idx}
              color={isLast ? 'text.primary' : 'text.secondary'}
              sx={{ fontWeight: isLast ? 600 : 400, fontSize: '0.8125rem' }}
            >
              {item.label}
            </Typography>
          );
        })}
      </Breadcrumbs>
    </Box>
  );
};
