# Hyperlocal Admin Panel

Web admin console for the Hyperlocal platform (Flutter web): merchant
verification, moderation queues, platform analytics.

## Status

Scaffold only. The admin REST surface already exists in the backend
(`backend/app/api/routes/admin*.py` - auth-guarded, permission-scoped).
UI flows are wired incrementally.

## Development

````powershell
cd apps/admin_panel
flutter pub get
flutter run -d chrome
````

## Build

````powershell
flutter build web --release
````

## Conventions

- Consume the API through the shared envelope models in
  `packages/shared_models` (already a path dependency).
- The HTTP contract lives in `packages/api_contracts` - read it before
  touching any endpoint integration.
- Auth: admin JWT from the backend auth endpoints; never Firebase
  client auth (admins are platform operators, not end users).