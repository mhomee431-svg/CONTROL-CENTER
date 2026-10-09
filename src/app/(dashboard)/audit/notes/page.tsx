'use client';

import React, { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Button,
  TextField,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Alert,
  MenuItem,
} from '@mui/material';
import { StickyNote, Plus, Pencil, Trash2 } from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminNoteItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ROUTES } from '@/core/routes/routes';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';

const ENTITY_TYPES = ['SHOP', 'USER', 'PRODUCT', 'CATEGORY', 'SETTING'] as const;

export default function AdminNotesPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });

  const [editing, setEditing] = useState<AdminNoteItem | null>(null);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [noteText, setNoteText] = useState('');
  const [entityType, setEntityType] = useState<string>('');
  const [entityId, setEntityId] = useState<string>('');
  const [formError, setFormError] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<AdminNoteItem | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: AdminNoteItem[]; total: number }>({
    queryKey: ['admin', 'notes', { page: paginationModel.page, pageSize: paginationModel.pageSize }],
    queryFn: () =>
      apiClient<{ items: AdminNoteItem[]; total: number }>(API_ENDPOINTS.AUDIT.NOTES, {
        params: {
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['admin', 'notes'] });

  /**
   * The backend requires `entity_type` and `entity_id` together or neither, so
   * the pair is only sent when a type was chosen AND an id was typed. Sending
   * `entity_type` with no id would be rejected as half a reference.
   */
  const entityPayload = () => {
    if (!entityType || !entityId.trim()) return {};
    return { entity_type: entityType, entity_id: Number(entityId) };
  };

  const createMutation = useMutation({
    mutationFn: () =>
      apiClient(API_ENDPOINTS.AUDIT.NOTES, {
        method: 'POST',
        body: JSON.stringify({ note: noteText.trim(), ...entityPayload() }),
      }),
    onSuccess: () => {
      invalidate();
      closeDialog();
    },
  });

  const updateMutation = useMutation({
    mutationFn: (note: AdminNoteItem) =>
      apiClient(API_ENDPOINTS.AUDIT.NOTE_DETAIL(note.id), {
        method: 'PATCH',
        body: JSON.stringify({ note: noteText.trim(), ...entityPayload() }),
      }),
    onSuccess: () => {
      invalidate();
      closeDialog();
    },
  });

  const deleteMutation = useMutation({
    mutationFn: (note: AdminNoteItem) =>
      apiClient(API_ENDPOINTS.AUDIT.NOTE_DETAIL(note.id), { method: 'DELETE' }),
    onSuccess: () => {
      setDeleteTarget(null);
      invalidate();
    },
  });

  function closeDialog() {
    setDialogOpen(false);
    setEditing(null);
    setNoteText('');
    setEntityType('');
    setEntityId('');
    setFormError(null);
  }

  function openCreate() {
    setEditing(null);
    setNoteText('');
    setEntityType('');
    setEntityId('');
    setFormError(null);
    setDialogOpen(true);
  }

  function openEdit(note: AdminNoteItem) {
    setEditing(note);
    setNoteText(note.note ?? '');
    setEntityType(note.entity_type ?? '');
    setEntityId(note.entity_id != null ? String(note.entity_id) : '');
    setFormError(null);
    setDialogOpen(true);
  }

  async function submit() {
    if (!noteText.trim()) {
      setFormError('A note body is required.');
      return;
    }
    // A type without an id is half a reference; block it before the round-trip
    // so the operator gets an immediate, specific message.
    if (entityType && !entityId.trim()) {
      setFormError('Enter an Entity ID for the chosen Entity Type, or set the type to None.');
      return;
    }
    setFormError(null);
    try {
      if (editing) {
        await updateMutation.mutateAsync(editing);
      } else {
        await createMutation.mutateAsync();
      }
    } catch (err: unknown) {
      setFormError(err instanceof Error ? err.message : 'Could not save the note.');
    }
  }

  const columns: GridColDef[] = [
    { field: 'id', headerName: 'ID', width: 80 },
    {
      field: 'note',
      headerName: 'Note',
      flex: 2.5,
      minWidth: 260,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <StickyNote size={16} color="#0F52BA" />
          <Typography variant="body2">{params.value as string}</Typography>
        </Box>
      ),
    },
    { field: 'entity_type', headerName: 'Entity', width: 130 },
    { field: 'entity_id', headerName: 'Entity ID', width: 110 },
    {
      field: 'author',
      headerName: 'Author',
      width: 150,
      valueGetter: (value) => (value as string) || 'System',
    },
    {
      field: 'entity_link',
      headerName: 'Target',
      width: 160,
      sortable: false,
      valueGetter: (_, row) =>
        row.entity_type ? `${row.entity_type} #${row.entity_id}` : 'General',
    },
    {
      field: 'created_at',
      headerName: 'Created',
      width: 180,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'N/A'),
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 140,
      sortable: false,
      renderCell: (params) => {
        const note = params.row as unknown as AdminNoteItem;
        return (
          <Box sx={{ display: 'flex', gap: 0.5 }}>
            <PermissionGuard capability={CAPABILITIES.SETTINGS_MANAGE}>
              <Button
                size="small"
                aria-label={`Edit note ${note.id}`}
                onClick={(e) => {
                  e.stopPropagation();
                  openEdit(note);
                }}
              >
                <Pencil size={14} />
              </Button>
              <Button
                size="small"
                color="error"
                aria-label={`Delete note ${note.id}`}
                onClick={(e) => {
                  e.stopPropagation();
                  // Deleting a note is irreversible, so it goes through the
                  // shared confirmation dialog rather than firing on one click.
                  setDeleteTarget(note);
                }}
              >
                <Trash2 size={14} />
              </Button>
            </PermissionGuard>
          </Box>
        );
      },
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Settings', href: ROUTES.SETTINGS },
          { label: 'Admin Notes' },
        ]}
      />
      <Box
        sx={{
          mb: 3,
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-start',
          gap: 2,
          flexWrap: 'wrap',
        }}
      >
        <Box>
          <Typography variant="h5" sx={{ fontWeight: 700 }}>
            Administrative Notes
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Operator annotations attached to shops, users, products, categories and settings.
          </Typography>
        </Box>
        <PermissionGuard capability={CAPABILITIES.SETTINGS_MANAGE}>
          <Button variant="contained" startIcon={<Plus size={16} />} onClick={openCreate}>
            New Note
          </Button>
        </PermissionGuard>
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          Could not load administrative notes.
        </Alert>
      )}

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        onRefresh={() => refetch()}
      />

      <Dialog open={dialogOpen} onClose={closeDialog} fullWidth maxWidth="sm">
        <DialogTitle>{editing ? `Edit Note #${editing.id}` : 'New Administrative Note'}</DialogTitle>
        <DialogContent>
          {formError && (
            <Alert severity="error" sx={{ mt: 1 }}>
              {formError}
            </Alert>
          )}
          <TextField
            label="Note"
            value={noteText}
            onChange={(e) => setNoteText(e.target.value)}
            multiline
            minRows={3}
            fullWidth
            required
            sx={{ mt: 1 }}
          />
          <TextField
            select
            label="Entity Type"
            value={entityType}
            onChange={(e) => setEntityType(e.target.value)}
            fullWidth
            sx={{ mt: 2 }}
          >
            <MenuItem value="">None</MenuItem>
            {ENTITY_TYPES.map((t) => (
              <MenuItem key={t} value={t}>
                {t}
              </MenuItem>
            ))}
          </TextField>
          <TextField
            label="Entity ID"
            value={entityId}
            onChange={(e) => setEntityId(e.target.value)}
            type="number"
            fullWidth
            disabled={!entityType}
            helperText={
              entityType
                ? 'The record this note is attached to.'
                : 'Choose an Entity Type first — or leave as None for a general note.'
            }
            sx={{ mt: 2 }}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={closeDialog}>Cancel</Button>
          <Button
            variant="contained"
            disabled={!noteText.trim() || createMutation.isPending || updateMutation.isPending}
            onClick={submit}
          >
            Save
          </Button>
        </DialogActions>
      </Dialog>

      {/* Deleting a note is irreversible — confirmed with the operator reason. */}
      {deleteTarget && (
        <ConfirmationDialog
          open={Boolean(deleteTarget)}
          title={`Delete Note #${deleteTarget.id}`}
          affectedItem={
            deleteTarget.entity_type
              ? `${deleteTarget.entity_type} #${deleteTarget.entity_id}`
              : 'General note'
          }
          consequence="The note is removed permanently. Deletion is recorded in the audit log."
          isDangerous
          requireReason
          isLoading={deleteMutation.isPending}
          onConfirm={async () => {
            await deleteMutation.mutateAsync(deleteTarget);
          }}
          onClose={() => setDeleteTarget(null)}
        />
      )}
    </Box>
  );
}