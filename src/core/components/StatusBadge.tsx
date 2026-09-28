'use client';

import React from 'react';
import { Chip, ChipProps } from '@mui/material';

export interface StatusBadgeProps {
  status: string;
  size?: 'small' | 'medium';
}

/**
 * Section 88: Centralized Status System
 * Single source of truth for semantic status colors across the application.
 */
export const StatusBadge: React.FC<StatusBadgeProps> = ({ status, size = 'small' }) => {
  const normalized = status ? status.toUpperCase() : 'UNKNOWN';

  let color: ChipProps['color'] = 'default';
  let label = normalized;

  switch (normalized) {
    case 'ACTIVE':
    case 'VERIFIED':
    case 'APPROVED':
    case 'SUCCESS':
    case 'RESOLVED':
    case 'COMPLETED':
      color = 'success';
      break;

    case 'PENDING':
    case 'UNDER_REVIEW':
    case 'IN_PROGRESS':
    case 'PROCESSING':
    case 'QUEUED':
      color = 'warning';
      break;

    case 'SUSPENDED':
    case 'BANNED':
    case 'REJECTED':
    case 'CANCELLED':
    case 'FAILED':
    case 'URGENT':
      color = 'error';
      break;

    case 'INACTIVE':
    case 'PAUSED':
    case 'DRAFT':
    case 'ARCHIVED':
    case 'CLOSED':
      color = 'default';
      break;

    case 'STALE':
    case 'ANOMALY':
      color = 'secondary';
      break;

    default:
      color = 'default';
  }

  return (
    <Chip
      size={size}
      color={color}
      label={label}
      sx={{
        fontWeight: 600,
        fontSize: '0.75rem',
        borderRadius: '6px',
        height: size === 'small' ? '22px' : '28px',
      }}
    />
  );
};
