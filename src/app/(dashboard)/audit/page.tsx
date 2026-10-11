'use client';

import React, { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { GridColDef, GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Typography,
  Chip,
  MenuItem,
  Select,
  FormControl,
  InputLabel,
  TextField,
  IconButton,
  Tooltip,
  Button,
  Drawer,
  Divider,
  Alert,
} from '@mui/material';
import {
  FileText,
  Shield,
  Search as SearchIcon,
  Copy as CopyIcon,
  X as CloseIcon,
  Eye as EyeIcon,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { AuditLogItem } from '@/core/types/admin';
import { AdminDataGrid } from '@/core/components/AdminDataGrid';
import { StatusBadge } from '@/core/components/StatusBadge';
import {
  resolveAuditEntry,
  resolveAuditChanges,
  type ResolvedAuditEntry,
} from '@/core/audit/auditLogs';

/**
 * AUDIT LOG CENTER.
 *
 * Every sensitive administrative action must be traceable. Each row shows, at
 * minimum: the admin, the action, the entity and its id, the timestamp, and —
 * where the backend supplies them — the operator's reason, the outcome, a
 * request/correlation id, and a before/after diff.
 *
 * The backend stores this as an append-only `AuditLog` row with a free-form
 * `details` JSON blob. `resolveAuditEntry` (see core/audit/auditLogs.ts) turns
 * that into the columns below, preferring first-class fields when a backend
 * publishes them and falling back to well-known keys inside `details`. A value
 * the backend did not send renders as "Not reported" rather than being
 * invented, so an operator can tell "no reason was recorded" apart from "the
 * UI did not show me the reason".
 */

const ENTITY_OPTIONS = [
  { value: 'shop', label: 'Business / Shop' },
  { value: 'user', label: 'Customer / User' },
  { value: 'product', label: 'Product' },
  { value: 'category', label: 'Category' },
  { value: 'brand', label: 'Brand' },
  { value: 'offer', label: 'Offer' },
  { value: 'notification', label: 'Notification' },
  { value: 'setting', label: 'System Setting' },
  { value: 'feature_flag', label: 'Feature Flag' },
  { value: 'complaint', label: 'Support Ticket' },
  { value: 'review', label: 'Review' },
];

const NOT_REPORTED = 'Not reported';

function formatTimestamp(value: string | null): string {
  if (!value) return NOT_REPORTED;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return NOT_REPORTED;
  return d.toLocaleString();
}

/** A dimmed placeholder so "the backend did not send this" is visually distinct. */
function NotReported() {
  return (
    <Typography variant="body2" sx={{ color: '#94A3B8', fontStyle: 'italic' }}>
      {NOT_REPORTED}
    </Typography>
  );
}

export default function AuditLogsPage() {
  const [paginationModel, setPaginationModel] = useState<GridPaginationModel>({
    page: 0,
    pageSize: 25,
  });
  const [entityFilter, setEntityFilter] = useState('');
  const [actionFilter, setActionFilter] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [severityFilter, setSeverityFilter] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<ResolvedAuditEntry | null>(null);
  const [copyState, setCopyState] = useState<'idle' | 'copied' | 'error'>('idle');

  // Distinct action names for the filter. A failure here degrades to a free-text
  // filter rather than blocking the trail, which must always be readable.
  const { data: actionsData } = useQuery<{ items: string[] }>({
    queryKey: ['admin', 'audit-actions'],
    queryFn: () => apiClient<{ items: string[] }>(API_ENDPOINTS.AUDIT.ACTIONS),
    staleTime: 5 * 60 * 1000,
  });

  const { data, isLoading, isError, refetch } = useQuery<{
    items: AuditLogItem[];
    total: number;
  }>({
    queryKey: [
      'admin',
      'audit-logs',
      {
        page: paginationModel.page,
        pageSize: paginationModel.pageSize,
        entityFilter,
        actionFilter,
        statusFilter,
        severityFilter,
        dateFrom,
        dateTo,
        search,
      },
    ],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[]; total: number }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: {
          entity_type: entityFilter || undefined,
          action: actionFilter || undefined,
          status: statusFilter || undefined,
          severity: severityFilter || undefined,
          date_from: dateFrom || undefined,
          date_to: dateTo || undefined,
          search: search || undefined,
          limit: paginationModel.pageSize,
          offset: paginationModel.page * paginationModel.pageSize,
        },
      }),
  });

  const hasActiveFilters = Boolean(
    entityFilter || actionFilter || statusFilter || severityFilter || dateFrom || dateTo || search
  );

  const resetFilters = () => {
    setEntityFilter('');
    setActionFilter('');
    setStatusFilter('');
    setSeverityFilter('');
    setDateFrom('');
    setDateTo('');
    setSearch('');
    setPaginationModel({ page: 0, pageSize: paginationModel.pageSize });
  };

  // Resolve once per render batch rather than inside every cell renderer.
  const resolvedRows = useMemo(
    () => (data?.items ?? []).map((row) => resolveAuditEntry(row)),
    [data]
  );

  const handleCopyRequestId = async (requestId: string) => {
    try {
      await navigator.clipboard.writeText(requestId);
      setCopyState('copied');
    } catch {
      setCopyState('error');
    }
    window.setTimeout(() => setCopyState('idle'), 2000);
  };

  const columns: GridColDef[] = [
    {
      field: 'action',
      headerName: 'Admin Action',
      flex: 1.4,
      minWidth: 190,
      renderCell: (params) => (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <Shield size={16} color="#0F52BA" />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {params.value as string}
          </Typography>
        </Box>
      ),
    },
    {
      field: 'admin',
      headerName: 'Admin',
      flex: 1,
      minWidth: 140,
      renderCell: (params) => <Typography variant="body2">{params.value as string}</Typography>,
    },
    {
      field: 'entityType',
      headerName: 'Entity',
      width: 130,
      valueGetter: (_v, row) => (row as unknown as ResolvedAuditEntry).entityType,
      renderCell: (params) =>
        params.value ? (
          <Typography variant="body2" sx={{ textTransform: 'capitalize' }}>
            {params.value as string}
          </Typography>
        ) : (
          <NotReported />
        ),
    },
    {
      field: 'entityId',
      headerName: 'Entity ID',
      width: 100,
      valueGetter: (_v, row) => (row as unknown as ResolvedAuditEntry).entityId,
      renderCell: (params) =>
        params.value === null || params.value === undefined ? (
          <NotReported />
        ) : (
          <Typography variant="body2">#{String(params.value)}</Typography>
        ),
    },
    {
      field: 'reason',
      headerName: 'Reason',
      flex: 1.4,
      minWidth: 200,
      renderCell: (params) => {
        const reason = params.value as string | null;
        if (!reason) return <NotReported />;
        return (
          <Tooltip title={reason} placement="top">
            <Typography
              variant="body2"
              sx={{
                display: '-webkit-box',
                WebkitLineClamp: 2,
                WebkitBoxOrient: 'vertical',
                overflow: 'hidden',
              }}
            >
              {reason}
            </Typography>
          </Tooltip>
        );
      },
    },
    {
      field: 'severity',
      headerName: 'Severity',
      width: 120,
      renderCell: (params) => {
        const severity = params.value as string | null;
        if (!severity) return <NotReported />;
        return <StatusBadge status={severity} />;
      },
    },
    {
      field: 'result',
      headerName: 'Status / Result',
      width: 130,
      renderCell: (params) => {
        const result = params.value as string | null;
        if (!result) return <NotReported />;
        return <StatusBadge status={result} />;
      },
    },
    {
      field: 'requestId',
      headerName: 'Request / Correlation ID',
      width: 230,
      renderCell: (params) => {
        const requestId = params.value as string | null;
        if (!requestId) return <NotReported />;
        return (
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5 }}>
            <Typography
              variant="body2"
              sx={{ fontFamily: 'monospace', fontSize: '0.75rem' }}
              title={requestId}
            >
              {requestId}
            </Typography>
            <IconButton
              size="small"
              aria-label={`Copy correlation id ${requestId}`}
              onClick={(e) => {
                e.stopPropagation();
                void handleCopyRequestId(requestId);
              }}
            >
              <CopyIcon size={13} />
            </IconButton>
          </Box>
        );
      },
    },
    {
      field: 'createdAt',
      headerName: 'Timestamp',
      flex: 1.1,
      minWidth: 180,
      renderCell: (params) =>
        params.value ? (
          <Typography variant="body2">{formatTimestamp(params.value as string)}</Typography>
        ) : (
          <NotReported />
        ),
    },
    {
      field: 'changes',
      headerName: 'Before → After',
      width: 150,
      sortable: false,
      renderCell: (params) => {
        const entry = params.row as unknown as ResolvedAuditEntry;
        if (entry.changes.length === 0) {
          return (
            <Typography variant="body2" sx={{ color: '#94A3B8', fontStyle: 'italic' }}>
              Not supplied
            </Typography>
          );
        }
        return (
          <Chip
            size="small"
            label={`${entry.changes.length} field${entry.changes.length === 1 ? '' : 's'}`}
            onClick={(e) => {
              e.stopPropagation();
              setSelected(entry);
            }}
            sx={{ cursor: 'pointer' }}
          />
        );
      },
    },
    {
      field: 'inspect',
      headerName: '',
      width: 60,
      sortable: false,
      renderCell: (params) => {
        const entry = params.row as unknown as ResolvedAuditEntry;
        return (
          <Tooltip title="View full audit record">
            <IconButton
              size="small"
              aria-label={`Inspect audit record ${entry.id}`}
              onClick={(e) => {
                e.stopPropagation();
                setSelected(entry);
              }}
            >
              <EyeIcon size={15} />
            </IconButton>
          </Tooltip>
        );
      },
    },
  ];

  return (
    <Box>
      <Box sx={{ mb: 3 }}>
        <Typography variant="h5" sx={{ fontWeight: 700 }}>
          Audit Log Center
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Immutable administrative record. Every sensitive status change, approval, merge, config edit
          and broadcast is traceable to an operator, an entity, a reason and a correlation id.
        </Typography>
      </Box>

      <Box sx={{ mb: 2, display: 'flex', gap: 2, flexWrap: 'wrap', alignItems: 'center' }}>
        <TextField
          size="small"
          placeholder="Search action, admin or entity id…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          sx={{ minWidth: 260 }}
          slotProps={{
            input: {
              startAdornment: <SearchIcon size={15} color="#64748B" style={{ marginRight: 6 }} />,
            },
          }}
        />

        <FormControl size="small" sx={{ minWidth: 190 }}>
          <InputLabel>Entity type</InputLabel>
          <Select value={entityFilter} label="Entity type" onChange={(e) => setEntityFilter(e.target.value)}>
            <MenuItem value="">All Entities</MenuItem>
            {ENTITY_OPTIONS.map((opt) => (
              <MenuItem key={opt.value} value={opt.value}>
                {opt.label}
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 210 }}>
          <InputLabel>Admin action</InputLabel>
          <Select
            value={actionFilter}
            label="Admin action"
            onChange={(e) => setActionFilter(e.target.value)}
          >
            <MenuItem value="">All Actions</MenuItem>
            {(actionsData?.items ?? []).map((action) => (
              <MenuItem key={action} value={action}>
                {action}
              </MenuItem>
            ))}
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 150 }}>
          <InputLabel>Status</InputLabel>
          <Select value={statusFilter} label="Status" onChange={(e) => setStatusFilter(e.target.value)}>
            <MenuItem value="">All Statuses</MenuItem>
            <MenuItem value="SUCCESS">Success</MenuItem>
            <MenuItem value="FAILED">Failed</MenuItem>
            <MenuItem value="PARTIAL">Partial</MenuItem>
          </Select>
        </FormControl>

        <FormControl size="small" sx={{ minWidth: 150 }}>
          <InputLabel>Severity</InputLabel>
          <Select
            value={severityFilter}
            label="Severity"
            onChange={(e) => setSeverityFilter(e.target.value)}
          >
            <MenuItem value="">All Severities</MenuItem>
            <MenuItem value="INFO">Info</MenuItem>
            <MenuItem value="WARNING">Warning</MenuItem>
            <MenuItem value="CRITICAL">Critical</MenuItem>
          </Select>
        </FormControl>

        <TextField
          size="small"
          type="date"
          label="From"
          value={dateFrom}
          onChange={(e) => setDateFrom(e.target.value)}
          slotProps={{ inputLabel: { shrink: true } }}
          sx={{ width: 160 }}
        />

        <TextField
          size="small"
          type="date"
          label="To"
          value={dateTo}
          onChange={(e) => setDateTo(e.target.value)}
          slotProps={{ inputLabel: { shrink: true } }}
          sx={{ width: 160 }}
        />

        {hasActiveFilters && (
          <Button size="small" variant="text" onClick={resetFilters}>
            Reset filters
          </Button>
        )}
      </Box>

      {isError && (
        <Alert severity="error" sx={{ mb: 2 }}>
          The audit trail could not be loaded. This is a read-only governance surface — retry, and
          escalate if it keeps failing.
        </Alert>
      )}

      <AdminDataGrid
        rows={resolvedRows as unknown as Record<string, unknown>[]}
        columns={columns}
        totalRows={data?.total ?? 0}
        paginationModel={paginationModel}
        onPaginationModelChange={setPaginationModel}
        loading={isLoading}
        error={isError}
        onRefresh={() => refetch()}
        onRowClick={(params) => setSelected(params.row as unknown as ResolvedAuditEntry)}
      />

      <AuditRecordDrawer
        entry={selected}
        onClose={() => setSelected(null)}
        copyState={copyState}
        onCopy={handleCopyRequestId}
      />
    </Box>
  );
}

