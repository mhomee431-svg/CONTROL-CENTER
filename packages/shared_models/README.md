# hyperlocal_shared_models

Genuinely-shared Dart models for the Hyperlocal Flutter apps
(customer_app, shopkeeper_app, admin_panel).

## Governance (read before adding anything)

This package exists to prevent DTO drift between the three Flutter apps,
**not** to become a dumping ground. The dependency graph is one-directional:

```
apps/*  ──▶  packages/shared_models  ──▶  (nothing — leaf package)
```

Rules, enforced in code review + CI:

1. **One direction only.** This package must never import from any app,
   use Flutter widgets, or reference app-specific services. Pure Dart only
   (`flutter` dependency NOT allowed — this stays a plain Dart package so it
   can later be reused by tooling).
2. **Only genuinely shared contracts.** A model goes here when *at least two
   apps* consume the exact same shape from the backend API. App-specific
   models stay inside their app.
3. **Source of truth is the backend.** These DTOs mirror the FastAPI response
   envelope defined in `backend/app/core/responses.py` (and the full contract
   in `packages/api_contracts/API_CONTRACT.md`). When the backend changes a
   shape, this package changes in the same PR.
4. **Additive changes only.** Never rename/remove a field without a backend
   migration plan — old app versions keep calling the API.

## Current contents

| File | Mirrors |
|------|---------|
| `lib/src/api_envelope.dart` | `success_response()` / `error_response()` in `backend/app/core/responses.py` |

## Usage

In an app's `pubspec.yaml`:

```yaml
dependencies:
  hyperlocal_shared_models:
    path: ../../packages/shared_models
```

```dart
import 'package:hyperlocal_shared_models/hyperlocal_shared_models.dart';

final envelope = ApiEnvelope.fromJson(response.data);
if (envelope.success) {
  final shop = envelope.dataAs<Shop>();
}
```
