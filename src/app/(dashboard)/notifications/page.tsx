'use client';

import React, { useMemo, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Box,
  Typography,
  Card,
  CardContent,
  TextField,
  Button,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Alert,
  Chip,
  Divider,
  InputAdornment,
  Tooltip,
  Grid,
  Collapse,
} from '@mui/material';
import { Send, Link2, ShieldCheck, ShieldAlert, Info, Save, CalendarClock, Target, Braces } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import {
  NotificationAudience,
  NotificationDraftPayload,
  NotificationSendPayload,
} from '@/core/types/admin';
import {
  ALL_NOTIFICATION_TYPES,
  AUDIENCE_TARGETING,
  NOTIFICATION_AUDIENCE_LIST,
  NOTIFICATION_TYPE_RULES,
  NOTIFICATION_TYPES,
  NotificationType,
  validateDeepLink,
  validateMetadata,
  validateSchedule,
} from '@/core/notifications/deepLink';
import { MobileNotificationPreview } from '@/core/notifications/MobileNotificationPreview';

/** Parse a comma/space separated list of ids into positive integers. */
function parseIds(raw: string): number[] {
  return raw
    .split(/[\s,]+/)
    .map((token) => token.trim())
    .filter(Boolean)
    .map((token) => Number(token))
    .filter((n) => Number.isInteger(n) && n > 0);
}