interface AuditRecordDrawerProps {
  entry: ResolvedAuditEntry | null;
  onClose: () => void;
  copyState: 'idle' | 'copied' | 'error';
  onCopy: (requestId: string) => void | Promise<void>;
}

/** The full, untruncated audit record, including the before/after diff. */
function AuditRecordDrawer({ entry, onClose, copyState, onCopy }: AuditRecordDrawerProps) {
  const changes = entry ? resolveAuditChanges(entry) : [];
  const detailEntries = entry?.details ? Object.entries(entry.details) : [];

  return (
    <Drawer anchor="right" open={Boolean(entry)} onClose={onClose}>
      <Box sx={{ width: { xs: '100vw', sm: 480 }, p: 3 }} role="dialog" aria-label="Audit record">
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <FileText size={18} color="#0F52BA" />
            <Typography variant="h6" sx={{ fontWeight: 700 }}>
              Audit Record
            </Typography>
          </Box>
          <IconButton size="small" onClick={onClose} aria-label="Close audit record">
            <CloseIcon size={18} />
          </IconButton>
        </Box>

        {!entry ? null : (
          <>
            <Field label="Admin Action" value={entry.action} />
            <Field label="Admin / Operator" value={entry.admin} />
            <Field label="Entity" value={entry.entityType ?? NOT_REPORTED} />
            <Field
              label="Entity ID"
              value={entry.entityId === null ? NOT_REPORTED : `#${entry.entityId}`}
            />
            <Field label="Timestamp" value={formatTimestamp(entry.createdAt)} />
            <Field label="Reason" value={entry.reason ?? NOT_REPORTED} />
            <Field label="Result" value={entry.result ?? NOT_REPORTED} />
            <Field label="Client IP" value={entry.ipAddress ?? NOT_REPORTED} />

            <Box sx={{ mb: 1.5 }}>
              <Typography variant="caption" color="text.secondary">
                Request / Correlation ID
              </Typography>
              {entry.requestId ? (
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Typography variant="body2" sx={{ fontFamily: 'monospace', wordBreak: 'break-all' }}>
                    {entry.requestId}
                  </Typography>
                  <IconButton
                    size="small"
                    aria-label="Copy correlation id"
                    onClick={() => void onCopy(entry.requestId as string)}
                  >
                    <CopyIcon size={14} />
                  </IconButton>
                </Box>
              ) : (
                <Typography variant="body2" sx={{ color: '#94A3B8', fontStyle: 'italic' }}>
                  {NOT_REPORTED}
                </Typography>
              )}
              {copyState === 'copied' && (
                <Typography variant="caption" color="success.main">
                  Copied to clipboard
                </Typography>
              )}
              {copyState === 'error' && (
                <Typography variant="caption" color="error.main">
                  Could not copy — select the id manually
                </Typography>
              )}
            </Box>

            <Divider sx={{ my: 2 }} />

            <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1 }}>
              Before → After
            </Typography>
            {changes.length === 0 ? (
              <Alert severity="info" variant="outlined">
                The backend did not supply a before/after snapshot for this event.
              </Alert>
            ) : (
              <Box component="table" sx={{ width: '100%', borderCollapse: 'collapse' }}>
                <Box component="thead">
                  <Box component="tr">
                    {['Field', 'Before', 'After'].map((h) => (
                      <Box
                        component="th"
                        key={h}
                        sx={{
                          textAlign: 'left',
                          fontSize: '0.7rem',
                          color: '#64748B',
                          borderBottom: '1px solid #E2E8F0',
                          pb: 0.5,
                        }}
                      >
                        {h}
                      </Box>
                    ))}
                  </Box>
                </Box>
                <Box component="tbody">
                  {changes.map((change) => (
                    <Box component="tr" key={change.field}>
                      <Box component="td" sx={{ py: 0.75, pr: 1, fontSize: '0.8rem', fontWeight: 600 }}>
                        {change.field}
                      </Box>
                      <Box component="td" sx={{ py: 0.75, pr: 1, fontSize: '0.8rem', color: '#B91C1C' }}>
                        {change.before ?? '—'}
                      </Box>
                      <Box component="td" sx={{ py: 0.75, fontSize: '0.8rem', color: '#15803D' }}>
                        {change.after ?? '—'}
                      </Box>
                    </Box>
                  ))}
                </Box>
              </Box>
            )}

            {detailEntries.length > 0 && (
              <>
                <Divider sx={{ my: 2 }} />
                <Typography variant="subtitle2" sx={{ fontWeight: 700, mb: 1 }}>
                  Raw Details
                </Typography>
                <Box
                  component="pre"
                  sx={{
                    fontSize: '0.72rem',
                    backgroundColor: '#F8FAFC',
                    border: '1px solid #E2E8F0',
                    borderRadius: 1,
                    p: 1.5,
                    overflowX: 'auto',
                    m: 0,
                  }}
                >
                  {JSON.stringify(entry.details, null, 2)}
                </Box>
              </>
            )}
          </>
        )}
      </Box>
    </Drawer>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return (
    <Box sx={{ mb: 1.5 }}>
      <Typography variant="caption" color="text.secondary">
        {label}
      </Typography>
      <Typography variant="body2" sx={{ wordBreak: 'break-word' }}>
        {value}
      </Typography>
    </Box>
  );
}
