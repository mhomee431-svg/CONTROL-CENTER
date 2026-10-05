'use client';

import React, { useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Alert,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  CircularProgress,
} from '@mui/material';
import { Plus } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { DeepLinkField } from '@/core/notifications/DeepLinkField';

/** A single editable field descriptor for a content resource. */
export interface ContentField {
  name: string;
  label: string;
  type?: 'text' | 'textarea' | 'select' | 'deep_link';
  required?: boolean;
  options?: Array<{ value: string; label: string }>;
  /** Default value applied on create. */
  defaultValue?: string;
  helperText?: string;
  /** Optional validation — return an error string, or null when valid. */
  validate?: (value: string) => string | null;
  /** Hide this field when creating (e.g. server-managed status). */
  createOnly?: boolean;
}

export interface ContentResourceManagerProps<T extends { id: number }> {
  title: string;
  subtitle: string;
  /** Full list endpoint. */
  listEndpoint: string;
  /** Detail/create endpoint base (used for POST/DELETE). */
  baseEndpoint: string;
  detailEndpoint: (id: number | string) => string;
  queryKey: string;
  columns: GridColDef[];
  fields: ContentField[];
  /** Field name used as the human label for confirm dialogs. */
  labelField: keyof T & string;
  searchPlaceholder?: string;
  /** Whether create is allowed (some system resources are read-only). */
  allowCreate?: boolean;
  /** Whether delete is allowed. */
  allowDelete?: boolean;
  /** Transform the draft into the POST body. */
  buildPayload?: (draft: Record<string, string>) => Record<string, unknown>;
  /** Called after a successful create/delete to invalidate extra keys. */
  extraInvalidateKeys?: string[][];
}

/**
 * Generic, backend-driven CRUD grid for content resources (banners,
 * announcements, FAQs, help content, promotional cards, system messages).
 *
 * Every mutation goes through the centralized apiClient; every write is guarded
 * by CAPABILITIES.CONTENT_MANAGE and confirmed through the reason-capturing
 * ConfirmationDialog. Deep-link fields are validated before submit.
 */
