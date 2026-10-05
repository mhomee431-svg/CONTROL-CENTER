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
    STATUS: (userId: number | string) => `/api/v1/admin/users/${userId}/status`,
  },

  // Shops & Verification
   SHOPS: {
    LIST: '/api/v1/admin/shops',
    DETAIL: (shopId: number | string) => `/api/v1/admin/shops/${shopId}`,
    VERIFICATION: (shopId: number | string) => `/api/v1/admin/shops/${shopId}/verification`,
    BULK: '/api/v1/admin/shops/bulk',
  },

  // Shopkeepers (Users listing, filtered server-side)
  SHOPKEEPERS: {
    LIST: '/api/v1/admin/shopkeepers',
    DETAIL: (userId: number | string) => `/api/v1/admin/shopkeepers/${userId}`,
  },

  // Products & Catalog
  PRODUCTS: {
    LIST: '/api/v1/admin/products',
    BARCODE_SEARCH: '/api/v1/admin/products/barcode-search',
    DETAIL: (productId: number | string) => `/api/v1/admin/products/${productId}`,
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
    UPDATE: (id: number | string) => `/api/v1/admin/complaints/${id}`,
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
