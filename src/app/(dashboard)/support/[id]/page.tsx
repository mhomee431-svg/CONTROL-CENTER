'use client';

import React from 'react';
import { useRouter } from 'next/navigation';
import { useQuery } from '@tanstack/react-query';
import { Box, Card, CardContent, Button, Typography, Divider, Alert, CircularProgress, Grid } from '@mui/material';
import { ArrowLeft, AlertCircle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ComplaintItem } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';

export default function SupportTicketDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  const { data, isLoading, isError } = useQuery<{ items: ComplaintItem[] }>({
    queryKey: ['admin', 'complaints'],
    queryFn: () => apiClient<{ items: ComplaintItem[] }>(API_ENDPOINTS.COMPLAINTS.LIST, { params: { limit: 250 } }),
  });

  const ticket = data?.items?.find((t) => String(t.id) === String(id));

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Support', href: ROUTES.SUPPORT },
          { label: ticket?.ticket_number ? `Ticket ${ticket.ticket_number}` : `Ticket #${id}` },
        ]}
      />
      <Button startIcon={<ArrowLeft size={16} />} onClick={() => router.push(ROUTES.SUPPORT)} sx={{ mb: 2 }}>
        Back to Support Queue
      </Button>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}
      {isError && <Alert severity="error">Could not load ticket #{id}.</Alert>}
      {!isLoading && !ticket && <Alert severity="warning">Ticket #{id} was not found.</Alert>}

      {ticket && (
        <Card>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#FDF2F8', color: '#EC4899' }}>
                  <AlertCircle size={24} />
                </Box>
                <Box>
                  <Typography variant="h6" sx={{ fontWeight: 700 }}>
                    {ticket.complaint_type}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Ticket #{ticket.ticket_number || ticket.id} · Reporter: {ticket.reporter_name || 'Unknown'}
                  </Typography>
                </Box>
              </Box>
              <Box sx={{ display: 'flex', gap: 1 }}>
                <StatusBadge status={ticket.priority} size="medium" />
                <StatusBadge status={ticket.status} size="medium" />
              </Box>
            </Box>
            <Divider sx={{ my: 2 }} />
            <Typography variant="caption" color="text.secondary">
              Description
            </Typography>
            <Typography variant="body2" sx={{ fontWeight: 500, mb: 2 }}>
              {ticket.description}
            </Typography>
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Reporter Type
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {ticket.reporter_type || 'Unknown'}
                </Typography>
              </Grid>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Reported At
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600 }}>
                  {ticket.created_at ? new Date(ticket.created_at).toLocaleString() : 'N/A'}
                </Typography>
              </Grid>
            </Grid>
          </CardContent>
        </Card>
      )}
    </Box>
  );
}