export function ContentResourceManager<T extends { id: number }>({
  title,
  subtitle,
  listEndpoint,
  baseEndpoint,
  detailEndpoint,
  queryKey,
  columns,
  fields,
  labelField,
  searchPlaceholder,
  allowCreate = true,
  allowDelete = true,
  buildPayload,
  extraInvalidateKeys = [],
}: ContentResourceManagerProps<T>) {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 50 });
  const [openCreate, setOpenCreate] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<T | null>(null);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [editingTarget, setEditingTarget] = useState<T | null>(null);

  const { data, isLoading, refetch, isError } = useQuery<{ items: T[]; total?: number }>({
    queryKey: [queryKey, paginationModel],
    queryFn: () =>
      apiClient<{ items: T[]; total?: number }>(listEndpoint, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
    retry: false,
  });

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: [queryKey] });
    extraInvalidateKeys.forEach((key) => queryClient.invalidateQueries({ queryKey: key }));
  };

  const createMutation = useMutation({
    mutationFn: (payload: Record<string, unknown>) =>
      apiClient(baseEndpoint, { method: 'POST', body: JSON.stringify(payload) }),
    onSuccess: () => {
      setOpenCreate(false);
      setDraft({});
      invalidate();
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, payload }: { id: number; payload: Record<string, unknown> }) =>
      apiClient(detailEndpoint(id), { method: 'PUT', body: JSON.stringify(payload) }),
    onSuccess: () => {
      setOpenCreate(false);
      setEditingTarget(null);
      setDraft({});
      invalidate();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => apiClient(detailEndpoint(id), { method: 'DELETE' }),
    onSuccess: () => {
      setDeleteTarget(null);
      invalidate();
    },
  });

  const openCreateDialog = () => {
    const initial: Record<string, string> = {};
    fields.forEach((f) => {
      initial[f.name] = f.defaultValue ?? '';
    });
    setDraft(initial);
    setEditingTarget(null);
    setFormError(null);
    setOpenCreate(true);
  };

  /** Seed the dialog from an existing row so it becomes an edit form. */
  const openEditDialog = (row: T) => {
    const source = row as unknown as Record<string, unknown>;
    const initial: Record<string, string> = {};
    fields.forEach((f) => {
      const value = source[f.name];
      initial[f.name] = value === null || value === undefined ? '' : String(value);
    });
    setDraft(initial);
    setEditingTarget(row);
    setFormError(null);
    setOpenCreate(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    // Validate all fields (required + custom validators) before hitting the API.
    for (const field of fields) {
      const value = (draft[field.name] ?? '').trim();
      if (field.required && !value) {
        setFormError(`${field.label} is required.`);
        return;
      }
      if (field.validate) {
        const err = field.validate(value);
        if (err) {
          setFormError(err);
          return;
        }
      }
    }
    setFormError(null);
    const payload = buildPayload ? buildPayload(draft) : { ...draft };
    try {
      if (editingTarget) {
        await updateMutation.mutateAsync({ id: editingTarget.id, payload });
      } else {
        await createMutation.mutateAsync(payload);
      }
    } catch (err: unknown) {
      setFormError(err instanceof Error ? err.message : 'Failed to save content.');
    }
  };

  const columnsWithActions: GridColDef[] = useMemo(() => {
    if (!allowDelete) return columns;
    return [
      ...columns,
      {
        field: '__actions',
        headerName: 'Actions',
        width: 170,
        sortable: false,
        filterable: false,
        renderCell: (params) => {
          const row = params.row as T;
          return (
            <Box sx={{ display: 'flex', gap: 0.5 }}>
              <PermissionGuard capability={CAPABILITIES.CONTENT_MANAGE}>
                <Button size="small" onClick={() => openEditDialog(row)}>
                  Edit
                </Button>
              </PermissionGuard>
              <PermissionGuard capability={CAPABILITIES.CONTENT_MANAGE}>
                <Button size="small" color="error" onClick={() => setDeleteTarget(row)}>
                  Delete
                </Button>
              </PermissionGuard>
            </Box>
          );
        },
      },
    ];
    // openEditDialog only reads stable props/state setters, so it is safe to omit.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [columns, allowDelete]);

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3, flexWrap: 'wrap', gap: 2 }}>
        <Box>
          <Typography variant="h5" sx={{ fontWeight: 700 }}>
            {title}
          </Typography>
          <Typography variant="body2" color="text.secondary">
            {subtitle}
          </Typography>
        </Box>
        {allowCreate && (
          <PermissionGuard capability={CAPABILITIES.CONTENT_MANAGE}>
            <Button variant="contained" startIcon={<Plus size={16} />} onClick={openCreateDialog}>
              Add New
            </Button>
          </PermissionGuard>
        )}
      </Box>

      {isError && (
        <Alert severity="warning" sx={{ mb: 2 }}>
          The content API endpoint for this resource is not available on the backend, or you lack access.
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columnsWithActions}
        totalRows={data?.total ?? data?.items?.length ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder={searchPlaceholder}
        onRefresh={() => refetch()}
      />

      <Dialog open={openCreate} onClose={() => setOpenCreate(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 600 }}>
          {editingTarget
            ? `Edit ${title.replace(/ Management$/, '')}`
            : `Create ${title.replace(/ Management$/, '')}`}
        </DialogTitle>
        <Box component="form" onSubmit={handleSubmit}>
          <DialogContent>
            {formError && (
              <Alert severity="error" sx={{ mb: 2 }}>
                {formError}
              </Alert>
            )}
            {fields.map((field) => {
              const value = draft[field.name] ?? '';
              const setValue = (v: string) => setDraft((prev) => ({ ...prev, [field.name]: v }));

              if (field.type === 'deep_link') {
                return <DeepLinkField key={field.name} label={field.label} value={value} onChange={setValue} />;
              }
              if (field.type === 'select') {
                return (
                  <FormControl key={field.name} fullWidth margin="dense">
                    <InputLabel>{field.label}</InputLabel>
                    <Select value={value} label={field.label} onChange={(e) => setValue(e.target.value)}>
                      {(field.options || []).map((opt) => (
                        <MenuItem key={opt.value} value={opt.value}>
                          {opt.label}
                        </MenuItem>
                      ))}
                    </Select>
                  </FormControl>
                );
              }
              return (
                <TextField
                  key={field.name}
                  margin="dense"
                  label={field.label}
                  fullWidth
                  required={field.required}
                  multiline={field.type === 'textarea'}
                  rows={field.type === 'textarea' ? 3 : undefined}
                  value={value}
                  helperText={field.helperText}
                  onChange={(e) => setValue(e.target.value)}
                />
              );
            })}
          </DialogContent>
          <DialogActions sx={{ px: 3, pb: 2 }}>
            <Button
              onClick={() => {
                setOpenCreate(false);
                setEditingTarget(null);
                setDraft({});
              }}
              color="inherit"
            >
              Cancel
            </Button>
            <Button type="submit" variant="contained" disabled={createMutation.isPending || updateMutation.isPending}>
              {createMutation.isPending || updateMutation.isPending ? (
                <CircularProgress size={18} color="inherit" />
              ) : editingTarget ? (
                'Save Changes'
              ) : (
                'Save'
              )}
            </Button>
          </DialogActions>
        </Box>
      </Dialog>

      {deleteTarget && (
        <ConfirmationDialog
          open={Boolean(deleteTarget)}
          title={`Delete ${title.replace(/ Management$/, '')}`}
          affectedItem={String((deleteTarget as Record<string, unknown>)[labelField] ?? `#${deleteTarget.id}`)}
          consequence="This content will be removed from the platform. This action is recorded in the audit log."
          isDangerous
          requireReason
          isLoading={deleteMutation.isPending}
          onConfirm={async () => {
            await deleteMutation.mutateAsync(deleteTarget.id);
          }}
          onClose={() => setDeleteTarget(null)}
        />
      )}
    </Box>
  );
}