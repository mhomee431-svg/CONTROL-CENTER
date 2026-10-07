'use client';

import React, { use, useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { GridPaginationModel } from '@mui/x-data-grid';
import {
  Box,
  Card,
  CardContent,
  Button,
  Typography,
  Divider,
  Alert,
  CircularProgress,
  Grid,
  Tabs,
  Tab,
  Table,
  TableHead,
  TableBody,
  TableRow,
  TableCell,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  TextField,
} from '@mui/material';
import {
  ArrowLeft,
  Check,
  X,
  FileWarning,
  Pause,
  Store,
  MapPin,
  User,
  UserPlus,
  FileText,
  History,
  Gavel,
} from 'lucide-react';
import { apiClient } from '@/core/api/client';
import { API_ENDPOINTS } from '@/core/api/endpoints';
import { fetchList } from '@/core/api/fetchList';
import {
  ShopItem,
  ShopDocumentItem,
  ShopkeeperDetail,
  AuditLogItem,
  AdminUserItem,
  VerificationHistoryItem,
} from '@/core/types/admin';
import { StatusBadge } from '@/core/components/StatusBadge';
import { DrillDownBreadcrumbs } from '@/core/components/DrillDownBreadcrumbs';
import { ConfirmationDialog } from '@/core/components/ConfirmationDialog';
import { PermissionGuard } from '@/core/permissions/PermissionGuard';
import { CAPABILITIES } from '@/core/permissions/permissions';
import { ROUTES } from '@/core/routes/routes';
import { stripForbiddenFields } from '@/core/privacy/masking';
import {
  DetailField,
  TabSection,
  NotReported,
  ListState,
  ExternalLink,
} from '@/core/components/BusinessDetailParts';

/**
 * One verification case, end to end: who applied, what they submitted, what
 * evidence is attached, where the business sits, how many times it has been
 * reviewed, what was decided each time, who is holding it now, and the full
 * audit trajectory. The header's four actions all land on the same audited
 * decision endpoint with an operator-written reason that the Decisions tab
 * reads back.
 */
const TABS = [
  'Shopkeeper',
  'Business',
  'Category',
  'Submitted Information',
  'Documents',
  'Location',
  'Attempts',
  'Decisions',
  'Reviewer',
  'Timeline',
] as const;

const TAB = {
  SHOPKEEPER: 0,
  BUSINESS: 1,
  CATEGORY: 2,
  SUBMITTED: 3,
  DOCUMENTS: 4,
  LOCATION: 5,
  ATTEMPTS: 6,
  DECISIONS: 7,
  REVIEWER: 8,
  TIMELINE: 9,
} as const;

/**
 * The four triage actions and the decision value each posts. Approve and
 * Reject reuse the contract the queue and Businesses registry already post.
 * Request Correction and Put On Hold go out verbatim so the backend says what
 * it supports with a 4xx — that rejection renders inside the dialog — rather
 * than the UI inventing a mapping the API never agreed to.
 */
const DECISIONS = {
  APPROVE: {
    value: 'VERIFY',
    label: 'Approve',
    capability: CAPABILITIES.SHOPS_APPROVE,
    isDangerous: false,
    consequence:
      'Approving marks this business as verified across the platform, publishing its local catalog to active shopper search.',
  },
  REJECT: {
    value: 'REJECT',
    label: 'Reject',
    capability: CAPABILITIES.SHOPS_REJECT,
    isDangerous: true,
    consequence:
      'Rejecting closes this application and notifies the shopkeeper with the recorded reason. The merchant may re-apply.',
  },
  CORRECTION: {
    value: 'REQUEST_CORRECTION',
    label: 'Request Correction',
    capability: CAPABILITIES.SHOPS_APPROVE,
    isDangerous: false,
    consequence:
      'Requesting correction sends the submission back to the shopkeeper with the recorded reason. The case waits on the merchant, not on a reviewer.',
  },
  HOLD: {
    value: 'ON_HOLD',
    label: 'Put On Hold',
    capability: CAPABILITIES.SHOPS_SUSPEND,
    isDangerous: false,
    consequence:
      'Putting the case on hold pauses all review work on it until another decision is recorded. Nothing is notified in the meantime.',
  },
} as const;

type DecisionKey = keyof typeof DECISIONS;


const fmtDate = (value?: string | null) =>
  value ? new Date(value).toLocaleDateString() : null;

const fmtDateTime = (value?: string | null) =>
  value ? new Date(value).toLocaleString() : null;

/** Pulls the operator's written reason out of an audit details payload, or out
 * of a dedicated history row that already carries it top-level. */
const reasonOf = (log: AuditLogItem | VerificationHistoryItem) => {
  if ('reason' in log && typeof log.reason === 'string' && log.reason.trim()) {
    return log.reason;
  }
  const d = ((log as AuditLogItem).details || {}) as Record<string, unknown>;
  const raw = d.reason ?? d.review_notes ?? d.review_reason ?? d.note ?? d.comment;
  return typeof raw === 'string' && raw.trim() ? raw : null;
};

/** Anything the verification pipeline wrote: submissions, reviews, decisions. */
const isVerificationEvent = (log: AuditLogItem) => /verif/i.test(log.action || '');

/** Newest ruling first for the Previous decisions table. */
const byTimeDesc = (
  a: { created_at?: string | null },
  b: { created_at?: string | null }
) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime();

export default function VerificationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();
  const queryClient = useQueryClient();
  const [tabIndex, setTabIndex] = useState(0);
  const [docPagination, setDocPagination] = useState<GridPaginationModel>({ page: 0, pageSize: 25 });
  const [docSearch, setDocSearch] = useState('');
  const [decisionKey, setDecisionKey] = useState<DecisionKey | null>(null);
  const [assignOpen, setAssignOpen] = useState(false);
  const [assignee, setAssignee] = useState('');
  // Every assignment is logged with a reason, same as every decision.
  const [assignReason, setAssignReason] = useState('');

  const {
    data: shop,
    isLoading,
    isError: shopError,
    refetch: refetchShop,
  } = useQuery<ShopItem>({
    queryKey: ['admin', 'shops', id],
    queryFn: () => apiClient<ShopItem>(API_ENDPOINTS.SHOPS.DETAIL(id)),
  });

  /**
   * The applicant. Sanitised exactly like the shopkeeper record: credentials
   * never reach the render path, and on deployments without the dedicated
   * route the role-filtered list is matched by id rather than by search.
   */
  const {
    data: owner,
    isLoading: ownerLoading,
    isError: ownerError,
    refetch: refetchOwner,
  } = useQuery<ShopkeeperDetail | null>({
    queryKey: ['admin', 'shopkeepers', shop?.owner_id],
    queryFn: async () => {
      try {
        return stripForbiddenFields(
          await apiClient<ShopkeeperDetail>(API_ENDPOINTS.SHOPKEEPERS.DETAIL(shop!.owner_id))
        );
      } catch {
        const res = await apiClient<{ items: ShopkeeperDetail[] }>(API_ENDPOINTS.CUSTOMERS.LIST, {
          params: { role: 'shopkeeper', limit: 100 },
        });
        const match = (res.items || []).find((u) => String(u.id) === String(shop!.owner_id));
        return match ? stripForbiddenFields(match) : null;
      }
    },
    enabled: tabIndex === TAB.SHOPKEEPER && Boolean(shop?.owner_id),
    retry: false,
  });

  const {
    data: documents,
    isLoading: docsLoading,
    isError: docsError,
    isFetching: docsFetching,
    refetch: refetchDocuments,
  } = useQuery({
    queryKey: ['admin', 'shops', id, 'documents', docPagination, docSearch],
    queryFn: () =>
      fetchList<ShopDocumentItem>(API_ENDPOINTS.SHOPS.DOCUMENTS(id), {
        params: {
          search: docSearch || undefined,
          limit: docPagination.pageSize,
          offset: docPagination.page * docPagination.pageSize,
        },
      }),
    enabled: tabIndex === TAB.DOCUMENTS,
    retry: false,
  });

  /**
   * One audit pull serves three tabs, so opening Attempts, Decisions, or
   * Timeline in sequence reuses the cache instead of hitting the trail again.
   */
  const auditEnabled =
    tabIndex === TAB.ATTEMPTS || tabIndex === TAB.DECISIONS || tabIndex === TAB.TIMELINE;

  const {
    data: auditLogs,
    isLoading: auditLoading,
    isError: auditError,
    refetch: refetchAudit,
  } = useQuery<{ items: AuditLogItem[]; total: number }>({
    queryKey: ['admin', 'shops', id, 'audit-logs'],
    queryFn: () =>
      apiClient<{ items: AuditLogItem[]; total: number }>(API_ENDPOINTS.AUDIT.LOGS, {
        params: { entity_type: 'shop', entity_id: id, limit: 100 },
      }),
    enabled: auditEnabled,
    retry: false,
  });

  /**
   * Previous decisions reads the dedicated audited history (newest first)
   * rather than filtering the generic trail: the row already carries Admin +
   * Time + Reason + Action, and holds stay visible as holds instead of
   * dissolving into "under review".
   */
  const historyEnabled = tabIndex === TAB.ATTEMPTS || tabIndex === TAB.DECISIONS;
  const {
    data: history,
    isLoading: historyLoading,
    isError: historyError,
    refetch: refetchHistory,
  } = useQuery<{ items: VerificationHistoryItem[]; total: number }>({
    queryKey: ['admin', 'shops', id, 'verification-history'],
    queryFn: () =>
      apiClient<{ items: VerificationHistoryItem[]; total: number }>(
        API_ENDPOINTS.SHOPS.VERIFICATION_HISTORY(id),
        { params: { limit: 100, offset: 0 } }
      ),
    enabled: historyEnabled,
    retry: false,
  });

  const decisionMutation = useMutation({
    mutationFn: ({ decision, reason }: { decision: string; reason: string }) =>
      apiClient(API_ENDPOINTS.SHOPS.VERIFICATION(id), {
        method: 'POST',
        body: JSON.stringify({ decision, reason }),
      }),
    onSuccess: () => {
      setDecisionKey(null);
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops', id] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops', id, 'audit-logs'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops', id, 'verification-history'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'verification-queue'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'verification-summary'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'dashboard', 'metrics'] });
    },
  });

  /**
   * Assignment moves a case into a reviewer's hands without deciding it. The
   * dropdown reads the same admin list the queue's reviewer filter does, so the
   * two offer the same names.
   */
  const assignMutation = useMutation({
    mutationFn: ({ reviewer, reason }: { reviewer: string | null; reason: string }) =>
      apiClient(API_ENDPOINTS.SHOPS.VERIFICATION_ASSIGN(id), {
        method: 'POST',
        body: JSON.stringify({ reviewer, reason }),
      }),
    onSuccess: () => {
      setAssignOpen(false);
      setAssignReason('');
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops', id] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops', id, 'audit-logs'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'shops', id, 'verification-history'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'verification-queue'] });
      queryClient.invalidateQueries({ queryKey: ['admin', 'verification-summary'] });
    },
  });

  const { data: reviewers } = useQuery<{ items: AdminUserItem[]; total: number }>({
    queryKey: ['admin', 'verification-reviewers'],
    queryFn: () =>
      apiClient<{ items: AdminUserItem[]; total: number }>(API_ENDPOINTS.CUSTOMERS.LIST, {
        params: { role: 'admin', limit: 100 },
      }),
    enabled: assignOpen,
    staleTime: 5 * 60 * 1000,
  });

  // Previous decisions: the audited rulings table (Admin + Time + Reason +
  // Action), newest first. Reads the dedicated history trail so holds stay
  // visible as holds; `byTimeDesc` runs on copies, never cached arrays.
  const historyEntries = useMemo(
    () => (history?.items || []).slice().sort(byTimeDesc),
    [history]
  );
  const decisions = historyEntries;

  const events = useMemo(
    () => (auditLogs?.items || []).filter(isVerificationEvent),
    [auditLogs]
  );

  const attemptsSummary = useMemo(() => {
    const source = decisions.length > 0 ? decisions : events;
    if (source.length === 0) return null;
    const times = source.map((e) => new Date(e.created_at).getTime()).filter((t) => !Number.isNaN(t));
    return {
      count: history?.total ?? decisions.length,
      first: times.length > 0 ? fmtDateTime(new Date(Math.min(...times)).toISOString()) : null,
      last: times.length > 0 ? fmtDateTime(new Date(Math.max(...times)).toISOString()) : null,
    };
  }, [decisions, events, history]);
  const documentsList = documents?.items ?? [];

  /**
   * Coordinates are authoritative; when the backend sends none, the address
   * line drives a map search instead of rendering a dead link.
   */
  const mapsUrl = shop
    ? [shop.address, shop.city, shop.state, shop.pincode]
        .filter(Boolean)
        .join(', ')
      ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(
          [shop.address, shop.city, shop.state, shop.pincode].filter(Boolean).join(', ')
        )}`
      : null
    : null;

  const activeDecision = decisionKey ? DECISIONS[decisionKey] : null;

  return (
    <Box>
      <DrillDownBreadcrumbs
        items={[
          { label: 'Dashboard', href: ROUTES.DASHBOARD },
          { label: 'Verification', href: ROUTES.VERIFICATION },
          { label: shop?.name ? shop.name : `Case #${id}` },
        ]}
      />
      <Button
        startIcon={<ArrowLeft size={16} />}
        onClick={() => router.push(ROUTES.VERIFICATION)}
        sx={{ mb: 2 }}
      >
        Back to Verification Queue
      </Button>

      {/* Identity header — the acting operator never leaves a tab to confirm
          which case the four buttons below are deciding on. */}
      <Card sx={{ mb: 2 }}>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}>
            <Box sx={{ p: 1.2, borderRadius: 2, backgroundColor: '#FFFBEB', color: '#D97706', display: 'flex' }}>
              <Store size={24} />
            </Box>
            <Box sx={{ flex: 1, minWidth: 200 }}>
              <Typography variant="h6" sx={{ fontWeight: 700 }}>
                {shop?.name || `Case #${id}`}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Case #{id}
                {shop ? ` · Shop ID #${shop.id} · Owner ID #${shop.owner_id}` : ''}
              </Typography>
            </Box>
            {shop?.status && <StatusBadge status={shop.status} size="medium" />}
            {shop?.verification_status && (
              <StatusBadge status={shop.verification_status} size="medium" />
            )}
          </Box>

          {shop && (
            <>
              <Divider sx={{ my: 2 }} />
              <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
                <PermissionGuard capability={DECISIONS.APPROVE.capability}>
                  <Button
                    variant="contained"
                    color="success"
                    startIcon={<Check size={16} />}
                    onClick={() => setDecisionKey('APPROVE')}
                  >
                    Approve
                  </Button>
                </PermissionGuard>
                <PermissionGuard capability={DECISIONS.REJECT.capability}>
                  <Button
                    variant="contained"
                    color="error"
                    startIcon={<X size={16} />}
                    onClick={() => setDecisionKey('REJECT')}
                  >
                    Reject
                  </Button>
                </PermissionGuard>
                <PermissionGuard capability={DECISIONS.CORRECTION.capability}>
                  <Button
                    variant="outlined"
                    color="warning"
                    startIcon={<FileWarning size={16} />}
                    onClick={() => setDecisionKey('CORRECTION')}
                  >
                    Request Correction
                  </Button>
                </PermissionGuard>
                <PermissionGuard capability={DECISIONS.HOLD.capability}>
                  <Button
                    variant="outlined"
                    startIcon={<Pause size={16} />}
                    onClick={() => setDecisionKey('HOLD')}
                  >
                    Put On Hold
                  </Button>
                </PermissionGuard>
                <PermissionGuard capability={DECISIONS.HOLD.capability}>
                  <Button
                    variant="outlined"
                    startIcon={<UserPlus size={16} />}
                    onClick={() => {
                      setAssignee(shop.verified_by || '');
                      setAssignReason('');
                      setAssignOpen(true);
                    }}
                  >
                    Assign Reviewer
                  </Button>
                </PermissionGuard>
              </Box>
            </>
          )}
        </CardContent>
      </Card>

      {isLoading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 6 }}>
          <CircularProgress />
        </Box>
      )}

      {shopError && (
        <Alert
          severity="error"
          sx={{ mb: 2 }}
          action={
            <Button color="inherit" size="small" onClick={() => refetchShop()}>
              Retry
            </Button>
          }
        >
          This verification case could not be loaded. The request failed — retry, and escalate if
          it keeps failing.
        </Alert>
      )}

      {!isLoading && !shopError && !shop && (
        <Alert severity="warning">
          No verification case exists for #{id}. It may have been decided and archived, or the id
          may refer to something other than a business.
        </Alert>
      )}
      {shop && (
        <>
          <Tabs
            value={tabIndex}
            onChange={(_, val) => setTabIndex(val)}
            variant="scrollable"
            scrollButtons="auto"
            sx={{ mb: 2, borderBottom: 1, borderColor: 'divider' }}
          >
            {TABS.map((label) => (
              <Tab key={label} label={label} />
            ))}
          </Tabs>

          {/* 1 — Shopkeeper */}
          {tabIndex === TAB.SHOPKEEPER && (
            <TabSection
              title="Shopkeeper"
              description="The applicant behind this submission."
            >
              <ListState
                isError={ownerError}
                unavailable={false}
                isEmpty={!ownerLoading && !owner}
                emptyMessage={`No shopkeeper record is linked to owner #${shop.owner_id}.`}
                unavailableMessage=""
                onRetry={() => refetchOwner()}
              />
              {ownerLoading && (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                  <CircularProgress size={28} />
                </Box>
              )}
              {owner && (
                <Grid container spacing={2}>
                  <Grid item xs={12} md={6}>
                    <DetailField label="Name" value={owner.name} />
                    <DetailField label="Phone" value={owner.phone} mono />
                    <DetailField label="Email" value={owner.email} />
                  </Grid>
                  <Grid item xs={12} md={6}>
                    <DetailField
                      label="Account status"
                      value={<StatusBadge status={owner.status} />}
                    />
                    <DetailField
                      label="Profile complete"
                      value={
                        owner.is_profile_complete === undefined
                          ? null
                          : owner.is_profile_complete
                            ? 'Yes'
                            : 'No'
                      }
                    />
                    <DetailField label="Last login" value={fmtDateTime(owner.last_login)} />
                    <DetailField label="Registered" value={fmtDateTime(owner.created_at)} />
                  </Grid>
                  <Grid item xs={12}>
                    <Button
                      size="small"
                      variant="outlined"
                      startIcon={<User size={14} />}
                      onClick={() => router.push(ROUTES.SHOPKEEPER_DETAIL(owner.id))}
                    >
                      Open Full Shopkeeper Profile
                    </Button>
                  </Grid>
                </Grid>
              )}
            </TabSection>
          )}

          {/* 2 — Business */}
          {tabIndex === TAB.BUSINESS && (
            <TabSection title="Business" description="The storefront under review.">
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Business name" value={shop.name} />
                  <DetailField label="Business ID" value={shop.id} mono />
                  <DetailField label="Business type" value={shop.business_type} />
                  <DetailField label="Description" value={shop.description} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField
                    label="Operational status"
                    value={<StatusBadge status={shop.status} />}
                  />
                  <DetailField
                    label="Verification stage"
                    value={<StatusBadge status={shop.verification_status} />}
                  />
                  <DetailField label="Products listed" value={shop.product_count} />
                  <DetailField label="Inventory records" value={shop.inventory_count} />
                </Grid>
                <Grid item xs={12}>
                  <Button
                    size="small"
                    variant="outlined"
                    onClick={() => router.push(ROUTES.BUSINESS_DETAIL(shop.id))}
                  >
                    Open Full Business Profile →
                  </Button>
                </Grid>
              </Grid>
            </TabSection>
          )}
          {/* 3 — Category */}
          {tabIndex === TAB.CATEGORY && (
            <TabSection
              title="Category"
              description="The taxonomy this business applied under."
            >
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Category" value={shop.category} />
                  <DetailField label="Subcategory" value={shop.subcategory} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Category ID" value={shop.category_id} mono />
                  <DetailField label="Business type" value={shop.business_type} />
                </Grid>
              </Grid>
            </TabSection>
          )}

          {/* 4 — Submitted information */}
          {tabIndex === TAB.SUBMITTED && (
            <TabSection
              title="Submitted Information"
              description="The application payload as the merchant sent it — the baseline every attempt is judged against."
            >
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Description" value={shop.description} />
                  <DetailField label="Registration number" value={shop.registration_number} mono />
                  <DetailField label="GST number" value={shop.gst_number} mono />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Phone" value={shop.phone} mono />
                  <DetailField label="Alternate phone" value={shop.alt_phone} mono />
                  <DetailField label="Email" value={shop.email} />
                  <DetailField label="Website" value={shop.website} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Submitted" value={fmtDateTime(shop.created_at)} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="Last updated" value={fmtDateTime(shop.updated_at)} />
                </Grid>
              </Grid>
            </TabSection>
          )}

          {/* 5 — Documents */}
          {tabIndex === TAB.DOCUMENTS && (
            <TabSection
              title="Documents"
              description="Evidence the merchant attached to this application."
            >
              <ListState
                isError={docsError}
                unavailable={documents?.unavailable ?? false}
                isEmpty={documentsList.length === 0}
                emptyMessage="No documents are attached to this application."
                unavailableMessage="Shop-scoped documents are not published on this deployment."
                onRetry={() => refetchDocuments()}
                isRetrying={docsFetching}
              />
              {documentsList.map((doc) => (
                <Card key={String(doc.id)} variant="outlined" sx={{ mb: 1.5 }}>
                  <CardContent
                    sx={{ p: 2, display: 'flex', alignItems: 'center', gap: 2, flexWrap: 'wrap' }}
                  >
                    <Box
                      sx={{
                        p: 1,
                        borderRadius: 1.5,
                        backgroundColor: '#EFF6FF',
                        color: 'primary.main',
                        display: 'flex',
                      }}
                    >
                      <FileText size={18} />
                    </Box>
                    <Box sx={{ flex: 1, minWidth: 180 }}>
                      <Typography variant="body2" sx={{ fontWeight: 600 }}>
                        {doc.title || doc.file_name || doc.doc_type || `Document #${doc.id}`}
                      </Typography>
                      <Typography variant="caption" color="text.secondary">
                        {[doc.doc_type, doc.file_name].filter(Boolean).join(' · ') || 'No file name'}
                      </Typography>
                      {doc.uploaded_at && (
                        <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                          Uploaded {fmtDateTime(doc.uploaded_at)}
                          {doc.expires_at ? ` · Expires ${fmtDate(doc.expires_at)}` : ''}
                        </Typography>
                      )}
                    </Box>
                    <StatusBadge status={doc.status || 'PENDING'} />
                    <ExternalLink href={doc.file_url}>Open</ExternalLink>
                  </CardContent>
                </Card>
              ))}
            </TabSection>
          )}



          {/* 6 — Location */}
          {tabIndex === TAB.LOCATION && (
            <TabSection
              title="Location"
              description="Where the physical verification visit goes."
            >
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Address" value={shop.address} />
                  <DetailField label="Locality" value={shop.locality} />
                  <DetailField label="City" value={shop.city} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField label="State" value={shop.state} />
                  <DetailField label="Pincode" value={shop.pincode} mono />
                  <DetailField
                    label="Coordinates"
                    value={
                      shop.latitude != null && shop.longitude != null
                        ? `${shop.latitude}, ${shop.longitude}`
                        : null
                    }
                    mono
                  />
                </Grid>
                <Grid item xs={12}>
                  {mapsUrl ? (
                    <Button
                      size="small"
                      variant="outlined"
                      startIcon={<MapPin size={14} />}
                      href={mapsUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      Open in Maps
                    </Button>
                  ) : (
                    <NotReported what="A mappable location" />
                  )}
                </Grid>
              </Grid>
            </TabSection>
          )}

          {/* 7 — Verification attempts */}
          {tabIndex === TAB.ATTEMPTS && (
            <TabSection
              title="Verification Attempts"
              description="Each ruling recorded on this case — the audited attempt count."
            >
              <ListState
                isError={historyError}
                unavailable={false}
                isEmpty={!historyLoading && decisions.length === 0}
                emptyMessage="No verification activity is recorded for this case yet."
                unavailableMessage=""
                onRetry={() => refetchHistory()}
              />
              {historyLoading && (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                  <CircularProgress size={28} />
                </Box>
              )}
              {!historyLoading && attemptsSummary && (
                <>
                  <Grid container spacing={2} sx={{ mb: 2 }}>
                    <Grid item xs={12} sm={4}>
                      <DetailField label="Attempts recorded" value={attemptsSummary.count} />
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <DetailField label="First attempt" value={attemptsSummary.first} />
                    </Grid>
                    <Grid item xs={12} sm={4}>
                      <DetailField label="Last attempt" value={attemptsSummary.last} />
                    </Grid>
                  </Grid>
                  {decisions.map((e) => (
                    <Box
                      key={e.id}
                      sx={{
                        display: 'flex',
                        gap: 1.5,
                        alignItems: 'flex-start',
                        py: 1.25,
                        borderBottom: '1px solid #F1F5F9',
                      }}
                    >
                      <Box sx={{ pt: 0.25, color: 'primary.main', display: 'flex' }}>
                        <History size={16} />
                      </Box>
                      <Box sx={{ flex: 1 }}>
                        <Typography variant="body2" sx={{ fontWeight: 600 }}>
                          {e.action}
                        </Typography>
                        <Typography variant="caption" color="text.secondary">
                          {e.admin_user || 'System'}
                          {' · '}
                          {fmtDateTime(e.created_at)}
                          {reasonOf(e) ? ` · ${reasonOf(e)}` : ''}
                        </Typography>
                      </Box>
                    </Box>
                  ))}
                </>
              )}
            </TabSection>
          )}


          {/* 8 — Previous decisions */}
          {tabIndex === TAB.DECISIONS && (
            <TabSection
              title="Previous Decisions"
              description="Every ruling recorded on this case — the same endpoint the header actions post to."
            >
              <ListState
                isError={historyError}
                unavailable={false}
                isEmpty={!historyLoading && decisions.length === 0}
                emptyMessage="No decisions are recorded on this case yet. It is awaiting its first ruling."
                unavailableMessage=""
                onRetry={() => refetchHistory()}
              />
              {historyLoading && (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                  <CircularProgress size={28} />
                </Box>
              )}
              {!historyLoading && decisions.length > 0 && (
                <Table size="small">
                  <TableHead>
                    <TableRow sx={{ backgroundColor: '#F8FAFC' }}>
                      <TableCell sx={{ fontWeight: 700 }}>Admin</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>Time</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>Reason</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>Action</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {decisions.map((d) => (
                      <TableRow key={d.id}>
                        <TableCell sx={{ fontWeight: 600 }}>
                          {d.admin_user || 'System'}
                        </TableCell>
                        <TableCell>{fmtDateTime(d.created_at) || '—'}</TableCell>
                        <TableCell>{reasonOf(d) || '—'}</TableCell>
                        <TableCell>
                          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Gavel size={14} color="#64748B" />
                            <Typography variant="body2">{d.action}</Typography>
                          </Box>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </TabSection>
          )}

          {/* 9 — Reviewer */}
          {tabIndex === TAB.REVIEWER && (
            <TabSection
              title="Reviewer"
              description="Who holds this case right now — assigned by the Reviewer dialog, recorded in the audit trail."
            >
              <Grid container spacing={2}>
                <Grid item xs={12} md={6}>
                  <DetailField label="Reviewed by" value={shop.verified_by} />
                  <DetailField label="Reviewed at" value={fmtDateTime(shop.verified_at)} />
                </Grid>
                <Grid item xs={12} md={6}>
                  <DetailField
                    label="Current stage"
                    value={<StatusBadge status={shop.verification_status} />}
                  />
                  <DetailField
                    label="Rejection reason"
                    value={shop.rejection_reason}
                  />
                </Grid>
                <Grid item xs={12}>
                  {decisions.length > 0 && (
                    <DetailField
                      label="Last decision"
                      value={`${decisions[0].action} · ${decisions[0].admin_user || 'System'} · ${fmtDateTime(decisions[0].created_at) || '—'}${reasonOf(decisions[0]) ? ` · ${reasonOf(decisions[0])}` : ''}`}
                    />
                  )}
                  {!shop.verified_by && decisions.length === 0 && (
                    <Alert severity="info">
                      No operator has recorded a decision yet — this case is unassigned, not
                      missing its reviewer.
                    </Alert>
                  )}
                  {!shop.verified_by && decisions.length > 0 && (
                    <Alert severity="warning">
                      This case has rulings but no current holder — assign a reviewer to take
                      ownership.
                    </Alert>
                  )}
                </Grid>
              </Grid>
            </TabSection>
          )}


          {/* 10 — Timeline */}
          {tabIndex === TAB.TIMELINE && (
            <TabSection
              title="Timeline"
              description="The full audit trajectory for this case, newest last."
            >
              <ListState
                isError={auditError}
                unavailable={false}
                isEmpty={!auditLoading && (auditLogs?.items?.length ?? 0) === 0}
                emptyMessage="No audit entries exist for this case."
                unavailableMessage=""
                onRetry={() => refetchAudit()}
              />
              {auditLoading && (
                <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
                  <CircularProgress size={28} />
                </Box>
              )}
              {!auditLoading && (auditLogs?.items?.length ?? 0) > 0 && (
                <Box sx={{ mt: 1 }}>
                  {(auditLogs?.items || []).map((entry, idx, arr) => (
                    <Box key={entry.id} sx={{ display: 'flex', gap: 2 }}>
                      <Box
                        sx={{
                          display: 'flex',
                          flexDirection: 'column',
                          alignItems: 'center',
                        }}
                      >
                        <Box
                          sx={{
                            width: 12,
                            height: 12,
                            borderRadius: '50%',
                            backgroundColor: isVerificationEvent(entry)
                              ? '#0F52BA'
                              : '#CBD5E1',
                            mt: 0.75,
                            flexShrink: 0,
                          }}
                        />
                        {idx < arr.length - 1 && (
                          <Box sx={{ width: 2, flex: 1, minHeight: 24, backgroundColor: '#E2E8F0' }} />
                        )}
                      </Box>
                      <Box sx={{ pb: 2.5, flex: 1 }}>
                        <Typography variant="body2" sx={{ fontWeight: 600 }}>
                          {entry.action}
                        </Typography>
                        <Typography variant="caption" color="text.secondary">
                          {entry.admin_user || 'System'}
                          {' · '}
                          {fmtDateTime(entry.created_at)}
                          {reasonOf(entry) ? ` · ${reasonOf(entry)}` : ''}
                        </Typography>
                      </Box>
                    </Box>
                  ))}
                </Box>
              )}
            </TabSection>
          )}
        </>
      )}

      {activeDecision && shop && (
        <ConfirmationDialog
          open={Boolean(activeDecision)}
          title={`${activeDecision.label} — ${shop.name}`}
          affectedItem={`Case #${id} · ${shop.name}`}
          consequence={activeDecision.consequence}
          isDangerous={activeDecision.isDangerous}
          requireReason
          isLoading={decisionMutation.isPending}
          onConfirm={async (reason) => {
            await decisionMutation.mutateAsync({ decision: activeDecision.value, reason });
          }}
          onClose={() => setDecisionKey(null)}
        />
      )}

      {/* Assignment is deliberately not a decision: it changes who holds the
          case, not its stage (except Pending, which becomes Under Review), so
          it gets its own dialog rather than riding on ConfirmationDialog. */}
      <Dialog open={assignOpen} onClose={() => setAssignOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>Assign Reviewer</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            Pick the operator who will hold this case. Assigning moves it to Under Review;
            leaving it unassigned releases it back to the shared queue.
          </Typography>
          <FormControl fullWidth size="small">
            <InputLabel id="assign-reviewer-label">Reviewer</InputLabel>
            <Select
              labelId="assign-reviewer-label"
              label="Reviewer"
              value={assignee}
              onChange={(e) => setAssignee(e.target.value)}
            >
              <MenuItem value="">Unassigned</MenuItem>
              {(reviewers?.items || [])
                .filter((r) => r.name)
                .map((r) => (
                  <MenuItem key={r.id} value={r.name as string}>
                    {r.name}
                  </MenuItem>
                ))}
            </Select>
          </FormControl>
          <TextField
            fullWidth
            size="small"
            multiline
            rows={2}
            label="Reason (Recorded in Audit Log)"
            placeholder="Why is this case moving reviewers?"
            value={assignReason}
            onChange={(e) => setAssignReason(e.target.value)}
            sx={{ mt: 2 }}
          />
          {assignMutation.isError && (
            <Alert severity="error" sx={{ mt: 2 }}>
              The assignment could not be saved. The request failed — retry, and escalate if it
              keeps failing.
            </Alert>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAssignOpen(false)} disabled={assignMutation.isPending}>
            Cancel
          </Button>
          <Button
            variant="contained"
            disabled={assignMutation.isPending || !assignReason.trim()}
            onClick={() => assignMutation.mutate({ reviewer: assignee || null, reason: assignReason.trim() })}
          >
            {assignMutation.isPending ? 'Saving…' : 'Assign'}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
