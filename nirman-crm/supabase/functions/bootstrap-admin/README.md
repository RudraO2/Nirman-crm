# bootstrap-admin

**Story 1.2** — One-time setup function that creates the initial Admin account for the Nirman CRM.

> ⚠️ Run once only. After the admin account exists, subsequent calls return HTTP 409.

## Purpose

Creates:
1. A Supabase Auth user (`auth.users`) with `app_metadata = {tenant_id, role: "admin"}` and `email_confirm = true`
2. A matching `public.users` profile row with the same UUID, bcrypt hash (cost 12), `role = admin`, `must_change_password = false`

## Required Secrets (Supabase Dashboard → Settings → Edge Functions → Secrets)

| Secret | Description |
|--------|-------------|
| `BOOTSTRAP_SECRET` | Pre-shared bearer token to protect this endpoint. Generate with `openssl rand -base64 32`. |
| `SUPABASE_URL` | Auto-injected by Supabase Edge runtime. |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-injected by Supabase Edge runtime. |

## Request

```
POST /functions/v1/bootstrap-admin
Authorization: Bearer <BOOTSTRAP_SECRET>
Content-Type: application/json

{
  "email": "admin@yourdomain.com",
  "password": "StrongPassword1"
}
```

**Password requirements:** min 8 chars, at least 1 uppercase, 1 lowercase, 1 number.

## Responses

| Status | Code | Meaning |
|--------|------|---------|
| 201 | — | Admin created successfully |
| 400 | `validation_error` | Invalid input or weak password |
| 401 | `unauthorised` | Missing or wrong `BOOTSTRAP_SECRET` |
| 409 | `user_already_exists` | Admin already exists for this tenant |
| 500 | `internal_error` | Unexpected failure (check edge-function logs) |

### Success (201)

```json
{
  "data": {
    "user_id": "<uuid>",
    "email": "admin@yourdomain.com",
    "role": "admin"
  }
}
```

## How to invoke

```bash
curl -X POST https://<project-ref>.supabase.co/functions/v1/bootstrap-admin \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <BOOTSTRAP_SECRET>" \
  -d '{"email":"admin@nirmanmedia.com","password":"<strong-password>"}'
```

## Idempotency

Checks `public.users` for an existing `role = admin` row before creating. Safe to re-run after failure — the function rolls back the `auth.users` entry if the `public.users` insert fails.

## Logs

Structured JSON logs via `console.log/error` — visible in Supabase Dashboard → Logs → Edge Functions.

## Security Notes

- `BOOTSTRAP_SECRET` is a pre-shared bearer token, NOT a JWT. It authenticates the bootstrap caller before any user exists.
- The service-role key (auto-injected) is never returned in responses.
- No user enumeration: the 409 response does not reveal which email is registered.
- After setup, the admin logs in via `supabase.auth.signInWithPassword()` — JWT will contain `app_metadata.role = "admin"` and `app_metadata.tenant_id`.
