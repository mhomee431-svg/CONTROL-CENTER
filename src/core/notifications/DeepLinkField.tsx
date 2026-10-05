'use client';

import React from 'react';
import { TextField, InputAdornment, Typography, Box } from '@mui/material';
import { Link2, ShieldCheck, ShieldAlert } from 'lucide-react';
import { validateExplicitUrl } from './deepLink';

export interface DeepLinkFieldProps {
  value: string;
  onChange: (value: string) => void;
  /** Field label. Defaults to "Deep Link (optional)". */
  label?: string;
  disabled?: boolean;
}

/**
 * Safe deep-link input for content/announcement editors.
 *
 * Operators may only enter a root-relative admin path. The field validates on
 * every keystroke via the centralized {@link validateExplicitUrl} gate and
 * refuses to present an invalid value as acceptable.
 */
export const DeepLinkField: React.FC<DeepLinkFieldProps> = ({
  value,
  onChange,
  label = 'Deep Link (optional)',
  disabled = false,
}) => {
  const result = value.trim() ? validateExplicitUrl(value) : null;
  const invalid = result !== null && !result.valid;

  return (
    <Box sx={{ mt: 1, mb: 1 }}>
      <TextField
        margin="dense"
        label={label}
        fullWidth
        value={value}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
        error={invalid}
        placeholder="/products/12"
        helperText={
          invalid
            ? result?.message
            : 'Root-relative admin path only (e.g. /products/12). External URLs are blocked.'
        }
        slotProps={{
          input: {
            startAdornment: (
              <InputAdornment position="start">
                <Link2 size={16} color="#64748B" />
              </InputAdornment>
            ),
            endAdornment: value.trim() ? (
              <InputAdornment position="end">
                {result?.valid ? (
                  <ShieldCheck size={16} color="#10B981" />
                ) : (
                  <ShieldAlert size={16} color="#EF4444" />
                )}
              </InputAdornment>
            ) : null,
          },
        }}
      />
      {value.trim() && result?.valid && result.path && (
        <Typography variant="caption" color="success.main" sx={{ ml: 1 }}>
          Validated route: {result.path}
        </Typography>
      )}
    </Box>
  );
};