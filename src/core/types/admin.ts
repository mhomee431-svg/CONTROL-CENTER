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
export type VerificationStatus = 'UNVERIFIED' | 'PENDING' | 'VERIFIED' | 'REJECTED' | 'SUSPENDED';

export interface ShopItem {
  id: number;
  name: string;
  owner_id: number;
  owner_name?: string;
  category: string;
  city: string;
  state: string;
  status: ShopStatus;
  verification_status: VerificationStatus;
  product_count: number;
  inventory_count?: number;
  inventory_freshness?: string;
  created_at: string;
  updated_at: string;
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

export interface ComplaintItem {
  id: number;
  ticket_number?: string;
  reporter_type?: string;
  reporter_name?: string;
  complaint_type: string;
  priority: 'LOW' | 'MEDIUM' | 'HIGH' | 'URGENT';
  status: 'OPEN' | 'IN_PROGRESS' | 'RESOLVED' | 'CLOSED';
  description: string;
  created_at: string;
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
  shop_ids?: number[];
  shop_names?: string[];
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