# PHASE 2 — ARCHITECTURE CONTRACT
**Platform:** HyperLocal Product Discovery Platform — Admin Control Center  
**Document Version:** 1.0.0  
**Status:** Approved & Enforced

---

## 1. Architectural Layers & Flow
Strictly follows Section 5 of the Master Prompt:
```
ADMIN UI (Next.js App Router Components)
  ↓
VIEW / PAGE LAYER (Route-based views & dynamic [id] controllers)
  ↓
FEATURE STATE / URL QUERY STATE (Search params, filters, pagination, sort)
  ↓
QUERY / MUTATION LAYER (TanStack Query v5 hooks)
  ↓
REPOSITORY / API CLIENT (Centralized API client with Auth & Request IDs)
  ↓
FASTAPI ADMIN API (/api/v1/admin/*)
  ↓
AUTHORIZATION GATE & BACKEND SERVICES
  ↓
DATABASE (PostgreSQL / PostGIS / Redis / S3)
```

> **Mandatory Rule:** Frontend is purely a presentation and control layer. The browser must never connect directly to Postgres, Redis, or private cloud credentials.

---

## 2. Directory & Modular Structure
Follows Sections 132 & 133:
```
src/
├── app/                      # Next.js App Router (pages & layouts)
│   ├── (auth)/login/
│   ├── (dashboard)/
│   │   ├── layout.tsx        # App Shell: Sidebar, TopBar, Command Palette
│   │   ├── dashboard/
│   │   ├── customers/
│   │   ├── shopkeepers/
│   │   ├── businesses/
│   │   ├── verification/
│   │   ├── products/
│   │   ├── categories/
│   │   ├── brands/
│   │   ├── inventory/
│   │   ├── pricing/
│   │   ├── offers/
│   │   ├── search/
│   │   ├── locations/
│   │   ├── imports/
│   │   ├── pos/
│   │   ├── notifications/
│   │   ├── support/
│   │   ├── analytics/
│   │   ├── audit/
│   │   ├── system/
│   │   ├── admin-users/
│   │   └── settings/
│   └── layout.tsx            # Global Providers (QueryClient, Theme, Auth)
├── core/
│   ├── api/                  # Single centralized API client & Domain APIs
│   │   ├── client.ts         # Axios/Fetch client with interceptors
│   │   ├── endpoints.ts      # Centralized endpoint constant mapping
│   │   └── modules/          # Domain-specific API wrappers (customers, shops, etc.)
│   ├── auth/                 # Admin session, token refresh, whoami
│   ├── permissions/          # RBAC evaluator, PermissionGuard, FeatureGate
│   ├── realtime/             # WebSocket / SSE connection & query invalidator
│   ├── errors/               # ApiError, ErrorBoundary, global error mapper
│   ├── theme/                # MUI Theme (deep blue, white, electric blue, slate)
│   └── components/           # Core reusable UI abstractions
│       ├── AdminDataGrid.tsx # Standardized server-paginated data grid
│       ├── PageHeader.tsx
│       ├── StatCard.tsx
│       ├── StatusBadge.tsx
│       ├── ConfirmDialog.tsx # High-risk modal with mandatory reason input
│       └── EmptyState.tsx
```

---

## 3. Data & State Management Contract
1. **Server State:** Handled exclusively via TanStack Query (`@tanstack/react-query`). Every domain uses strongly typed query keys (e.g. `['admin', 'shops', { page, status }]`).
2. **Mutations:** Action hooks trigger backend endpoints; on success, affected query keys are invalidated rather than reloading pages.
3. **Table & Filter URL Sync:** All pagination (`page`, `limit`), sorting (`sortBy`, `sortOrder`), and filters (`status`, `search`, `category`) are mirrored in URL search parameters to allow bookmarking, team sharing, and back-button navigation.
4. **Client-Only State:** Limited to ephemeral UI state (sidebar collapse, dialog visibility, draft inputs). No redundant client stores duplicating backend records.

---

## 4. Security & Safety Contract
1. **Never Expose Secrets:** No database credentials or admin master keys in frontend code.
2. **Permission Guarding:** Client UI checks capabilities before displaying actions; backend authoritatively verifies every call.
3. **High-Risk Operations (Section 116 & 117):** Actions such as suspension, bans, product merges, deletions, and broadcast notifications require a double-confirmation modal capturing the operator's reason.
4. **Graceful Error Handling:** 401 triggers session refresh or redirect to `/login`; 403 displays "Permission Denied"; 500+ triggers a localized retry component without crashing the shell.
