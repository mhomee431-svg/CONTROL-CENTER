import React from 'react';
import { Box, Card, CardContent, Typography, Alert, Chip, Divider, Link as MuiLink } from '@mui/material';
import { AlertTriangle, Inbox, ExternalLink as ExternalLinkIcon } from 'lucide-react';
import { StatusBadge } from './StatusBadge';

/**
 * Presentational building blocks for the business drill-down tabs.
 *
 * Each tab answers one operator question, and an absent value has to read as
 * absent rather than as a blank cell that looks like it was never asked for.
 * So every field states what it is, and `—` means "the backend did not report
 * this", which is a different statement from "this is empty".
 */

/** One labelled value inside a tab panel. */
export function DetailField({
  label,
  value,
  mono,
}: {
  label: string;
  value: React.ReactNode;
  mono?: boolean;
}) {
  const missing =
    value === null ||
    value === undefined ||
    value === '' ||
    (typeof value === 'number' && Number.isNaN(value));
  return (
    <Box sx={{ py: 1, borderBottom: '1px solid #F1F5F9' }}>
      <Typography variant="caption" color="text.secondary" sx={{ textTransform: 'uppercase', letterSpacing: 0.4 }}>
        {label}
      </Typography>
      <Typography
        variant="body2"
        sx={{ fontWeight: 500, mt: 0.25, wordBreak: 'break-word', fontFamily: mono ? 'monospace' : undefined }}
      >
        {missing ? '—' : value}
      </Typography>
    </Box>
  );
}

export function TabSection({ title, description, children }: { title: string; description?: string; children: React.ReactNode }) {
  return (
    <Card>
      <CardContent sx={{ p: 3 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>
          {title}
        </Typography>
        {description && (
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5, mb: 1 }}>
            {description}
          </Typography>
        )}
        <Divider sx={{ my: 1.5 }} />
        {children}
      </CardContent>
    </Card>
  );
}

/** A value the backend did not report. Named so it is never mistaken for zero. */
export function NotReported({ what }: { what: string }) {
  return (
    <Box sx={{ py: 2, textAlign: 'center' }}>
      <Typography variant="body2" color="text.secondary">
        {what} is not reported by the backend for this business.
      </Typography>
    </Box>
  );
}

/**
 * Three outcomes for a shop-scoped list, kept distinct on purpose:
 *   failed          -> the request broke; offer a retry
 *   unavailable     -> the route is not deployed here; say so
 *   empty           -> the request succeeded and there is nothing
 * Collapsing the last two into "no records" would tell the operator their
 * data is gone when in fact nothing was ever asked for.
 */
export function ListState({
  isError,
  unavailable,
  isEmpty,
  emptyMessage,
  unavailableMessage,
  onRetry,
  isRetrying,
}: {
  isError: boolean;
  unavailable: boolean;
  isEmpty: boolean;
  emptyMessage: string;
  unavailableMessage: string;
  onRetry?: () => void;
  isRetrying?: boolean;
}) {
  if (isError) {
    return (
      <Alert severity="error" sx={{ mt: 2 }} action={
        onRetry ? (
          <MuiLink component="button" onClick={onRetry} underline="hover" sx={{ fontWeight: 600 }}>
            {isRetrying ? 'Retrying…' : 'Retry'}
          </MuiLink>
        ) : undefined
      }>
        The request failed, so this list is unknown rather than empty.
      </Alert>
    );
  }
  if (unavailable) {
    return (
      <Alert severity="info" sx={{ mt: 2 }} icon={<AlertTriangle size={18} />}>
        {unavailableMessage}
      </Alert>
    );
  }
  if (isEmpty) {
    return (
      <Box sx={{ py: 3, textAlign: 'center' }}>
        <Inbox size={22} color="#94A3B8" />
        <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
          {emptyMessage}
        </Typography>
      </Box>
    );
  }
  return null;
}

/** A safe outbound link. Only http(s) is allowed through. */
export function ExternalLink({ href, children }: { href?: string | null; children: React.ReactNode }) {
  if (!href || !/^https?:\/\//i.test(href)) {
    return <Typography variant="body2">—</Typography>;
  }
  return (
    <MuiLink href={href} target="_blank" rel="noopener noreferrer" underline="hover" sx={{ fontWeight: 500 }}>
      {children} <ExternalLinkIcon size={12} style={{ verticalAlign: 'middle' }} />
    </MuiLink>
  );
}

export { StatusBadge, Chip };