/**
 * Centralized API Endpoints Map
 * All requests route through FastAPI's /api/v1 prefix
 */

export const API_ENDPOINTS = {
  // Auth & Session
  AUTH: {
    LOGIN: '/api/v1/admin/auth/login',
    FIREBASE_LOGIN: '/api/v1/auth/firebase-login',
    LOGOUT: '/api/v1/auth/logout',
    REFRESH: '/api/v1/auth/refresh',
    SESSIONS: '/api/v1/auth/sessions',
    ME: '/api/v1/admin/me',
  },

  // Dashboard & Analytics
  DASHBOARD: {
    METRICS: '/api/v1/admin/dashboard/metrics',
    ANALYTICS_SUMMARY: '/api/v1/admin/analytics/summary',
  },

  // Users & Customers
  CUSTOMERS: {
    LIST: '/api/v1/admin/customers',
    DETAIL: (userId: number | string) => `/api/v1/admin/customers/${userId}`,
    // Each customer drill-down tab is its own route. They stay separate so a
    // tab that is not deployed yet is a named failure rather than an empty
    // tab, and so one slow surface does not hold up the rest.
    ACTIVITY: (userId: number | string) => `/api/v1/admin/customers/${userId}/activity`,
    SEARCHES: (userId: number | string) => `/api/v1/admin/customers/${userId}/searches`,
    VIEWED_PRODUCTS: (userId: number | string) =>
      `/api/v1/admin/customers/${userId}/viewed-products`,
    VIEWED_SHOPS: (userId: number | string) => `/api/v1/admin/customers/${userId}/viewed-shops`,
    SAVED_PRODUCTS: (userId: number | string) =>
      `/api/v1/admin/customers/${userId}/saved-products`,
    SAVED_SHOPS: (userId: number | string) => `/api/v1/admin/customers/${userId}/saved-shops`,
    NOTIFICATIONS: (userId: number | string) =>
      `/api/v1/admin/customers/${userId}/notifications`,
    SAVED_ITEMS: (userId: number | string) => `/api/v1/admin/customers/${userId}/saved-items`,
    ADDRESSES: (userId: number | string) => `/api/v1/admin/customers/${userId}/addresses`,
    TICKETS: (userId: number | string) => `/api/v1/admin/customers/${userId}/tickets`,
    REPORTS: (userId: number | string) => `/api/v1/admin/customers/${userId}/reports`,
    RESTRICT: (userId: number | string) => `/api/v1/admin/customers/${userId}/restrict`,
    STATUS: (userId: number | string) => `/api/v1/admin/users/${userId}/status`,
  },

  // Shops & Verification
   SHOPS: {
    LIST: '/api/v1/admin/shops',
    DETAIL: (shopId: number | string) => `/api/v1/admin/shops/${shopId}`,
    /** Audited partial update of shop master fields. */
    UPDATE: (shopId: number | string) => `/api/v1/admin/shops/${shopId}`,
    /**
     * Shop-scoped sub-resources. Not published on every deployment — the
     * surfaces that read these go through `fetchList`, which reports a 404 as
     * "route not published" rather than an empty result.
     */
    DOCUMENTS: (shopId: number | string) => `/api/v1/admin/shops/${shopId}/documents`,
    PRICING: (shopId: number | string) => `/api/v1/admin/shops/${shopId}/pricing`,
    HOURS: (shopId: number | string) => `/api/v1/admin/shops/${shopId}/hours`,
    VERIFICATION: (shopId: number | string) => `/api/v1/admin/shops/${shopId}/verification`,
    /** Per-stage counts for the queue's tab badges. */
    VERIFICATION_SUMMARY: '/api/v1/admin/shops/verification/summary',
    /** The decision trail for one case, newest first. */
    VERIFICATION_HISTORY: (shopId: number | string) =>
      `/api/v1/admin/shops/${shopId}/verification/history`,
    /** Put a case in a named reviewer's hands, or release it. */
    VERIFICATION_ASSIGN: (shopId: number | string) =>
      `/api/v1/admin/shops/${shopId}/verification/assign`,
    BULK: '/api/v1/admin/shops/bulk',
  },

  // Shopkeepers (Users listing, filtered server-side)
  SHOPKEEPERS: {
    LIST: '/api/v1/admin/shopkeepers',
    DETAIL: (userId: number | string) => `/api/v1/admin/shopkeepers/${userId}`,
    // Merchant-scoped sub-resources. Each backs one tab on the shopkeeper
    // drill-down; they are distinct routes so a tab that fails is visible
    // rather than collapsing the whole merchant record.
    SHOPS: (userId: number | string) => `/api/v1/admin/shopkeepers/${userId}/shops`,
    IMPORTS: (userId: number | string) => `/api/v1/admin/shopkeepers/${userId}/imports`,
    POS_INTEGRATIONS: (userId: number | string) =>
      `/api/v1/admin/shopkeepers/${userId}/pos-integrations`,
    NOTIFICATIONS: (userId: number | string) =>
      `/api/v1/admin/shopkeepers/${userId}/notifications`,
    TICKETS: (userId: number | string) => `/api/v1/admin/shopkeepers/${userId}/tickets`,
  },

  // Products & Catalog
  PRODUCTS: {
    LIST: '/api/v1/admin/products',
    BARCODE_SEARCH: '/api/v1/admin/products/barcode-search',
    DETAIL: (productId: number | string) => `/api/v1/admin/products/${productId}`,
    /** Variants of one master product. Route-by-route like every other
        product surface: unpublished here reads as unavailable, not empty. */
    VARIANTS: (productId: number | string) => `/api/v1/admin/products/${productId}/variants`,
    UPDATE: (productId: number | string) => `/api/v1/admin/products/${productId}`,
    BULK: '/api/v1/admin/products/bulk',
    APPROVALS: '/api/v1/admin/products/approvals',
    REVIEW_LISTING: (listingId: number | string) => `/api/v1/admin/products/listings/${listingId}/review`,
  },

  // Categories & Brands
  CATEGORIES: {
    LIST: '/api/v1/admin/categories',
    CREATE: '/api/v1/admin/categories',
    UPDATE: (id: number | string) => `/api/v1/admin/categories/${id}`,
    DELETE: (id: number | string) => `/api/v1/admin/categories/${id}`,
  },
  BRANDS: {
    LIST: '/api/v1/admin/brands',
    CREATE: '/api/v1/admin/brands',
    UPDATE: (id: number | string) => `/api/v1/admin/brands/${id}`,
    DELETE: (id: number | string) => `/api/v1/admin/brands/${id}`,
  },
  IDENTIFIERS: {
    LIST: '/api/v1/admin/identifiers',
  },

  // Inventory
  INVENTORY: {
    SUMMARY: '/api/v1/admin/inventory/summary',
    STALE: '/api/v1/admin/inventory/stale',
    MISSING_PRICES: '/api/v1/admin/inventory/missing-prices',
    ANOMALIES: '/api/v1/admin/inventory/anomalies',
    SYNC_FAILURES: '/api/v1/admin/inventory/sync-failures',
    SHOP_INVENTORY: (shopId: number | string) => `/api/v1/admin/inventory/shop/${shopId}`,
    RECORD_DETAIL: (shopProductId: number | string) => `/api/v1/admin/inventory/records/${shopProductId}`,
    RECORD_HISTORY: (shopProductId: number | string) => `/api/v1/admin/inventory/records/${shopProductId}/history`,
  },

  // Offers
  OFFERS: {
    LIST: '/api/v1/admin/offers',
    UPDATE_STATUS: (id: number | string) => `/api/v1/admin/offers/${id}/status`,
  },

  // Subscriptions & Payments
  SUBSCRIPTIONS: {
    LIST: '/api/v1/admin/subscriptions',
    UPDATE: (id: number | string) => `/api/v1/admin/subscriptions/${id}`,
    PAYMENTS: '/api/v1/admin/payments',
  },

  // Complaints / Support
  COMPLAINTS: {
    LIST: '/api/v1/admin/complaints',
    DETAIL: (id: number | string) => `/api/v1/admin/complaints/${id}`,
    UPDATE: (id: number | string) => `/api/v1/admin/complaints/${id}`,
    ASSIGN: (id: number | string) => `/api/v1/admin/complaints/${id}/assign`,
    NOTE: (id: number | string) => `/api/v1/admin/complaints/${id}/notes`,
    RESPONSE: (id: number | string) => `/api/v1/admin/complaints/${id}/respond`,
    TIMELINE: (id: number | string) => `/api/v1/admin/complaints/${id}/timeline`,
  },

  // Notifications
  NOTIFICATIONS: {
    SEND: '/api/v1/admin/notifications/send',
    CAMPAIGNS: '/api/v1/admin/notifications/campaigns',
    CAMPAIGN_DETAIL: (id: number | string) => `/api/v1/admin/notifications/campaigns/${id}`,
    // Optional: force-cancel an in-flight campaign (backend-authoritative).
    CAMPAIGN_CANCEL: (id: number | string) => `/api/v1/admin/notifications/campaigns/${id}/cancel`,
  },

  // Content & Announcements (banners, announcements, FAQs, help, promos, system messages)
  CONTENT: {
    BANNERS: '/api/v1/admin/content/banners',
    BANNER_DETAIL: (id: number | string) => `/api/v1/admin/content/banners/${id}`,

    ANNOUNCEMENTS: '/api/v1/admin/content/announcements',
    ANNOUNCEMENT_DETAIL: (id: number | string) => `/api/v1/admin/content/announcements/${id}`,

    FAQS: '/api/v1/admin/content/faqs',
    FAQ_DETAIL: (id: number | string) => `/api/v1/admin/content/faqs/${id}`,

    HELP: '/api/v1/admin/content/help',
    HELP_DETAIL: (id: number | string) => `/api/v1/admin/content/help/${id}`,

    PROMOTIONS: '/api/v1/admin/content/promotions',
    PROMOTION_DETAIL: (id: number | string) => `/api/v1/admin/content/promotions/${id}`,

    SYSTEM_MESSAGES: '/api/v1/admin/content/system-messages',
    SYSTEM_MESSAGE_DETAIL: (id: number | string) => `/api/v1/admin/content/system-messages/${id}`,
  },

  // Reviews & Moderation
  REVIEWS: {
    LIST: '/api/v1/admin/reviews',
    DETAIL: (id: number | string) => `/api/v1/admin/reviews/${id}`,
    MODERATE: (id: number | string) => `/api/v1/admin/reviews/${id}/moderation`,
  },

  // Governance & Audit
  AUDIT: {
    LOGS: '/api/v1/admin/audit-logs',
    ACTIONS: '/api/v1/admin/actions',
    NOTES: '/api/v1/admin/notes',
    NOTE_DETAIL: (id: number | string) => `/api/v1/admin/notes/${id}`,
  },

  // POS Integrations (provider-neutral)
  POS: {
    LIST: '/api/v1/admin/pos/integrations',
    DETAIL: (id: number | string) => `/api/v1/admin/pos/integrations/${id}`,
    SYNC: (id: number | string) => `/api/v1/admin/pos/integrations/${id}/sync`,
    DISCONNECT: (id: number | string) => `/api/v1/admin/pos/integrations/${id}/disconnect`,
    RECONNECT: (id: number | string) => `/api/v1/admin/pos/integrations/${id}/reconnect`,
    SYNC_HISTORY: (id: number | string) => `/api/v1/admin/pos/integrations/${id}/syncs`,
  },

  // Data Imports / Import Center
  IMPORTS: {
    LIST: '/api/v1/admin/imports',
    DETAIL: (id: number | string) => `/api/v1/admin/imports/${id}`,
    ERRORS: (id: number | string) => `/api/v1/admin/imports/${id}/errors`,
    RETRY: (id: number | string) => `/api/v1/admin/imports/${id}/retry`,
    CANCEL: (id: number | string) => `/api/v1/admin/imports/${id}/cancel`,
  },

  // System
  SYSTEM: {
    FEATURE_FLAGS: '/api/v1/admin/feature-flags',
    SETTINGS: '/api/v1/admin/settings',
    SETTING_KEY: (key: string) => `/api/v1/admin/settings/${key}`,
    FEATURE_FLAG_NAME: (name: string) => `/api/v1/admin/feature-flags/${name}`,
    REPORTS: '/api/v1/admin/reports',
    GENERATE_REPORT: '/api/v1/admin/reports/generate',
  },
} as const;
