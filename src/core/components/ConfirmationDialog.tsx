'use client';

import React, { useState } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogContentText,
  DialogActions,
  Button,
  TextField,
  Alert,
  Box,
  Typography,
  CircularProgress,
} from '@mui/material';

export interface ConfirmationDialogProps {
  open: boolean;
  title: string;
  affectedItem?: string;
  consequence?: string;
  isDangerous?: boolean;
  requireReason?: boolean;
  isLoading?: boolean;
  onConfirm: (reason: string) => Promise<void> | void;
  onClose: () => void;
}

/**
 * Section 116, 117, 187: High-Risk Operations Confirmation Modal
 * Captures explicit operator reason and outlines operational consequences.
 */
export const ConfirmationDialog: React.FC<ConfirmationDialogProps> = ({
  open,
  title,
  affectedItem,
  consequence,
  isDangerous = false,
  requireReason = true,
  isLoading = false,
  onConfirm,
  onClose,
}) => {
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  const handleConfirm = async () => {
    if (requireReason && !reason.trim()) {
      setError('Please provide an operational reason for this action.');
      return;
    }
    setError(null);
    try {
      await onConfirm(reason);
      setReason('');
      onClose();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Action failed');
    }
  };

  const handleCancel = () => {
    setReason('');
    setError(null);
    onClose();
  };

  return (
    <Dialog open={open} onClose={isLoading ? undefined : handleCancel} maxWidth="sm" fullWidth>
      <DialogTitle sx={{ fontWeight: 600, color: isDangerous ? 'error.main' : 'text.primary' }}>
        {title}
      </DialogTitle>
      <DialogContent>
        {affectedItem && (
          <Box sx={{ mb: 2 }}>
            <Typography variant="body2" color="text.secondary">
              Affected Entity:
            </Typography>
            <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
              {affectedItem}
            </Typography>
          </Box>
        )}

        {consequence && (
          <Alert severity={isDangerous ? 'error' : 'warning'} sx={{ mb: 2 }}>
            {consequence}
          </Alert>
        )}

        {requireReason && (
          <TextField
            autoFocus
            margin="dense"
            label="Reason for Action (Recorded in Audit Log)"
            type="text"
            fullWidth
            multiline
            rows={2}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            error={!!error}
            helperText={error}
            disabled={isLoading}
          />
        )}
      </DialogContent>
      <DialogActions sx={{ px: 3, pb: 2.5 }}>
        <Button onClick={handleCancel} disabled={isLoading} color="inherit">
          Cancel
        </Button>
        <Button
          onClick={handleConfirm}
          disabled={isLoading || (requireReason && !reason.trim())}
          variant="contained"
          color={isDangerous ? 'error' : 'primary'}
          startIcon={isLoading ? <CircularProgress size={16} color="inherit" /> : null}
        >
          {isLoading ? 'Processing...' : 'Confirm Action'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};
