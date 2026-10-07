/**
 * Admin Platform Data Models matching Backend Schemas
 */

export type AdminRoleLevel = 'SUPER' | 'SUB' | 'none';

export interface AdminRoleInfo {
  user_id: number;
  name: string | null;
  role_name: string | null;
  level: AdminRoleLevel;
  permissions: string[];
  /** True only for the single platform owner. Backend-authoritative. */
  is_owner?: boolean;
}

export interface DashboardMetrics {
  total_customers: number;
  total_shops: number;
  active_shops: number;
  pending_verification: number;
  total_products: number;
  total_inventory_records: number;
  total_searches: number;
  search_success_rate: number;
  popular_categories: Array<{ id: number; name: string; count: number }>;
  active_subscriptions: number;
  total_subscription_revenue: number;
  pending_approvals: number;
  open_complaints: number;
  stale_inventory_count: number;
  products_missing_prices: number;
  sync_failures: number;
}

export type UserStatus = 'ACTIVE' | 'INACTIVE' | 'SUSPENDED' | 'BANNED' | 'PENDING';

export interface AdminUserItem {
  id: number;
  name: string | null;
  phone: string | null;
  email: string | null;
  role: string;
  status: UserStatus;
  created_at: string;
  last_login?: string | null;
}

export type ShopStatus = 'ACTIVE' | 'INACTIVE' | 'SUSPENDED' | 'PENDING' | 'REJECTED';
export type VerificationStatus =
  | 'UNVERIFIED'
  | 'PENDING'
  | 'UNDER_REVIEW'
  | 'VERIFIED'
  | 'NEEDS_CORRECTION'
  | 'REJECTED'
  | 'SUSPENDED';

/**
 * Business type classification for a merchant storefront.
 *
 * Optional by design: the admin backend does not publish a `business_type`
 * enum contract, so the field is surfaced only when the backend supplies it.
 * The UI renders "Not reported" rather than inventing a classification.
 */
export type BusinessType =
  | 'RETAIL'
  | 'WHOLESALE'
  | 'DISTRIBUTOR'
  | 'MANUFACTURER'
  | 'SERVICE'
  | 'MIXED'
  | string;

export interface ShopItem {
  id: number;
  name: string;
  owner_id: number;
  owner_name?: string;
  category: string;
  /** Taxonomy ids/names as reported by the backend, when it reports them. */
  category_id?: number | null;
  subcategory?: string | null;
  business_type?: BusinessType | null;
  city: string;
  state: string;
  status: ShopStatus;
  verification_status: VerificationStatus;
  product_count: number;
  inventory_count?: number;
  inventory_freshness?: string;
  /** Most recent inventory sync across this shop, when reported. */
  last_inventory_update?: string | null;
  created_at: string;
  updated_at: string;

  // Location
  address?: string | null;
  locality?: string | null;
  pincode?: string | null;
  latitude?: number | null;
  longitude?: number | null;

  // Contact
  phone?: string | null;
  alt_phone?: string | null;
  email?: string | null;
  website?: string | null;

  // Presentation
  logo_url?: string | null;
  description?: string | null;
  registration_number?: string | null;
  gst_number?: string | null;

  // Verification
  verified_at?: string | null;
  verified_by?: string | null;
  rejection_reason?: string | null;

  // Operating hours. Sent either as a weekly map keyed by weekday or as a
  // pre-rendered list; both shapes are tolerated by the hours tab.
  operating_hours?: Record<string, string | null> | string | null;
}

/** A compliance document attached to a shop. */
export interface ShopDocumentItem {
  id: number | string;
  doc_type?: string | null;
  title?: string | null;
  file_name?: string | null;
  file_url?: string | null;
  status?: string | null;
  uploaded_at?: string | null;
  expires_at?: string | null;
  verified_at?: string | null;
}

/** A shop-scoped price record. */
export interface ShopPricingItem {
  id: number | string;
  product_name?: string | null;
  sku?: string | null;
  barcode?: string | null;
  price?: number | null;
  mrp?: number | null;
  currency?: string | null;
  updated_at?: string | null;
}

export type ProductStatus = 'DRAFT' | 'PENDING' | 'APPROVED' | 'REJECTED' | 'ARCHIVED' | 'ACTIVE';

export interface ProductItem {
  id: number;
  name: string;
  brand_id?: number | null;
  brand_name?: string | null;
  category_id?: number | null;
  category_name?: string | null;
  subcategory_id?: number | null;
  barcode?: string | null;
  status: ProductStatus;
  shop_count?: number;
  created_at: string;
  updated_at: string;
  /** Backend-disclosed product extras. Absent values render as "Not reported"
      rather than invented — the variants tab reads its own endpoint instead. */
  image_url?: string | null;
  images?: string[] | null;
  description?: string | null;
  mrp?: number | null;
  unit?: string | null;
}

