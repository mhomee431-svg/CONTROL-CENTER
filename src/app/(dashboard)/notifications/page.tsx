'use client';

import React, { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
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
  CircularProgress,
} from '@mui/material';
import { Send, Bell } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';

export default function NotificationsPage() {
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [targetRole, setTargetRole] = useState<'customer' | 'shopkeeper' | 'all'>('all');
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [showConfirm, setShowConfirm] = useState(false);

  const sendMutation = useMutation({
    mutationFn: (payload: { title: string; body: string; notification_type: string; target_role?: string }) =>
      apiClient(API_ENDPOINTS.NOTIFICATIONS.SEND, {
        method: 'POST',
        body: JSON.stringify(payload),
      }),
    onSuccess: () => {
      setTitle('');
      setBody('');
      setSuccessMsg('Broadcast notification sent successfully.');
    },
  });

  const handlePreSend = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !body.trim()) return;
    setShowConfirm(true);
  };

  const handleConfirmSend = async () => {
    await sendMutation.mutateAsync({
      title,
      body,
      notification_type: 'ADMIN_BROADCAST',
      target_role: targetRole === 'all' ? undefined : targetRole,
    });
  };

  return (
    <Box sx={{ maxWidth: 800 }}>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Notification Broadcast Composer
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Section 48, 49, 50: Dispatch platform announcements and targeted notifications.
        </Typography>
      </Box>

      {successMsg && (
        <Alert severity="success" sx={{ mb: 3 }}>
          {successMsg}
        </Alert>
      )}

      <Card>
        <CardContent sx={{ p: 3 }}>
          <Box component="form" onSubmit={handlePreSend}>
            <FormControl fullWidth margin="dense" sx={{ mb: 2 }}>
              <InputLabel>Audience Scope</InputLabel>
              <Select
                value={targetRole}
                label="Audience Scope"
                onChange={(e) => setTargetRole(e.target.value as any)}
              >
                <MenuItem value="all">All Platform Users</MenuItem>
                <MenuItem value="customer">Customers Only</MenuItem>
                <MenuItem value="shopkeeper">Shopkeepers Only</MenuItem>
              </Select>
            </FormControl>

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
              sx={{ mb: 3 }}
            />

            <Button
              type="submit"
              variant="contained"
              size="large"
              startIcon={<Send size={18} />}
              disabled={sendMutation.isPending || !title.trim() || !body.trim()}
            >
              {sendMutation.isPending ? 'Broadcasting...' : 'Review & Send Broadcast'}
            </Button>
          </Box>
        </CardContent>
      </Card>

      {/* Confirmation Modal */}
      <ConfirmationDialog
        open={showConfirm}
        title="Confirm High-Impact Broadcast"
        affectedItem={`Target: ${targetRole.toUpperCase()}`}
        consequence="Section 49: Sending a broadcast notification pushes directly to active devices and cannot be undone."
        isDangerous
        requireReason
        isLoading={sendMutation.isPending}
        onConfirm={handleConfirmSend}
        onClose={() => setShowConfirm(false)}
      />
    </Box>
  );
}
