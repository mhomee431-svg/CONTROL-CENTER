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
    // POS Control Center: link established (a syncing integration is still connected).
    case 'CONNECTED':
    case 'SYNCED':
      color = 'success';
      break;

    case 'PENDING':
    case 'UNDER_REVIEW':
    case 'IN_PROGRESS':
    case 'PROCESSING':
    case 'QUEUED':
    // Verification Center: the merchant was asked to fix the submission, so
    // the case is still open but waiting on them rather than on an operator.
    case 'NEEDS_CORRECTION':
    // Import Center in-flight phases (data ingestion pipeline).
    case 'UPLOADED':
    case 'VALIDATING':
    // PARTIAL means the job finished but some rows were rejected.
    case 'PARTIAL':
    // POS Control Center: a sync run is in flight.
    case 'SYNCING':
    case 'RUNNING':
      color = 'warning';
      break;

    case 'SUSPENDED':
    case 'BANNED':
    case 'REJECTED':
    case 'CANCELLED':
    case 'FAILED':
    case 'URGENT':
    // POS Control Center: link down, or the last sync run failed.
    case 'DISCONNECTED':
    case 'SYNC_FAILED':
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
