# manage-employee

Story 1.6 — Admin deactivates and reactivates Employee accounts.

## Purpose

Allows an Admin to deactivate or reactivate an Employee account:
- **Deactivate**: sets `public.users.is_active = false` and calls `auth.admin.signOut(userId, 'global')` to immediately invalidate all existing tokens.
- **Reactivate**: sets `public.users.is_active = true`.

Both actions are logged to `user_events`.

## Auth

Requires a valid JWT with `role = admin` in `app_metadata`. Employee JWTs return 403.

## Request

```
POST /functions/v1/manage-employee
Authorization: Bearer <admin-jwt>
Content-Type: application/json

{
  "action": "deactivate" | "reactivate",
  "targetUserId": "<uuid>"
}
```

## Response

**200 OK**
```json
{ "data": { "is_active": false } }
```

**200 OK (idempotent — already in desired state)**
```json
{ "data": { "is_active": false, "already": true } }
```

## Error Codes

| HTTP | Code | Condition |
|------|------|-----------|
| 400 | `validation_error` | Invalid body, self-deactivation attempt, targeting admin |
| 401 | `unauthorised` | Missing or invalid JWT |
| 403 | `forbidden_role` | Caller is not admin |
| 500 | `internal_error` | DB update failed |

## Idempotency

If the employee is already in the desired state, returns 200 with `already: true`. Safe to retry.

## Token Revocation

`auth.admin.signOut(userId, 'global')` removes all `auth.sessions` entries for that user. Subsequent calls to `verifyJwtAndScope` (which calls `supabase.auth.getUser(jwt)`) will return 401. Revocation is **immediate** — exceeds the 60-second SLA in Story 1.6 AC-2.

## Constraints

- AC-8: Admin cannot deactivate their own account.
- AC-9: Only employee accounts can be deactivated (admin-targeting returns 400).
- `signOut` failure is non-fatal: `is_active=false` already blocks new logins via the `login` Edge Function.
