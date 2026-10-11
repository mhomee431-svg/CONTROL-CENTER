'use client';

import React, { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Button,
  Chip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  MenuItem,
  FormControl,
  InputLabel,
  Select,
  Alert,
  Snackbar,
  Tooltip,
} from '@mui/material';
import {
  ShieldCheck,
  UserPlus,
  KeyRound,
  UserX,
  UserCheck,
  ShieldAlert,
  Pencil,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AdminUserRecord } from '@/core/types/admin';
import {
  createAdminUser,
  changeAdminUserRole,
  resetAdminAccess,
  setAdminUserStatus,
} from '@/core/api/adminUsers';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';

/**
 * ADMIN USER MANAGEMENT.
 *
 * Columns: Admin Users · Roles · Permissions · Status · Last Active.
 * Actions: Create · Deactivate / Reactivate · Change role · Reset access.
 *
 * Every high-impact action is routed through <ConfirmationDialog />, which
 * captures the operator's reason before the mutation fires — the backend
 * records that reason in the audit trail, so a role change or an access reset
 * is traceable back to a person and a justification.
 *
 * The page is gated behind `admins.read`. Individual actions carry their own
 * finer capabilities (`admins.manage`, `admins.roles.manage`, reset access) so
 * a read-only governance viewer sees the registry without being able to alter
 * it.
 */

const STATUS_OPTIONS = [
  { value: '', label: 'All Statuses' },
  { value: 'ACTIVE', label: 'Active' },
  { value: 'INACTIVE', label: 'Deactivated' },
];

type PendingAction =
  | { kind: 'deactivate'; target: AdminUserRecord }
  | { kind: 'reactivate'; target: AdminUserRecord }
  | null;

