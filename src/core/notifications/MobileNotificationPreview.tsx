'use client';

import React from 'react';
import { Box, Typography, Chip } from '@mui/material';
import { Smartphone, Link2 } from 'lucide-react';

export interface MobileNotificationPreviewProps {
  title: string;
  body: string;
  /** Application/platform label shown above the title. */
  appName?: string;
  /** Validated, root-relative deep link — only ever a safe path. */
  deepLink?: string | null;
  /** Small label for the audience scope, e.g. "ALL CUSTOMERS". */
  audienceLabel?: string;
}

/**
 * A faithful mobile push notification preview.
 *
 * This renders only what the operator has actually entered, plus a deep link
 * that has already passed validation. It never invents copy — an empty title or
 * body shows the placeholder so the gap is visible before sending.
 */
export const MobileNotificationPreview: React.FC<MobileNotificationPreviewProps> = ({
  title,
  body,
  appName = 'Hyperlocal',
  deepLink,
  audienceLabel,
}) => {
  return (
    <Box
      sx={{
        borderRadius: 3,
        border: '1px solid #E2E8F0',
        backgroundColor: '#F8FAFC',
        p: 2,
      }}
    >
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1.5 }}>
        <Smartphone size={16} color="#64748B" />
        <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748B', letterSpacing: '0.04em' }}>
          MOBILE PREVIEW
        </Typography>
      </Box>

      <Box
        sx={{
          borderRadius: 2.5,
          backgroundColor: '#FFFFFF',
          boxShadow: '0 1px 3px rgba(15, 23, 42, 0.12)',
          p: 1.5,
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
          <Box
            sx={{
              width: 22,
              height: 22,
              borderRadius: '6px',
              backgroundColor: 'primary.main',
              color: '#fff',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 12,
              fontWeight: 700,
            }}
          >
            H
          </Box>
          <Typography variant="caption" sx={{ color: '#64748B', fontWeight: 600 }}>
            {appName}
          </Typography>
          <Typography variant="caption" sx={{ color: '#94A3B8', ml: 'auto' }}>
            now
          </Typography>
        </Box>

        <Typography variant="subtitle2" sx={{ fontWeight: 700, lineHeight: 1.3 }}>
          {title.trim() || 'Notification title'}
        </Typography>
        <Typography
          variant="body2"
          color={body.trim() ? 'text.primary' : 'text.disabled'}
          sx={{ whiteSpace: 'pre-wrap', mt: 0.25 }}
        >
          {body.trim() || 'Message body appears here.'}
        </Typography>

        {deepLink && (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mt: 1 }}>
            <Link2 size={13} color="#2563EB" />
            <Typography variant="caption" sx={{ color: 'primary.main', fontWeight: 600 }}>
              {deepLink}
            </Typography>
          </Box>
        )}
      </Box>

      {audienceLabel && (
        <Box sx={{ mt: 1.5 }}>
          <Chip size="small" variant="outlined" label={audienceLabel} />
        </Box>
      )}
    </Box>
  );
};
