/**
 * Section: Final Route Structure — centralized route registry.
 *
 * Single source of truth for every navigable path in the Admin Control Center.
 * Pages, the sidebar, drill-downs and the command palette must reference these
 * helpers instead of hardcoding string literals, so the route tree can evolve
 * without scattered edits.
 */

export const ROUTES = {
  LOGIN: '/login',

  DASHBOARD: '/dashboard',

  // People
  CUSTOMERS: '/customers',
  CUSTOMER_DETAIL: (id: number | string) => `/customers/${id}`,
  SHOPKEEPERS: '/shopkeepers',
  SHOPKEEPER_DETAIL: (id: number | string) => `/shopkeepers/${id}`,

  // Businesses
  BUSINESSES: '/businesses',
  BUSINESS_DETAIL: (id: number | string) => `/businesses/${id}`,
  VERIFICATION: '/verification',
  VERIFICATION_DETAIL: (id: number | string) => `/verification/${id}`,

  // Catalog
  PRODUCTS: '/products',
  PRODUCT_DETAIL: (id: number | string) => `/products/${id}`,
  PRODUCTS_APPROVALS: '/products/approvals',
  PRODUCTS_QUALITY: '/products/quality',
  PRODUCTS_MERGE: '/products/merge',
  CATEGORIES: '/categories',
  CATEGORY_DETAIL: (id: number | string) => `/categories/${id}`,
  BRANDS: '/brands',
  BRAND_DETAIL: (id: number | string) => `/brands/${id}`,

  // Inventory & Pricing
  INVENTORY: '/inventory',
  INVENTORY_DETAIL: (id: number | string) => `/inventory/${id}`,
  PRICING: '/pricing',
  PRICING_DETAIL: (id: number | string) => `/pricing/${id}`,

  // Offers & Subscriptions
  OFFERS: '/offers',
  OFFER_DETAIL: (id: number | string) => `/offers/${id}`,
  SUBSCRIPTIONS: '/subscriptions',
  SUBSCRIPTIONS_PAYMENTS: '/subscriptions/payments',

  // Discovery / Search
  SEARCH: '/search',
  SEARCH_QUALITY: '/search/quality',
  SEARCH_ZERO_RESULTS: '/search/zero-results',
  SEARCH_TRENDS: '/search/trends',

  // Geography & Data Ingestion
  LOCATIONS: '/locations',
  LOCATIONS_MAP: '/locations/map',
  IMPORTS: '/imports',
  IMPORT_DETAIL: (id: number | string) => `/imports/${id}`,
  POS: '/pos',
  POS_DETAIL: (id: number | string) => `/pos/${id}`,

  // Engagement & Governance
  NOTIFICATIONS: '/notifications',
  NOTIFICATION_CAMPAIGNS: '/notifications/campaigns',
  NOTIFICATION_DETAIL: (id: number | string) => `/notifications/${id}`,

  // Content & Announcements
  CONTENT: '/content',
  CONTENT_BANNERS: '/content/banners',
  CONTENT_ANNOUNCEMENTS: '/content/announcements',
  CONTENT_FAQS: '/content/faqs',
  CONTENT_HELP: '/content/help',
  CONTENT_PROMOTIONS: '/content/promotions',
  CONTENT_SYSTEM_MESSAGES: '/content/system-messages',

  SUPPORT: '/support',
  SUPPORT_DETAIL: (id: number | string) => `/support/${id}`,
  AUDIT: '/audit',
  AUDIT_NOTES: '/audit/notes',

  // Reviews & Moderation
  REVIEWS: '/reviews',
  REVIEW_DETAIL: (id: number | string) => `/reviews/${id}`,

  // Analytics
  ANALYTICS: '/analytics',
  ANALYTICS_CUSTOMERS: '/analytics/customers',
  ANALYTICS_SHOPKEEPERS: '/analytics/shopkeepers',
  ANALYTICS_PRODUCTS: '/analytics/products',
  ANALYTICS_SHOPS: '/analytics/shops',
  ANALYTICS_SEARCH: '/analytics/search',
  ANALYTICS_GEOGRAPHY: '/analytics/geography',

  // System
  SYSTEM_HEALTH: '/system/health',
  SYSTEM_JOBS: '/system/jobs',
  SYSTEM_FLAGS: '/system/flags',
  SYSTEM_SETTINGS: '/system/settings',
  SYSTEM_LIVE_OPERATIONS: '/system/live-operations',

  // Admin Users (RBAC management)
  ADMIN_USERS: '/admin-users',
  ADMIN_USER_DETAIL: (id: number | string) => `/admin-users/${id}`,
  SETTINGS: '/settings',
} as const;
