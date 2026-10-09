'use client';

import React from 'react';
import { Button } from '@mui/material';
import { CheckCircle, Pencil, Copy, Trash2 } from 'lucide-react';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { BrandItem } from '@/core/types/admin';

export const BrandItemRowActions: React.FC<{
  row: BrandItem;
  excluded: boolean;
  onEdit: (brand: BrandItem) => void;
  onDuplicate: (brand: BrandItem) => void;
  onStatusToggle: (brand: BrandItem) => void;
  onDelete: (brand: BrandItem) => void;
}> = ({ row, excluded, onEdit, onDuplicate, onStatusToggle, onDelete }) => {
  return (
    <>
      <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
        <Button
          size="small"
          color="primary"
          startIcon={<Pencil size={14} />}
          onClick={() => onEdit(row)}
        >
          Edit
        </Button>
      </PermissionGuard>
      <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
        <Button
          size="small"
          color="primary"
          startIcon={<Copy size={14} />}
          onClick={() => onDuplicate(row)}
        >
          Duplicate
        </Button>
      </PermissionGuard>
      <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
        <Button
          size="small"
          color={row.is_active ? 'success' : 'inherit'}
          disabled={excluded}
          startIcon={<CheckCircle size={14} />}
          onClick={() => onStatusToggle(row)}
        >
          {row.is_active ? 'Active' : 'Inactive'}
        </Button>
      </PermissionGuard>
      {/* Delete is hidden entirely for excluded (protected) brands — the
          contract is "no delete affordance", not a disabled button. */}
      {!excluded && (
        <PermissionGuard capability={CAPABILITIES.TAXONOMY_MANAGE}>
          <Button size="small" color="error" startIcon={<Trash2 size={14} />} onClick={() => onDelete(row)}>
            Delete
          </Button>
        </PermissionGuard>
      )}
    </>
  );
};