export default function AdminUsersPage() {
  const queryClient = useQueryClient();
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');

  const [createOpen, setCreateOpen] = useState(false);
  const [roleTarget, setRoleTarget] = useState<AdminUserRecord | null>(null);
  const [resetTarget, setResetTarget] = useState<AdminUserRecord | null>(null);
  const [pendingAction, setPendingAction] = useState<PendingAction>(null);
  const [temporaryPassword, setTemporaryPassword] = useState<string | null>(null);

  const { data, isLoading, isError, refetch } = useQuery<{ items: AdminUserRecord[]; total: number }>({
    queryKey: ['admin', 'admin-users', { page: paginationModel.page, pageSize: paginationModel.pageSize, search, statusFilter }],
    queryFn: () =>
      apiClient<{ items: AdminUserRecord[]; total: number }>(API_ENDPOINTS.ADMIN_USERS.LIST, {
        params: {
          search: search || undefined,
          status: statusFilter || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['admin', 'admin-users'] });

  const statusMutation = useMutation({
    mutationFn: ({ id, isActive, reason }: { id: number; isActive: boolean; reason: string }) =>
      setAdminUserStatus(id, isActive, reason),
    onSuccess: () => {
      invalidate();
      setPendingAction(null);
    },
  });

  const columns: GridColDef[] = [
    {
      field: 'username',
      headerName: 'Administrator',
      flex: 1.4,
      minWidth: 180,
      renderCell: (params) => {
        const row = params.row as unknown as AdminUserRecord;
        return (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <ShieldCheck size={16} color="#0F52BA" />
            <Box>
              <Typography variant="body2" sx={{ fontWeight: 600 }}>
                {row.name || row.username}
              </Typography>
              <Typography variant="caption" color="text.secondary">
                @{row.username}
              </Typography>
            </Box>
          </Box>
        );
      },
    },
    {
      field: 'role_name',
      headerName: 'Role',
      width: 190,
      renderCell: (params) => {
        const row = params.row as unknown as AdminUserRecord;
        return (
          <Chip
            size="small"
            label={row.is_owner ? 'OWNER' : (row.role_name || '—').replace(/_/g, ' ')}
            color={row.is_owner ? 'primary' : 'default'}
            sx={{ fontWeight: 600 }}
          />
        );
      },
    },
    {
      field: 'permissions',
      headerName: 'Permissions',
      flex: 1.4,
      minWidth: 220,
      sortable: false,
      renderCell: (params) => {
        const row = params.row as unknown as AdminUserRecord;
        const perms = row.permissions ?? [];
        if (row.is_owner) {
          return <Typography variant="body2">All capabilities (owner)</Typography>;
        }
        if (perms.length === 0) {
          return (
            <Typography variant="body2" sx={{ color: '#94A3B8', fontStyle: 'italic' }}>
              Role default
            </Typography>
          );
        }
        const shown = perms.slice(0, 3);
        return (
          <Tooltip title={perms.join(', ')}>
            <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap' }}>
              {shown.map((p) => (
                <Chip key={p} size="small" variant="outlined" label={p} />
              ))}
              {perms.length > shown.length && (
                <Chip size="small" variant="outlined" label={`+${perms.length - shown.length}`} />
              )}
            </Box>
          </Tooltip>
        );
      },
    },
    {
      field: 'is_active',
      headerName: 'Status',
      width: 130,
      renderCell: (params) => (
        <StatusBadge status={(params.row as AdminUserRecord).is_active ? 'ACTIVE' : 'INACTIVE'} />
      ),
    },
    {
      field: 'last_login',
      headerName: 'Last Active',
      width: 180,
      valueFormatter: (value) => (value ? new Date(value as string).toLocaleString() : 'Never'),
    },
    {
      field: 'actions',
      headerName: 'Actions',
      width: 340,
      sortable: false,
      renderCell: (params) => {
        const row = params.row as unknown as AdminUserRecord;
        return (
          <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
            <PermissionGuard capability={CAPABILITIES.ADMINS_ROLES_MANAGE} fallback={null}>
              <Button
                size="small"
                variant="outlined"
                startIcon={<Pencil size={14} />}
                disabled={row.is_owner}
                onClick={(e) => {
                  e.stopPropagation();
                  setRoleTarget(row);
                }}
              >
                Change role
              </Button>
            </PermissionGuard>

            <PermissionGuard capability={CAPABILITIES.SECURITY_MANAGE} fallback={null}>
              <Button
                size="small"
                variant="outlined"
                startIcon={<KeyRound size={14} />}
                onClick={(e) => {
                  e.stopPropagation();
                  setResetTarget(row);
                }}
              >
                Reset access
              </Button>
            </PermissionGuard>

            <PermissionGuard capability={CAPABILITIES.ADMINS_MANAGE} fallback={null}>
              {row.is_active ? (
                <Button
                  size="small"
                  color="error"
                  variant="outlined"
                  startIcon={<UserX size={14} />}
                  disabled={row.is_owner}
                  onClick={(e) => {
                    e.stopPropagation();
                    setPendingAction({ kind: 'deactivate', target: row });
                  }}
                >
                  Deactivate
                </Button>
              ) : (
                <Button
                  size="small"
                  color="success"
                  variant="outlined"
                  startIcon={<UserCheck size={14} />}
                  onClick={(e) => {
                    e.stopPropagation();
                    setPendingAction({ kind: 'reactivate', target: row });
                  }}
                >
                  Reactivate
                </Button>
              )}
            </PermissionGuard>
          </Box>
        );
      },
    },
  ];

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[{ label: 'Dashboard', href: ROUTES.DASHBOARD }, { label: 'Admin Users' }]}
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
            Admin User Management
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Manage administrators, their roles, permissions and access. Every change is recorded in
            the audit log with the operator&apos;s reason.
          </Typography>
        </Box>
        <PermissionGuard capability={CAPABILITIES.ADMINS_MANAGE} fallback={null}>
          <Button variant="contained" startIcon={<UserPlus size={16} />} onClick={() => setCreateOpen(true)}>
            Create Admin User
          </Button>
        </PermissionGuard>
      </Box>

      <Box sx={{ mb: 2, display: 'flex', gap: 2, flexWrap: 'wrap' }}>
        <FormControl size="small" sx={{ minWidth: 170 }}>
          <InputLabel>Status</InputLabel>
          <Select value={statusFilter} label="Status" onChange={(e) => setStatusFilter(e.target.value)}>
            {STATUS_OPTIONS.map((o) => (
              <MenuItem key={o.value} value={o.value}>
                {o.label}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
      </Box>

      <AdminDataGrid
        rows={(data?.items || []) as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        searchPlaceholder="Search administrators..."
        searchValue={search}
        onSearchChange={setSearch}
        onRefresh={() => refetch()}
        error={isError}
      />

      <CreateAdminDialog
        open={createOpen}
        onClose={() => setCreateOpen(false)}
        onCreated={invalidate}
      />

      <ChangeRoleDialog
        target={roleTarget}
        onClose={() => setRoleTarget(null)}
        onChanged={invalidate}
      />

      <ResetAccessDialog
        target={resetTarget}
        onClose={() => setResetTarget(null)}
        onReset={(tempPassword) => {
          invalidate();
          if (tempPassword) setTemporaryPassword(tempPassword);
        }}
      />

      {pendingAction && (
        <ConfirmationDialog
          open={Boolean(pendingAction)}
          title={
            pendingAction.kind === 'deactivate'
              ? `Deactivate ${pendingAction.target.username}`
              : `Reactivate ${pendingAction.target.username}`
          }
          affectedItem={`${pendingAction.target.name || pendingAction.target.username} (${pendingAction.target.role_name})`}
          actionSummary={`Action: ${pendingAction.kind === 'deactivate' ? 'DEACTIVATE' : 'REACTIVATE'}`}
          consequence={
            pendingAction.kind === 'deactivate'
              ? 'This administrator will be signed out immediately and will be unable to log in until reactivated.'
              : 'This administrator will be able to log in again.'
          }
          isDangerous={pendingAction.kind === 'deactivate'}
          requireReason
          isLoading={statusMutation.isPending}
          onConfirm={async (reason) => {
            await statusMutation.mutateAsync({
              id: pendingAction.target.id,
              isActive: pendingAction.kind === 'reactivate',
              reason,
            });
          }}
          onClose={() => setPendingAction(null)}
        />
      )}

      <Snackbar
        open={Boolean(temporaryPassword)}
        autoHideDuration={null}
        onClose={() => setTemporaryPassword(null)}
        anchorOrigin={{ vertical: 'top', horizontal: 'center' }}
      >
        <Alert severity="warning" onClose={() => setTemporaryPassword(null)} sx={{ maxWidth: 520 }}>
          <Typography variant="subtitle2" sx={{ fontWeight: 700 }}>
            Temporary password generated
          </Typography>
          <Typography variant="body2" sx={{ fontFamily: 'monospace', my: 1, wordBreak: 'break-all' }}>
            {temporaryPassword}
          </Typography>
          <Typography variant="caption">
            Copy it now and hand it over securely. It is shown once and never stored in plain text.
          </Typography>
        </Alert>
      </Snackbar>
    </Box>
  );
}

/* -------------------------------------------------------------------------- */
/* Create                                                                     */
/* -------------------------------------------------------------------------- */

interface CreateAdminDialogProps {
  open: boolean;
  onClose: () => void;
  onCreated: () => void;
}

function CreateAdminDialog({ open, onClose, onCreated }: CreateAdminDialogProps) {
  const [username, setUsername] = useState('');
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState('SUPPORT_ADMIN');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  const roles = ['SUPER_ADMIN', 'ADMIN', 'VERIFICATION_ADMIN', 'OPERATIONS_ADMIN', 'SUPPORT_ADMIN', 'CONTENT_ADMIN', 'ANALYST'];

  const mutation = useMutation({
    mutationFn: () =>
      createAdminUser({ username: username.trim(), password, name: name.trim() || undefined, email: email.trim() || undefined, role_name: role, reason: reason.trim() || undefined }),
    onSuccess: () => {
      onCreated();
      reset();
      onClose();
    },
    onError: (err: unknown) => {
      setError(err instanceof Error ? err.message : 'Could not create the administrator.');
    },
  });

  function reset() {
    setUsername('');
    setName('');
    setEmail('');
    setPassword('');
    setRole('SUPPORT_ADMIN');
    setReason('');
    setError(null);
  }

  const valid = username.trim().length >= 3 && password.length >= 8;

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>Create Admin User</DialogTitle>
      <DialogContent>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}
        <TextField label="Username" value={username} onChange={(e) => setUsername(e.target.value)} fullWidth required sx={{ mt: 1 }} />
        <TextField label="Full name" value={name} onChange={(e) => setName(e.target.value)} fullWidth sx={{ mt: 2 }} />
        <TextField label="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} fullWidth sx={{ mt: 2 }} />
        <TextField
          label="Initial password (min 8 characters)"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          fullWidth
          required
          sx={{ mt: 2 }}
        />
        <TextField select label="Role" value={role} onChange={(e) => setRole(e.target.value)} fullWidth sx={{ mt: 2 }}>
          {roles.map((r) => (
            <MenuItem key={r} value={r}>
              {r.replace(/_/g, ' ')}
            </MenuItem>
          ))}
        </TextField>
        <TextField
          label="Reason (recorded in audit log)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          fullWidth
          multiline
          rows={2}
          sx={{ mt: 2 }}
        />
        <Alert severity="info" sx={{ mt: 2 }}>
          The new administrator starts active with the selected role&apos;s default permissions.
        </Alert>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={mutation.isPending}>
          Cancel
        </Button>
        <Button variant="contained" disabled={!valid || mutation.isPending} onClick={() => mutation.mutate()}>
          {mutation.isPending ? 'Creating…' : 'Create'}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Change role                                                                */
/* -------------------------------------------------------------------------- */

interface ChangeRoleDialogProps {
  target: AdminUserRecord | null;
  onClose: () => void;
  onChanged: () => void;
}

function ChangeRoleDialog({ target, onClose, onChanged }: ChangeRoleDialogProps) {
  const [role, setRole] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  const roles = ['SUPER_ADMIN', 'ADMIN', 'VERIFICATION_ADMIN', 'OPERATIONS_ADMIN', 'SUPPORT_ADMIN', 'CONTENT_ADMIN', 'ANALYST'];

  React.useEffect(() => {
    setRole(target?.role_name ?? 'SUPPORT_ADMIN');
    setReason('');
    setError(null);
  }, [target]);

  const mutation = useMutation({
    mutationFn: () => changeAdminUserRole(target!.id, role, reason.trim()),
    onSuccess: () => {
      onChanged();
      onClose();
    },
    onError: (err: unknown) => {
      setError(err instanceof Error ? err.message : 'Could not change the role.');
    },
  });

  return (
    <Dialog open={Boolean(target)} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>Change role — {target?.username}</DialogTitle>
      <DialogContent>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}
        <Alert severity="warning" icon={<ShieldAlert size={18} />} sx={{ mt: 1, mb: 2 }}>
          Changing the role replaces this administrator&apos;s permission grants with the new role&apos;s
          defaults. A downgrade removes the previous privileges immediately.
        </Alert>
        <TextField select label="New role" value={role} onChange={(e) => setRole(e.target.value)} fullWidth>
          {roles.map((r) => (
            <MenuItem key={r} value={r}>
              {r.replace(/_/g, ' ')}
            </MenuItem>
          ))}
        </TextField>
        <TextField
          label="Reason (recorded in audit log)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          fullWidth
          multiline
          rows={2}
          required
          sx={{ mt: 2 }}
        />
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={mutation.isPending}>
          Cancel
        </Button>
        <Button
          variant="contained"
          disabled={!role || !reason.trim() || mutation.isPending || role === target?.role_name}
          onClick={() => mutation.mutate()}
        >
          {mutation.isPending ? 'Saving…' : 'Change role'}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

/* -------------------------------------------------------------------------- */
/* Reset access                                                               */
/* -------------------------------------------------------------------------- */

interface ResetAccessDialogProps {
  target: AdminUserRecord | null;
  onClose: () => void;
  onReset: (temporaryPassword: string | null) => void;
}

function ResetAccessDialog({ target, onClose, onReset }: ResetAccessDialogProps) {
  const [newPassword, setNewPassword] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  React.useEffect(() => {
    setNewPassword('');
    setReason('');
    setError(null);
  }, [target]);

  const mutation = useMutation({
    mutationFn: () => resetAdminAccess(target!.id, { newPassword: newPassword.trim() || undefined, reason: reason.trim() }),
    onSuccess: (res) => {
      onReset(res.temporary_password ?? null);
      onClose();
    },
    onError: (err: unknown) => {
      setError(err instanceof Error ? err.message : 'Could not reset access.');
    },
  });

  return (
    <Dialog open={Boolean(target)} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>Reset access — {target?.username}</DialogTitle>
      <DialogContent>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {error}
          </Alert>
        )}
        <Alert severity="warning" icon={<ShieldAlert size={18} />} sx={{ mt: 1, mb: 2 }}>
          This rotates the password and signs the administrator out of all active sessions. Leave the
          password blank to have the server generate a one-time password.
        </Alert>
        <TextField
          label="New password (optional, min 8 chars)"
          type="password"
          value={newPassword}
          onChange={(e) => setNewPassword(e.target.value)}
          fullWidth
        />
        <TextField
          label="Reason (recorded in audit log)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          fullWidth
          multiline
          rows={2}
          required
          sx={{ mt: 2 }}
        />
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={mutation.isPending}>
          Cancel
        </Button>
        <Button
          variant="contained"
          color="warning"
          disabled={!reason.trim() || mutation.isPending || (newPassword.length > 0 && newPassword.length < 8)}
          onClick={() => mutation.mutate()}
        >
          {mutation.isPending ? 'Resetting…' : 'Reset access'}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
