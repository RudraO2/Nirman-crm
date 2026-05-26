# `_shared/` — Edge Function helpers

Reusable utilities imported by every Edge Function. No public HTTP surface.

## Files

| File | Purpose |
|------|---------|
| `auth.ts` | `verifyJwtAndScope(req)` — JWT verify + bind `app.current_tenant` via `set_current_tenant` RPC. Returns `AuthedContext` or `AuthFailure` with prebuilt 401/403 Response. |
| `errors.ts` | Canonical `ErrorCode` enum, `ApiError`/`ApiSuccess`/`ApiResult` types, `errorResponse()` and `successResponse()` builders, HTTP status mapping. |

## Usage

```ts
import { verifyJwtAndScope, isAuthFailure } from "../_shared/auth.ts";
import { successResponse } from "../_shared/errors.ts";

Deno.serve(async (req) => {
  const ctx = await verifyJwtAndScope(req);
  if (isAuthFailure(ctx)) return ctx.response;

  // ctx.supabase is RLS-scoped to ctx.tenantId for the rest of this request
  const { data, error } = await ctx.supabase.from("tenants").select("*");
  if (error) return errorResponse("internal_error", error.message);
  return successResponse(data);
});
```

## Contract Reminders

- Never query tables outside an Edge Function without first calling `set_current_tenant` — RLS will return zero rows.
- Service-role clients bypass RLS by default (Postgres `BYPASSRLS` attribute). Use sparingly; always set `app.current_tenant` even on service-role clients for defense-in-depth.
- Tests for these helpers live alongside the function that consumes them; there's no unit-test runner for `_shared/` itself in V1.