/** One purchasable variant of a master product. */
export interface ProductVariantItem {
  id: number | string;
  product_id?: number | null;
  name?: string | null;
  variant_name?: string | null;
  sku?: string | null;
  barcode?: string | null;
  mrp?: number | null;
  price?: number | null;
  unit?: string | null;
  status?: string | null;
  image_url?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface CategoryItem {
  id: number;
  name: string;
  slug: string;
  description?: string | null;
  icon_url?: string | null;
  parent_id?: number | null;
  sort_order: number;
  is_active: boolean;
  is_subcategory: boolean;
  created_at?: string;
}

export interface BrandItem {
  id: number;
  name: string;
  slug: string;
  description?: string | null;
  logo_url?: string | null;
  is_active: boolean;
  product_count?: number;
  created_at?: string;
}

export interface StaleInventoryItem {
  shop_product_id: number;
  product_name: string;
  shop_name: string;
  shop_id: number;
  quantity: number;
  stock_status: string;
  freshness_status?: string | null;
  last_updated?: string | null;
  last_updated_source?: string | null;
  stale_hours?: number | null;
}

export interface OfferItem {
  id: number;
  title: string;
  discount_type: string;
  discount_value: number;
  status: 'ACTIVE' | 'PAUSED' | 'CANCELLED' | 'EXPIRED';
  shop_id: number;
  shop_name?: string;
  valid_from: string;
  valid_until: string;
}

/**
 * Support Center ticket lifecycle.
 *
 * OPEN → IN_PROGRESS → (ESCALATED) → RESOLVED → CLOSED.
 * ESCALATED marks a ticket pushed to a higher support tier; it can return to
 * IN_PROGRESS or jump straight to RESOLVED. CLOSED is terminal.
 */
export type ComplaintStatus = 'OPEN' | 'IN_PROGRESS' | 'ESCALATED' | 'RESOLVED' | 'CLOSED';

/**
 * Support Center ticket categories. `OTHER` is the server-side fallback for
 * any classifier value the console does not know about.
 */
export type ComplaintCategory =
  | 'CUSTOMER'
  | 'SHOPKEEPER'
  | 'BUSINESS'
  | 'PRODUCT'
  | 'SEARCH'
  | 'TECHNICAL'
  | 'PAYMENT'
  | 'OTHER';

/** One entry in a ticket's activity timeline. */
export interface ComplaintTimelineEntry {
  id?: number | string;
  /** e.g. CREATED, STATUS_CHANGED, ASSIGNED, NOTE_ADDED, RESPONSE_SENT. */
  event_type: string;
  /** Human-readable summary of what happened. */
  message: string;
  actor_name?: string | null;
  /** True when the entry is an operator-visible-only internal note. */
  is_internal?: boolean;
  created_at: string;
}

/** An attachment uploaded alongside a ticket or added during handling. */
export interface ComplaintAttachment {
  id?: number | string;
  file_name?: string | null;
  /** Backend-hosted asset URL (S3/CDN). Never a user-supplied script URL. */
  file_url?: string | null;
  file_size_bytes?: number | null;
  content_type?: string | null;
  uploaded_at?: string | null;
}

export interface ComplaintItem {
  id: number;
  ticket_number?: string;
  reporter_type?: string;
  reporter_name?: string;
  complaint_type: string;
  /** Classifier category, e.g. "TECHNICAL". Derived from complaint_type when absent. */
  category?: string | null;
  priority: 'LOW' | 'MEDIUM' | 'HIGH' | 'URGENT';
  status: ComplaintStatus | string;
  description: string;
  created_at: string;
  /** Admin the ticket is currently assigned to. */
  assigned_admin?: string | null;
  assigned_admin_id?: number | null;
  /** Related entity references surfaced as drill-down links. */
  related_customer_id?: number | null;
  related_customer_name?: string | null;
  related_shop_id?: number | null;
  related_shop_name?: string | null;
  related_product_id?: number | null;
  related_product_name?: string | null;
  /** Detail payload extras — populated by the detail endpoint when supported. */
  attachments?: ComplaintAttachment[] | null;
  timeline?: ComplaintTimelineEntry[] | null;
  /** Backend-advertised action availability; honoured when explicitly false. */
  can_assign?: boolean;
  can_respond?: boolean;
  resolution_notes?: string | null;
  updated_at?: string | null;
}

export interface AuditLogItem {
  id: number;
  action: string;
  entity_type: string;
  entity_id?: number | null;
  user_id?: number | null;
  admin_user?: string | null;
  ip_address?: string | null;
  created_at: string;
  details?: Record<string, unknown> | null;
}

export interface SystemSettingItem {
  key: string;
  value: string;
  value_type: 'string' | 'int' | 'float' | 'boolean' | 'json';
  description?: string | null;
  is_secret: boolean;
  updated_at?: string;
}

export interface FeatureFlagItem {
  name: string;
  is_enabled: boolean;
  rollout_percentage: number;
  scope: 'GLOBAL' | 'SHOP' | 'USER' | 'REGION';
  description?: string | null;
  updated_at?: string;
}

/**
 * Drill-down data models (SEE → UNDERSTAND → CONTROL → INVESTIGATE → CORRECT → MEASURE)
 */

export interface InventoryRecordDetail extends StaleInventoryItem {
  shop_id: number;
  shop_name: string;
  owner_id: number;
  owner_name?: string | null;
  owner_phone?: string | null;
  price?: number | null;
  mrp?: number | null;
  availability?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  sync_source?: string | null;
  sync_status?: string | null;
  sync_error?: string | null;
}

export interface InventoryHistoryEntry {
  id: number;
  shop_product_id: number;
  change_type: string;
  old_value?: string | null;
  new_value?: string | null;
  source?: string | null;
  changed_by?: string | null;
  created_at: string;
}

export interface ShopInventoryItem {
  shop_product_id: number;
  product_name: string;
  product_id?: number;
  shop_name?: string | null;
  quantity: number;
  price?: number | null;
  stock_status: string;
  freshness_status?: string | null;
  last_updated?: string | null;
}

export interface ShopkeeperDetail {
  id: number;
  name: string | null;
  phone: string | null;
  email: string | null;
  status: string;
  created_at: string;
  last_login?: string | null;
  /** Account completeness — drives the "Incomplete" quick-filter. */
  is_profile_complete?: boolean;
  shop_ids?: number[];
  shop_names?: string[];
  /** Optional backend-disclosed fields; absent values render as "Not reported". */
  business_type?: BusinessType | null;
  verification_status?: VerificationStatus | null;
  city?: string | null;
  state?: string | null;
}

/**
 * Customer detail models.
 *
 * Every field here is optional because the backend progressively discloses more
 * as policy allows; the UI must degrade honestly rather than assume a shape.
 * No credential field exists by design — see core/privacy/masking.ts.
 */
export interface CustomerDetail extends AdminUserItem {
  auth_status?: 'VERIFIED' | 'PENDING' | 'UNVERIFIED' | string;
  last_active?: string | null;
  city?: string | null;
  state?: string | null;
  search_count?: number;
  viewed_product_count?: number;
  viewed_shop_count?: number;
  saved_product_count?: number;
  saved_shop_count?: number;
  is_restricted?: boolean;
}

export interface CustomerActivityItem {
  id: number;
  activity_type: string;
  description?: string | null;
  entity_type?: string | null;
  entity_id?: number | null;
  created_at: string;
}

/**
 * The six activity surfaces named in the spec. Each is a distinct backend
 * contract, so each gets its own row shape rather than one overloaded type.
 */
export interface CustomerSearchItem {
  id: number;
  query: string;
  result_count?: number | null;
  location?: string | null;
  searched_at?: string | null;
}

export interface CustomerViewedItem {
  id: number;
  entity_type: 'PRODUCT' | 'SHOP' | string;
  entity_name: string;
  category?: string | null;
  city?: string | null;
  viewed_at?: string | null;
}

export interface CustomerSavedEntityItem {
  id: number;
  name: string;
  category?: string | null;
  brand_name?: string | null;
  city?: string | null;
  shop_name?: string | null;
  price?: number | null;
  saved_at?: string | null;
}

export interface CustomerNotificationItem {
  id: number;
  title: string;
  notification_type?: string | null;
  status?: string | null;
  is_read?: boolean;
  sent_at?: string | null;
  created_at?: string | null;
}

export interface CustomerReportItem {
  id: number;
  report_type: string;
  reason?: string | null;
  status: string;
  resolution?: string | null;
  created_at: string;
}

export interface CustomerSavedItem {
  id: number;
  item_type: 'PRODUCT' | 'SHOP' | string;
  name: string;
  shop_name?: string | null;
  city?: string | null;
  saved_at?: string | null;
}

export interface CustomerAddressItem {
  id: number;
  label?: string | null;
  area?: string | null;
  city?: string | null;
  state?: string | null;
  is_default?: boolean;
}

export interface CustomerTicketItem {
  id: number;
  ticket_number?: string;
  complaint_type: string;
  priority: 'LOW' | 'MEDIUM' | 'HIGH' | 'URGENT';
  status: 'OPEN' | 'IN_PROGRESS' | 'RESOLVED' | 'CLOSED';
  description: string;
  created_at: string;
}

/** Shop-scoped import job, used by the shopkeeper Imports tab. */
export interface ImportJob {
  id: number;
  shop_id?: number | null;
  shop_name?: string | null;
  source?: string;
  status?: string;
  rows_total?: number;
  rows_processed?: number;
  created_at?: string;
}

/** Shop-scoped POS connection, used by the shopkeeper POS tab. */
export interface PosIntegration {
  id: number;
  shop_id?: number | null;
  shop_name?: string | null;
  provider?: string;
  status?: string;
  last_sync?: string | null;
}

export interface ShopkeeperBusinessSummary {
  shops: ShopItem[];
  total_shops: number;
  total_products: number;
  total_inventory: number;
  last_inventory_update: string | null;
}

/** Shop-scoped ingestion, POS, notification and support row shapes. */
export interface ShopkeeperImportItem {
  id: number;
  source?: string | null;
  status?: string | null;
  rows_total?: number | null;
  rows_processed?: number | null;
  created_at?: string | null;
}

export interface ShopkeeperPosItem {
  id: number;
  shop_name?: string | null;
  provider?: string | null;
  status?: string | null;
  last_sync?: string | null;
}

export interface ShopkeeperNotificationItem {
  id: number;
  title: string;
  notification_type?: string | null;
  status?: string | null;
  is_read?: boolean;
  sent_at?: string | null;
}

export interface ShopkeeperTicketItem {
  id: number;
  ticket_number?: string | null;
  complaint_type: string;
  priority: 'LOW' | 'MEDIUM' | 'HIGH' | 'URGENT' | string;
  status: string;
  description?: string | null;
  created_at: string;
}
/**
 * Notification campaign models (Section 48–50).
 *
 * A campaign is the persisted record of a broadcast/targeted dispatch. The
 * backend is authoritative for delivery counts; the frontend only renders them.
 */
export type NotificationAudience = 'all' | 'customer' | 'shopkeeper';
export type NotificationCampaignStatus = 'DRAFT' | 'SCHEDULED' | 'SENDING' | 'SENT' | 'FAILED' | 'CANCELLED';

export interface NotificationCampaignItem {
  id: number;
  title: string;
  body?: string;
  notification_type: string;
  audience?: NotificationAudience | string;
  status: NotificationCampaignStatus | string;
  deep_link?: string | null;
  entity_id?: string | null;
  recipients_total?: number;
  recipients_sent?: number;
  recipients_failed?: number;
  sent_by?: string | null;
  created_at: string;
  sent_at?: string | null;
}

export interface NotificationSendPayload {
  title: string;
  body: string;
  notification_type: string;
  audience?: NotificationAudience;
  /** Pre-validated, root-relative admin path only. */
  deep_link?: string | null;
  entity_id?: string | null;
  /** Operator reason, recorded in the audit log for high-impact broadcasts. */
  reason?: string;
}

/**
 * Content & Announcements models (banners, announcements, FAQs, help content,
 * promotional cards, system messages). Only usable when the backend exposes the
 * `/api/v1/admin/content/*` API.
 */
export type ContentStatus = 'DRAFT' | 'SCHEDULED' | 'PUBLISHED' | 'ARCHIVED';

export interface ContentAudienceTarget {
  audience: NotificationAudience | string;
}

export interface HomeBannerItem {
  id: number;
  title: string;
  subtitle?: string | null;
  image_url?: string | null;
  deep_link?: string | null;
  placement?: string | null;
  status: ContentStatus | string;
  sort_order?: number;
  starts_at?: string | null;
  ends_at?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface AnnouncementItem {
  id: number;
  title: string;
  body: string;
  audience?: NotificationAudience | string;
  status: ContentStatus | string;
  is_pinned?: boolean;
  published_at?: string | null;
  expires_at?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface FaqItem {
  id: number;
  question: string;
  answer: string;
  category?: string | null;
  audience?: NotificationAudience | string;
  status: ContentStatus | string;
  sort_order?: number;
  created_at?: string;
  updated_at?: string;
}

export interface HelpContentItem {
  id: number;
  title: string;
  slug?: string | null;
  body: string;
  section?: string | null;
  status: ContentStatus | string;
  sort_order?: number;
  created_at?: string;
  updated_at?: string;
}

export interface PromotionalCardItem {
  id: number;
  title: string;
  description?: string | null;
  image_url?: string | null;
  cta_label?: string | null;
  deep_link?: string | null;
  status: ContentStatus | string;
  starts_at?: string | null;
  ends_at?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface SystemMessageItem {
  id: number;
  title: string;
  body: string;
  severity?: 'INFO' | 'WARNING' | 'CRITICAL' | string;
  status: ContentStatus | string;
  is_active?: boolean;
  starts_at?: string | null;
  ends_at?: string | null;
  created_at?: string;
  updated_at?: string;
}