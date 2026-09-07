# hyperlocal_api_contracts

Single source of truth for the HTTP contract between the backend and the
three clients (customer_app, shopkeeper_app, admin_panel).

| File | What it is |
|------|------------|
| `API_CONTRACT.md` | Human-written full API contract (endpoints, envelopes, auth) |
| `openapi.json` | **Generated** OpenAPI 3.1 spec exported from the FastAPI app — never hand-edit |

## Regenerating `openapi.json`

```powershell
# from repo root
python backend/scripts/export_openapi.py
```

The script boots the FastAPI app (`backend/app/main.py`) and dumps
`app.openapi()` here. CI runs the same script and fails the build if the
committed spec is stale — this makes contract drift impossible to merge.

## Change protocol

1. Change the backend schema/route first (Pydantic models are the source of truth).
2. Regenerate `openapi.json` (script above) and include it in the same PR.
3. Update `API_CONTRACT.md` if the change is user-visible.
4. Update Dart DTOs in `packages/shared_models` **only if** the shared
   envelope/pagination shapes changed — app-specific DTOs live in the apps.
