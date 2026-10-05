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
} from '@mui/material';
import { Send, Link2, ShieldCheck, ShieldAlert, Info } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { NotificationAudience, NotificationSendPayload } from '@/core/types/admin';
import {
  ALL_NOTIFICATION_TYPES,
  NOTIFICATION_TYPE_RULES,
  NOTIFICATION_TYPES,
  NotificationType,
  validateDeepLink,
} from '@/core/notifications/deepLink';

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

  const rule = NOTIFICATION_TYPE_RULES[notificationType];
  const entityRequired = rule.entity === 'numeric' || rule.entity === 'string';

  /**
   * NOTIFICATION SAFETY: the deep link is derived — never free-typed — and is
   * validated against the type + entity + supported-route contract before it is
   * ever placed into the payload.
   */
  const deepLinkValidation = useMemo(
    () => validateDeepLink(notificationType, entityId || null),
    [notificationType, entityId]
  );

  const formValid =
    title.trim().length > 0 &&
    body.trim().length > 0 &&
    deepLinkValidation.valid &&
    (!entityRequired || entityId.trim().length > 0);

  const sendMutation = useMutation({
    mutationFn: (payload: NotificationSendPayload) =>
      apiClient(API_ENDPOINTS.NOTIFICATIONS.SEND, {
        method: 'POST',
        body: JSON.stringify(payload),
      }),
    onSuccess: () => {
      setTitle('');
      setBody('');
      setEntityId('');
      setSuccessMsg('Broadcast notification dispatched successfully.');
      queryClient.invalidateQueries({ queryKey: ['admin', 'campaigns'] });
    },
    onError: (err: unknown) => {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to dispatch notification.');
    },
  });

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

    const payload: NotificationSendPayload = {
      title: title.trim(),
      body: body.trim(),
      notification_type: notificationType,
      audience,
      deep_link: validation.path,
      entity_id: entityId.trim() || null,
      reason,
    };

    await sendMutation.mutateAsync(payload);
  };

  return (
    <Box sx={{ maxWidth: 860 }}>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Notification Broadcast Composer
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 48, 49, 50: Dispatch platform announcements and targeted notifications. Every deep link is validated
          against notification type, entity ID and supported routes before dispatch.
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
                <InputLabel>Audience Scope</InputLabel>
                <Select
                  value={audience}
                  label="Audience Scope"
                  onChange={(e) => setAudience(e.target.value as NotificationAudience)}
                >
                  <MenuItem value="all">All Platform Users</MenuItem>
                  <MenuItem value="customer">Customers Only</MenuItem>
                  <MenuItem value="shopkeeper">Shopkeepers Only</MenuItem>
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
              traversal are rejected automatically.
            </Alert>

            <PermissionGuard capability={CAPABILITIES.NOTIFICATIONS_SEND}>
              <Button
                type="submit"
                variant="contained"
                size="large"
                startIcon={<Send size={18} />}
                disabled={sendMutation.isPending || !formValid}
              >
                {sendMutation.isPending ? 'Broadcasting...' : 'Review & Send Broadcast'}
              </Button>
            </PermissionGuard>
          </Box>
        </CardContent>
      </Card>

      <ConfirmationDialog
        open={showConfirm}
        title="Confirm High-Impact Broadcast"
        affectedItem={`Target: ${audience.toUpperCase()} · ${rule.label}`}
        consequence={
          deepLinkValidation.path
            ? `Section 49: This broadcast pushes directly to active devices with deep link "${deepLinkValidation.path}" and cannot be undone.`
            : 'Section 49: Sending a broadcast notification pushes directly to active devices and cannot be undone.'
        }
        isDangerous
        requireReason
        isLoading={sendMutation.isPending}
        onConfirm={handleConfirmSend}
        onClose={() => setShowConfirm(false)}
      />
    </Box>
  );
}
