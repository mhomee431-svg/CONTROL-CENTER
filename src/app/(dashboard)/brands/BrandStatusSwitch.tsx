'use client';

import React from 'react';
import { Button } from '@mui/material';
import { Hourglass, LogOut } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { BrandItem } from '@/core/types/admin';

export const BrandStatusSwitch: React.FC<{
  brand: BrandItem;
  onSaved: () => void;
  excluded: boolean;
}> = ({ brand, onSaved, excluded }) => {
  const [saving, setSaving] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  const handleToggle = async () => {
    if (excluded) return;
    setSaving(true);
    setError(null);
    try {
      await apiClient(API_ENDPOINTS.BRANDS.UPDATE(brand.id), {
        method: 'PATCH',
        body: JSON.stringify({ is_active: !brand.is_active }),
      });
      onSaved();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to update status');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Button
      variant="outlined"
      color={brand.is_active ? 'success' : 'inherit'}
      disabled={saving || excluded}
      startIcon={saving ? <Hourglass size={16} /> : null}
      onClick={handleToggle}
    >
      {brand.is_active ? 'Deactivate' : 'Activate'}
    </Button>
  );
};
