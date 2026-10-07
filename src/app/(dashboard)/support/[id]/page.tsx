'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Divider,
  Alert,
  CircularProgress,
  Grid,
  Chip,
  TextField,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Paper,
} from '@mui/material';
import {
  ArrowLeft,
  AlertCircle,
  UserCheck,
  MessageSquare,
  Send,
  Paperclip,
  History,
  ExternalLink,
  Lock,
  History as HistoryIcon,
  User,
  Store,
  Package,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ComplaintItem, ComplaintTimelineEntry } from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { useAuth } from '@/core/auth/AuthContext';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';
import { allowedTransitions, categoryFor, categoryLabel } from '@/core/support/tickets';

export default function SupportTicketDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = React.use(params);
  const router = useRouter();

  // Primary: the dedicated detail endpoint. The list fallback covers backends
  // that only expose the collection, so the page degrades instead of failing.
  const detailQuery = useQuery<ComplaintItem>({
    queryKey: ['admin', 'complaint', id],
    queryFn: () => apiClient<ComplaintItem>(API_ENDPOINTS.COMPLAINTS.DETAIL(id)),
    retry: false,
  });

  const listQuery = useQuery<{ items: ComplaintItem[] }>({
    queryKey: ['admin', 'complaints'],
    queryFn: () => apiClient<{ items: ComplaintItem[] }>(API_ENDPOINTS.COMPLAINTS.LIST, { params: { limit: 250 } }),
    enabled: detailQuery.isError,
    retry: false,
  });

  const ticket = detailQuery.data || listQuery.data?.items?.find((t) => String(t.id) === String(id));
  const isLoading = detailQuery.isLoading || (detailQuery.isError && listQuery.isLoading);

  const queryClient = useQueryClient();
  const { adminRole } = useAuth();

  const [actionError, setActionError] = useState<string | null>(null);
  const [actionNotice, setActionNotice] = useState<string | null>(null);
  const [pendingAction, setPendingAction] = useState<'ASSIGN' | 'STATUS' | 'NOTE' | 'RESPOND' | null>(null);
  const [assignName, setAssignName] = useState('');
  const [newStatus, setNewStatus] = useState('');
  const [noteText, setNoteText] = useState('');
  const [responseText, setResponseText] = useState('');

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ['admin', 'complaint', id] });
    queryClient.invalidateQueries({ queryKey: ['admin', 'complaints'] });
  };

  const assignMutation = useMutation({
    mutationFn: (admin: string) =>
      apiClient(API_ENDPOINTS.COMPLAINTS.ASSIGN(id), {
        method: 'POST',
        body: JSON.stringify({ assigned_admin: admin }),
      }),
    onSuccess: () => {
      setPendingAction(null);
      setActionError(null);
      setActionNotice('Ticket assigned.');
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Assign failed.'),
  });

  const statusMutation = useMutation({
    mutationFn: ({ status, notes }: { status: string; notes: string }) =>
      apiClient(API_ENDPOINTS.COMPLAINTS.UPDATE(id), {
        method: 'PUT',
        body: JSON.stringify({ status, resolution_notes: notes }),
      }),
    onSuccess: () => {
      setPendingAction(null);
      setActionError(null);
      setActionNotice('Status updated.');
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Status update failed.'),
  });

  const noteMutation = useMutation({
    mutationFn: (note: string) =>
      apiClient(API_ENDPOINTS.COMPLAINTS.NOTE(id), {
        method: 'POST',
        body: JSON.stringify({ note, is_internal: true }),
      }),
    onSuccess: () => {
      setPendingAction(null);
      setNoteText('');
      setActionError(null);
      setActionNotice('Internal note added.');
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Adding note failed.'),
  });

  const respondMutation = useMutation({
    mutationFn: (message: string) =>
      apiClient(API_ENDPOINTS.COMPLAINTS.RESPONSE(id), {
        method: 'POST',
        body: JSON.stringify({ message }),
      }),
    onSuccess: () => {
      setPendingAction(null);
      setResponseText('');
      setActionError(null);
      setActionNotice('Response sent to the reporter.');
      invalidate();
    },
    onError: (err: unknown) => setActionError(err instanceof Error ? err.message : 'Sending response failed.'),
  });

  const transitions = ticket ? allowedTransitions(ticket.status) : [];
  const canAssign = ticket?.can_assign !== false;
  const canRespond = ticket?.can_respond !== false && transitions.length > 0;
  const myName = adminRole?.name || '';

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
      {detailQuery.isError && listQuery.isError && (
        <Alert severity="error">Could not load ticket #{id}.</Alert>
      )}
      {!isLoading && !ticket && <Alert severity="warning">Ticket #{id} was not found.</Alert>}

      {actionError && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setActionError(null)}>
          {actionError}
        </Alert>
      )}
      {actionNotice && !actionError && (
        <Alert severity="success" sx={{ mb: 2 }} onClose={() => setActionNotice(null)}>
          {actionNotice}
        </Alert>
      )}

      {ticket && (
        <>
        <Card sx={{ mb: 2 }}>
          <CardContent sx={{ p: 3 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2, flexWrap: 'wrap', gap: 2 }}>
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
              <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
                <StatusBadge status={ticket.priority} size="medium" />
                <StatusBadge status={ticket.status} size="medium" />
              </Box>
            </Box>
            <Divider sx={{ my: 2 }} />
            <Typography variant="caption" color="text.secondary">
              Issue Description
            </Typography>
            <Typography variant="body2" sx={{ fontWeight: 500, mb: 2 }}>
              {ticket.description}
            </Typography>
            {ticket.resolution_notes && (
              <>
                <Typography variant="caption" color="text.secondary">
                  Resolution Notes
                </Typography>
                <Typography variant="body2" sx={{ mb: 2 }}>
                  {ticket.resolution_notes}
                </Typography>
              </>
            )}
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Issue Type / Category
                </Typography>
                <Box sx={{ mt: 0.5 }}>
                  <Chip size="small" label={categoryLabel(categoryFor(ticket))} variant="outlined" />
                </Box>
              </Grid>
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
              <Grid item xs={12} sm={6}>
                <Typography variant="caption" color="text.secondary">
                  Assigned Admin
                </Typography>
                <Typography variant="body2" sx={{ fontWeight: 600, display: 'flex', alignItems: 'center', gap: 0.5 }}>
                  <UserCheck size={15} color="#64748B" />
                  {ticket.assigned_admin || 'Unassigned'}
                </Typography>
              </Grid>
            </Grid>
          </CardContent>
        </Card>

        {/* Related entities — only rendered when the backend linked them. */}
        {(ticket.related_customer_id || ticket.related_shop_id || ticket.related_product_id) && (
          <Card sx={{ mb: 2 }}>
            <CardContent sx={{ p: 2.5 }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
                Related Records
              </Typography>
              <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
                {ticket.related_customer_id && (
                  <RelatedLink
                    icon={<User size={15} />}
                    label={ticket.related_customer_name || `Customer #${ticket.related_customer_id}`}
                    href={ROUTES.CUSTOMER_DETAIL(ticket.related_customer_id)}
                  />
                )}
                {ticket.related_shop_id && (
                  <RelatedLink
                    icon={<Store size={15} />}
                    label={ticket.related_shop_name || `Shop #${ticket.related_shop_id}`}
                    href={ROUTES.BUSINESS_DETAIL(ticket.related_shop_id)}
                  />
                )}
                {ticket.related_product_id && (
                  <RelatedLink
                    icon={<Package size={15} />}
                    label={ticket.related_product_name || `Product #${ticket.related_product_id}`}
                    href={ROUTES.PRODUCT_DETAIL(ticket.related_product_id)}
                  />
                )}
              </Box>
            </CardContent>
          </Card>
        )}

        {/* Attachments — degrade silently when none exist. */}
        {ticket.attachments && ticket.attachments.length > 0 && (
          <Card sx={{ mb: 2 }}>
            <CardContent sx={{ p: 2.5 }}>
              <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
                Attachments
              </Typography>
              <List dense disablePadding>
                {ticket.attachments.map((att, idx) => (
                  <ListItem key={att.id ?? idx} disableGutters>
                    <ListItemIcon sx={{ minWidth: 30 }}>
                      <Paperclip size={15} color="#64748B" />
                    </ListItemIcon>
                    <ListItemText
                      primary={att.file_name || 'Attachment'}
                      secondary={att.file_size_bytes ? `${(att.file_size_bytes / 1024).toFixed(0)} KB` : undefined}
                      primaryTypographyProps={{ fontSize: '0.85rem' }}
                    />
                    {att.file_url && (
                      <Button
                        size="small"
                        startIcon={<ExternalLink size={14} />}
                        href={att.file_url}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        Open
                      </Button>
                    )}
                  </ListItem>
                ))}
              </List>
            </CardContent>
          </Card>
        )}

        {/* Actions — every write is permission-gated and reason/notes-captured. */}
        <Card sx={{ mb: 2 }}>
          <CardContent sx={{ p: 2.5 }}>
            <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5 }}>
              Actions
            </Typography>
            <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
              {canAssign && (
                <PermissionGuard capability={CAPABILITIES.SUPPORT_UPDATE}>
                  <Button variant="outlined" startIcon={<UserCheck size={15} />} onClick={() => setPendingAction('ASSIGN')}>
                    Assign
                  </Button>
                </PermissionGuard>
              )}
              {transitions.length > 0 ? (
                <PermissionGuard capability={CAPABILITIES.SUPPORT_UPDATE}>
                  <Button variant="contained" startIcon={<History size={15} />} onClick={() => { setNewStatus(transitions.includes('RESOLVED') ? 'RESOLVED' : transitions[0]); setPendingAction('STATUS'); }}>
                    Change Status
                  </Button>
                </PermissionGuard>
              ) : (
                <Alert severity="info" sx={{ py: 0 }}>
                  Closed ticket — terminal state, no status transitions.
                </Alert>
              )}
              <PermissionGuard capability={CAPABILITIES.SUPPORT_UPDATE}>
                <Button variant="outlined" startIcon={<Lock size={15} />} onClick={() => setPendingAction('NOTE')}>
                  Add Internal Note
                </Button>
              </PermissionGuard>
              {canRespond && (
                <PermissionGuard capability={CAPABILITIES.SUPPORT_UPDATE}>
                  <Button variant="outlined" color="success" startIcon={<Send size={15} />} onClick={() => setPendingAction('RESPOND')}>
                    Respond to Reporter
                  </Button>
                </PermissionGuard>
              )}
            </Box>
          </CardContent>
        </Card>

        {/* Timeline — from the detail payload or the dedicated endpoint. */}
        <Card>
          <CardContent sx={{ p: 2.5 }}>
            <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1.5, display: 'flex', alignItems: 'center', gap: 1 }}>
              <HistoryIcon size={16} /> Timeline
            </Typography>
            {ticket.timeline && ticket.timeline.length > 0 ? (
              <TimelineList entries={ticket.timeline} />
            ) : (
              <Alert severity="info">No activity recorded yet — events will appear as this ticket is handled.</Alert>
            )}
          </CardContent>
        </Card>
        </>
      )}

      {/* Assign dialog */}
      <Dialog open={pendingAction === 'ASSIGN'} onClose={() => setPendingAction(null)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 600 }}>Assign Ticket #{id}</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            margin="dense"
            label="Assign to admin"
            value={assignName || myName}
            onChange={(e) => setAssignName(e.target.value)}
            helperText={myName ? `Defaults to you (${myName}).` : 'Enter the admin username.'}
          />
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2 }}>
          <Button color="inherit" onClick={() => setPendingAction(null)}>Cancel</Button>
          <Button
            variant="contained"
            disabled={assignMutation.isPending}
            onClick={() => assignMutation.mutate(assignName.trim() || myName)}
          >
            {assignMutation.isPending ? <CircularProgress size={18} color="inherit" /> : 'Assign'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* Change-status dialog */}
      <Dialog open={pendingAction === 'STATUS'} onClose={() => setPendingAction(null)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 600 }}>Change Status — Ticket #{id}</DialogTitle>
        <DialogContent>
          <FormControl fullWidth margin="dense">
            <InputLabel>New Status</InputLabel>
            <Select value={newStatus} label="New Status" onChange={(e) => setNewStatus(e.target.value)}>
              {transitions.map((s) => (
                <MenuItem key={s} value={s}>{s.replace('_', ' ')}</MenuItem>
              ))}
            </Select>
          </FormControl>
          <TextField
            fullWidth
            margin="dense"
            multiline
            rows={3}
            label="Resolution / operational notes"
            value={noteText}
            onChange={(e) => setNoteText(e.target.value)}
          />
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2 }}>
          <Button color="inherit" onClick={() => setPendingAction(null)}>Cancel</Button>
          <Button
            variant="contained"
            disabled={!newStatus || statusMutation.isPending}
            onClick={() => statusMutation.mutate({ status: newStatus, notes: noteText })}
          >
            {statusMutation.isPending ? <CircularProgress size={18} color="inherit" /> : 'Update Status'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* Internal-note dialog */}
      <Dialog open={pendingAction === 'NOTE'} onClose={() => setPendingAction(null)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 600 }}>Add Internal Note</DialogTitle>
        <DialogContent>
          <Alert severity="info" sx={{ mb: 2 }}>
            Internal notes are visible to admins only — never shown to the reporter.
          </Alert>
          <TextField
            autoFocus
            fullWidth
            multiline
            rows={4}
            label="Internal note"
            value={noteText}
            onChange={(e) => setNoteText(e.target.value)}
          />
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2 }}>
          <Button color="inherit" onClick={() => setPendingAction(null)}>Cancel</Button>
          <Button
            variant="contained"
            disabled={!noteText.trim() || noteMutation.isPending}
            onClick={() => noteMutation.mutate(noteText.trim())}
          >
            {noteMutation.isPending ? <CircularProgress size={18} color="inherit" /> : 'Add Note'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* Respond-to-reporter dialog */}
      <Dialog open={pendingAction === 'RESPOND'} onClose={() => setPendingAction(null)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 600 }}>Respond to Reporter</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            multiline
            rows={4}
            label="Response message"
            value={responseText}
            onChange={(e) => setResponseText(e.target.value)}
            helperText="This message is delivered to the ticket reporter."
          />
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2 }}>
          <Button color="inherit" onClick={() => setPendingAction(null)}>Cancel</Button>
          <Button
            variant="contained"
            color="success"
            disabled={!responseText.trim() || respondMutation.isPending}
            onClick={() => respondMutation.mutate(responseText.trim())}
          >
            {respondMutation.isPending ? <CircularProgress size={18} color="inherit" /> : 'Send Response'}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