export default function NotificationsPage() {
  const queryClient = useQueryClient();

  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [audience, setAudience] = useState<NotificationAudience>('all');
  const [notificationType, setNotificationType] = useState<NotificationType>(NOTIFICATION_TYPES.ADMIN_BROADCAST);
  const [entityId, setEntityId] = useState('');
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [showConfirm, setShowConfirm] = useState(false);

  // Schedule / targeting / metadata
  const [scheduledAt, setScheduledAt] = useState('');
  const [category, setCategory] = useState('');
  const [location, setLocation] = useState('');
  const [selectedIds, setSelectedIds] = useState('');
  const [metadata, setMetadata] = useState('');
  const [showAdvanced, setShowAdvanced] = useState(false);

  const rule = NOTIFICATION_TYPE_RULES[notificationType];
  const entityRequired = rule.entity === 'numeric' || rule.entity === 'string';
  const targeting = AUDIENCE_TARGETING[audience];
  const selectedIdsParsed = parseIds(selectedIds);

  /**
   * NOTIFICATION SAFETY: the deep link is derived — never free-typed — and is
   * validated against the type + entity + supported-route contract before it is
   * ever placed into the payload. The backend re-validates authoritatively.
   */
  const deepLinkValidation = useMemo(
    () => validateDeepLink(notificationType, entityId || null),
    [notificationType, entityId]
  );

  const scheduleValidation = useMemo(() => validateSchedule(scheduledAt), [scheduledAt]);
  const metadataValidation = useMemo(() => validateMetadata(metadata), [metadata]);

  const formValid =
    title.trim().length > 0 &&
    body.trim().length > 0 &&
    deepLinkValidation.valid &&
    scheduleValidation.valid &&
    metadataValidation.valid &&
    (!entityRequired || entityId.trim().length > 0) &&
    (!targeting.selected || selectedIdsParsed.length > 0);

  /** Build the shared payload body for both send and draft. */
  const buildPayload = () => ({
    title: title.trim(),
    body: body.trim(),
    notification_type: notificationType,
    audience,
    deep_link: deepLinkValidation.path,
    entity_id: entityId.trim() || null,
    scheduled_at: scheduleValidation.iso,
    category: targeting.category ? category.trim() || null : null,
    location: targeting.location ? location.trim() || null : null,
    selected_ids: targeting.selected && selectedIdsParsed.length > 0 ? selectedIdsParsed : null,
    metadata: metadataValidation.value,
  });

  const sendMutation = useMutation({
    mutationFn: (payload: NotificationSendPayload) =>
      apiClient(API_ENDPOINTS.NOTIFICATIONS.SEND, {
        method: 'POST',
        body: JSON.stringify(payload),
      }),
    onSuccess: () => {
      resetForm();
      setSuccessMsg(
        scheduleValidation.iso
          ? 'Notification scheduled successfully.'
          : 'Broadcast notification dispatched successfully.'
      );
      queryClient.invalidateQueries({ queryKey: ['admin', 'campaigns'] });
    },
    onError: (err: unknown) => {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to dispatch notification.');
    },
  });

  const draftMutation = useMutation({
    mutationFn: (payload: NotificationDraftPayload) =>
      apiClient(API_ENDPOINTS.NOTIFICATIONS.DRAFTS, {
        method: 'POST',
        body: JSON.stringify(payload),
      }),
    onSuccess: () => {
      setSuccessMsg('Draft saved. Nothing was sent.');
      queryClient.invalidateQueries({ queryKey: ['admin', 'campaigns'] });
    },
    onError: (err: unknown) => {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to save draft.');
    },
  });

  const resetForm = () => {
    setTitle('');
    setBody('');
    setEntityId('');
    setScheduledAt('');
    setCategory('');
    setLocation('');
    setSelectedIds('');
    setMetadata('');
  };

  const handlePreSend = (e: React.FormEvent) => {
    e.preventDefault();
    setSuccessMsg(null);
    setErrorMsg(null);
    if (!formValid) return;
    setShowConfirm(true);
  };

  const handleConfirmSend = async (reason: string) => {
    // Re-validate at the final boundary — never trust earlier UI state.
    const validation = validateDeepLink(notificationType, entityId || null);
    if (!validation.valid) {
      setErrorMsg(validation.message || 'Deep link validation failed.');
      throw new Error(validation.message || 'Deep link validation failed.');
    }
    const schedule = validateSchedule(scheduledAt);
    if (!schedule.valid) {
      setErrorMsg(schedule.message || 'Schedule validation failed.');
      throw new Error(schedule.message || 'Schedule validation failed.');
    }

    const payload: NotificationSendPayload = {
      ...buildPayload(),
      deep_link: validation.path,
      scheduled_at: schedule.iso,
      reason,
    };

    await sendMutation.mutateAsync(payload);
  };

  const handleSaveDraft = async () => {
    setSuccessMsg(null);
    setErrorMsg(null);
    // A draft may be incomplete, but anything it carries must still be safe.
    if (!deepLinkValidation.valid || !metadataValidation.valid || !scheduleValidation.valid) {
      setErrorMsg(
        deepLinkValidation.message || metadataValidation.message || scheduleValidation.message || 'Fix the errors first.'
      );
      return;
    }
    const payload: NotificationDraftPayload = buildPayload();
    await draftMutation.mutateAsync(payload);
  };

  return (
    <Box sx={{ maxWidth: 1100 }}>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Notification Composer
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 48, 49, 50: Compose, schedule and target platform notifications. Every deep link is validated against
          notification type, entity ID and supported routes — the backend re-validates authoritatively.
        </Typography>
      </Box>

      {successMsg && (
        <Alert severity="success" sx={{ mb: 3 }} onClose={() => setSuccessMsg(null)}>
          {successMsg}
        </Alert>
      )}
      {errorMsg && (
        <Alert severity="error" sx={{ mb: 3 }} onClose={() => setErrorMsg(null)}>
          {errorMsg}
        </Alert>
      )}

      <Grid container spacing={3}>
        <Grid item xs={12} md={7.5}>
          <Card>
            <CardContent sx={{ p: 3 }}>
              <Box component="form" onSubmit={handlePreSend}>
                <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', mb: 2 }}>
                  <FormControl margin="dense" sx={{ flex: 1, minWidth: 240 }}>
                    <InputLabel>Notification Type</InputLabel>
                    <Select
                      value={notificationType}
                      label="Notification Type"
                      onChange={(e) => {
                        setNotificationType(e.target.value as NotificationType);
                        setEntityId('');
                      }}
                    >
                      {ALL_NOTIFICATION_TYPES.map((type) => (
                        <MenuItem key={type} value={type}>
                          {NOTIFICATION_TYPE_RULES[type].label}
                        </MenuItem>
                      ))}
                    </Select>
                  </FormControl>

                  <FormControl margin="dense" sx={{ flex: 1, minWidth: 200 }}>
                    <InputLabel>Audience</InputLabel>
                    <Select
                      value={audience}
                      label="Audience"
                      onChange={(e) => setAudience(e.target.value as NotificationAudience)}
                    >
                      {NOTIFICATION_AUDIENCE_LIST.map((option) => (
                        <MenuItem key={option.audience} value={option.audience}>
                          {option.label}
                        </MenuItem>
                      ))}
                    </Select>
                  </FormControl>
                </Box>

                {rule.entity !== 'none' && (
                  <TextField
                    margin="dense"
                    label={`Entity ID ${entityRequired ? '(required)' : '(optional)'}`}
                    fullWidth
                    required={entityRequired}
                    value={entityId}
                    onChange={(e) => setEntityId(e.target.value)}
                    error={Boolean(entityId) && !deepLinkValidation.valid}
                    helperText={
                      entityId && !deepLinkValidation.valid
                        ? deepLinkValidation.message
                        : rule.entity === 'numeric'
                        ? 'Numeric identifier of the target entity.'
                        : 'Letters, numbers, hyphens and underscores only.'
                    }
                    sx={{ mb: 2 }}
                    slotProps={{
                      input: {
                        startAdornment: (
                          <InputAdornment position="start">
                            <Link2 size={16} color="#64748B" />
                          </InputAdornment>
                        ),
                      },
                    }}
                  />
                )}

                <TextField
                  margin="dense"
                  label="Notification Title"
                  fullWidth
                  required
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  sx={{ mb: 2 }}
                />

                <TextField
                  margin="dense"
                  label="Message Body"
                  fullWidth
                  required
                  multiline
                  rows={4}
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                  sx={{ mb: 2 }}
                />

                <Divider sx={{ my: 2 }} />

                {/* Targeting — only dimensions the backend resolves are shown. */}
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                  <Target size={16} color="#64748B" />
                  <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748B', letterSpacing: '0.04em' }}>
                    TARGETING
                  </Typography>
                </Box>

                <Grid container spacing={2} sx={{ mb: 2 }}>
                  {targeting.category && (
                    <Grid item xs={12} sm={6}>
                      <TextField
                        margin="dense"
                        label="Category (optional)"
                        fullWidth
                        value={category}
                        onChange={(e) => setCategory(e.target.value)}
                        helperText="Restrict to one category, if supported."
                      />
                    </Grid>
                  )}
                  {targeting.location && (
                    <Grid item xs={12} sm={6}>
                      <TextField
                        margin="dense"
                        label="Location (optional)"
                        fullWidth
                        value={location}
                        onChange={(e) => setLocation(e.target.value)}
                        helperText="City or state filter."
                      />
                    </Grid>
                  )}
                  {targeting.selected && (
                    <Grid item xs={12}>
                      <TextField
                        margin="dense"
                        label="Selected IDs (required for this audience)"
                        fullWidth
                        value={selectedIds}
                        onChange={(e) => setSelectedIds(e.target.value)}
                        error={targeting.selected && selectedIdsParsed.length === 0}
                        helperText="Comma or space separated numeric subject ids."
                      />
                    </Grid>
                  )}
                </Grid>

                <Button
                  size="small"
                  variant="text"
                  onClick={() => setShowAdvanced((v) => !v)}
                  startIcon={<CalendarClock size={16} />}
                  sx={{ mb: 1 }}
                >
                  {showAdvanced ? 'Hide schedule & metadata' : 'Schedule & metadata'}
                </Button>

                <Collapse in={showAdvanced} unmountOnExit>
                  <Grid container spacing={2} sx={{ mb: 2, mt: 0.5 }}>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        margin="dense"
                        label="Schedule (optional)"
                        type="datetime-local"
                        fullWidth
                        value={scheduledAt}
                        onChange={(e) => setScheduledAt(e.target.value)}
                        error={Boolean(scheduledAt) && !scheduleValidation.valid}
                        helperText={
                          scheduledAt && !scheduleValidation.valid
                            ? scheduleValidation.message
                            : 'Leave blank to send immediately.'
                        }
                        slotProps={{ inputLabel: { shrink: true } }}
                      />
                    </Grid>
                    <Grid item xs={12} sm={6}>
                      <TextField
                        margin="dense"
                        label="Metadata (JSON, optional)"
                        fullWidth
                        multiline
                        rows={2}
                        value={metadata}
                        onChange={(e) => setMetadata(e.target.value)}
                        error={Boolean(metadata) && !metadataValidation.valid}
                        helperText={
                          metadata && !metadataValidation.valid
                            ? metadataValidation.message
                            : 'Opaque key/value envelope. Never used to build a route.'
                        }
                        slotProps={{
                          input: {
                            startAdornment: (
                              <InputAdornment position="start">
                                <Braces size={16} color="#64748B" />
                              </InputAdornment>
                            ),
                          },
                        }}
                      />
                    </Grid>
                  </Grid>
                </Collapse>

                <Divider sx={{ my: 2 }} />

                {/* Deep link validation preview */}
                <Box sx={{ mb: 2 }}>
                  <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748B', letterSpacing: '0.04em' }}>
                    DEEP LINK VALIDATION
                  </Typography>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mt: 1, flexWrap: 'wrap' }}>
                    <Chip
                      size="small"
                      icon={deepLinkValidation.valid ? <ShieldCheck size={14} /> : <ShieldAlert size={14} />}
                      color={deepLinkValidation.valid ? 'success' : 'error'}
                      variant="outlined"
                      label={deepLinkValidation.valid ? 'Type + Entity + Route valid' : 'Validation failed'}
                    />
                    {deepLinkValidation.path ? (
                      <Chip size="small" label={deepLinkValidation.path} variant="outlined" color="primary" />
                    ) : (
                      <Tooltip title="This notification type has no client destination.">
                        <Chip size="small" label="No deep link" variant="outlined" />
                      </Tooltip>
                    )}
                  </Box>
                  {!deepLinkValidation.valid && (
                    <Alert severity="error" sx={{ mt: 1.5 }}>
                      {deepLinkValidation.message}
                    </Alert>
                  )}
                </Box>

                <Alert severity="info" icon={<Info size={18} />} sx={{ mb: 3 }}>
                  Deep links must resolve to a registered admin route. External URLs, protocol-relative URLs and path
                  traversal are rejected automatically, on the client and again on the server.
                </Alert>

                <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap' }}>
                  <PermissionGuard capability={CAPABILITIES.NOTIFICATIONS_SEND}>
                    <Button
                      variant="outlined"
                      size="large"
                      startIcon={<Save size={18} />}
                      disabled={draftMutation.isPending || sendMutation.isPending}
                      onClick={handleSaveDraft}
                    >
                      {draftMutation.isPending ? 'Saving...' : 'Save Draft'}
                    </Button>
                  </PermissionGuard>
                  <PermissionGuard capability={CAPABILITIES.NOTIFICATIONS_SEND}>
                    <Button
                      type="submit"
                      variant="contained"
                      size="large"
                      startIcon={<Send size={18} />}
                      disabled={sendMutation.isPending || !formValid}
                    >
                      {sendMutation.isPending
                        ? scheduleValidation.iso
                          ? 'Scheduling...'
                          : 'Broadcasting...'
                        : scheduleValidation.iso
                        ? 'Review & Schedule'
                        : 'Review & Send Broadcast'}
                    </Button>
                  </PermissionGuard>
                </Box>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} md={4.5}>
          <MobileNotificationPreview
            title={title}
            body={body}
            deepLink={deepLinkValidation.path}
            audienceLabel={targeting.label.toUpperCase()}
          />
        </Grid>
      </Grid>

      <ConfirmationDialog
        open={showConfirm}
        title={scheduleValidation.iso ? 'Confirm Scheduled Broadcast' : 'Confirm High-Impact Broadcast'}
        affectedItem={`Audience: ${targeting.label} · ${rule.label}`}
        consequence={
          scheduleValidation.iso
            ? `This broadcast is queued for ${new Date(scheduleValidation.iso).toLocaleString()}. It will push to active devices when it runs.`
            : deepLinkValidation.path
            ? `Section 49: This broadcast pushes directly to active devices with deep link "${deepLinkValidation.path}" and cannot be undone.`
            : 'Section 49: Sending a broadcast notification pushes directly to active devices and cannot be undone.'
        }
        isDangerous={!scheduleValidation.iso}
        requireReason
        isLoading={sendMutation.isPending}
        onConfirm={handleConfirmSend}
        onClose={() => setShowConfirm(false)}
      />
    </Box>
  );
}
