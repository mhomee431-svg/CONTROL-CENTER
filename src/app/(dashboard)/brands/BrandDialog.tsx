'use client';

import React from 'react';
import {
  Box,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Alert,
  Stack,
} from '@mui/material';
import { CheckCircle } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { BrandItem } from '@/core/types/admin';

export interface BrandDialogProps {
  open: boolean;
  brand?: BrandItem | null;
  mode: 'create' | 'edit' | 'duplicate';
  sourceBrand?: BrandItem | null;
  onClose: () => void;
  onSaved: () => void;
}

export const BrandDialog: React.FC<BrandDialogProps> = ({
  open,
  brand,
  mode,
  sourceBrand,
  onClose,
  onSaved,
}) => {
  const [name, setName] = React.useState('');
  const [slug, setSlug] = React.useState('');
  const [description, setDescription] = React.useState('');
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!open) return;

    setError(null);
    if (mode === 'create') {
      setName('');
      setSlug('');
      setDescription('');
      return;
    }

    if (mode === 'edit' && brand) {
      setName(brand.name);
      setSlug(brand.slug);
      setDescription(brand.description || '');
      return;
    }

    if (mode === 'duplicate' && sourceBrand) {
      setName(`${sourceBrand.name} (Copy)`);
      setSlug(sourceBrand.slug);
      setDescription(`Copy of ${sourceBrand.name}`);
    }
  }, [open, mode, brand, sourceBrand]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!name.trim() || !slug.trim()) {
      setError('Brand Name and Slug are required.');
      return;
    }

    const payload: { name: string; slug: string; description?: string; is_active: boolean } = {
      name: name.trim(),
      slug: slug.trim(),
      description: description.trim() || undefined,
      is_active: true,
    };

    try {
      if (mode === 'create') {
        await apiClient(API_ENDPOINTS.BRANDS.CREATE, {
          method: 'POST',
          body: JSON.stringify(payload),
        });
      } else if (mode === 'edit' && brand) {
        await apiClient(API_ENDPOINTS.BRANDS.UPDATE(brand.id), {
          method: 'PATCH',
          body: JSON.stringify(payload),
        });
      } else if (mode === 'duplicate' && sourceBrand) {
        await apiClient(API_ENDPOINTS.BRANDS.CREATE, {
          method: 'POST',
          body: JSON.stringify(payload),
        });
      }
      onSaved();
      onClose();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to save brand');
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle sx={{ fontWeight: 600 }}>
        {mode === 'create'
          ? 'Register New Brand'
          : mode === 'edit'
            ? 'Edit Brand'
            : 'Duplicate Brand'}
      </DialogTitle>
      <Box component="form" onSubmit={handleSubmit}>
        <DialogContent>
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}

          <Stack spacing={2}>
            <TextField
              label="Brand Name"
              fullWidth
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
            <TextField
              label="URL Slug"
              fullWidth
              required
              value={slug}
              onChange={(e) => setSlug(e.target.value)}
              helperText="Used in canonical brand URLs; must be unique."
            />
            <TextField
              label="Description"
              fullWidth
              multiline
              rows={2}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </Stack>
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2 }}>
          <Button onClick={onClose} color="inherit">
            Cancel
          </Button>
          <Button
            type="submit"
            variant="contained"
            startIcon={<CheckCircle size={16} />}
          >
            Save
          </Button>
        </DialogActions>
      </Box>
    </Dialog>
  );
};