const RelatedLink: React.FC<{ icon: React.ReactNode; label: string; href: string }> = ({ icon, label, href }) => (
  <Button
    size="small"
    variant="outlined"
    startIcon={icon}
    onClick={() => window.open(href, '_self')}
    sx={{ textTransform: 'none' }}
  >
    {label}
  </Button>
);

const TimelineList: React.FC<{ entries: ComplaintTimelineEntry[] }> = ({ entries }) => (
  <List dense disablePadding>
    {entries.map((entry, idx) => (
      <ListItem key={entry.id ?? idx} disableGutters sx={{ alignItems: 'flex-start', py: 1 }}>
        <ListItemIcon sx={{ minWidth: 30, mt: 0.5 }}>
          {entry.is_internal ? <Lock size={14} color="#F59E0B" /> : <MessageSquare size={14} color="#64748B" />}
        </ListItemIcon>
        <ListItemText
          primary={
            <Box sx={{ display: 'flex', gap: 1, alignItems: 'center', flexWrap: 'wrap' }}>
              <Typography variant="body2" sx={{ fontWeight: 600 }}>
                {entry.message}
              </Typography>
              {entry.is_internal && <Chip size="small" label="INTERNAL" variant="outlined" sx={{ height: 18, fontSize: '0.65rem' }} />}
            </Box>
          }
          secondary={
            <Typography variant="caption" color="text.secondary">
              {entry.event_type}{entry.actor_name ? ` · ${entry.actor_name}` : ''}
              {entry.created_at ? ` · ${new Date(entry.created_at).toLocaleString()}` : ''}
            </Typography>
          }
        />
      </ListItem>
    ))}
  </List>
);
