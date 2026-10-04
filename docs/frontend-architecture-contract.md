# Admin frontend architecture contract
## Request flow
`Admin UI → View/Page → Feature state → TanStack Query mutation/query → apiClient → FastAPI Admin API → authorization → database/services`

The browser does not connect to PostgreSQL, Redis, S3, AWS services, or any other infrastructure directly. All authoritative reads and writes use `src/core/api/client.ts` and the endpoint map in `src/core/api/endpoints.ts`.

## Source of truth
Backend/database state is authoritative for users, roles, businesses, products, inventory, prices, offers, verification, notifications, analytics, and system state. The frontend stores only ephemeral UI state and in-memory request/session state. It does not create a database or persist platform records in browser storage.

## Authentication
Admin authentication is backend-controlled. Login calls the approved `/api/v1/admin/auth/login` endpoint through `apiClient` with `credentials: 'include'`. The preferred backend contract is an HttpOnly, Secure, SameSite session cookie. A returned bearer token is held in memory only as a compatibility bridge for the current runtime and is never written to localStorage, sessionStorage, cookies, IndexedDB, or other browser persistence.

The frontend cannot manufacture an admin session. If the backend has no admin-auth implementation, the login UI remains only an integration contract and the backend must provide the endpoint, cookie policy, authorization, expiry, logout, and `/api/v1/admin/me` profile response.

## Realtime
WebSocket/SSE connects only to approved backend realtime endpoints. Realtime data is presentation state and is not treated as authoritative storage.
