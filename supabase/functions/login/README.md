# login — Platform-segregated authentication + rate limiting

**Story:** 1.4, 1.7  
**FR:** FR-30 (platform segregation), FR-38 (rate limiting), NFR-6 (JWT expiry), NFR-9 (bcrypt)  
**verify_jwt:** `false` — this is the login endpoint, callers have no JWT yet

## Purpose

Issues Supabase JWTs after validating credentials, enforcing platform segregation, and blocking locked accounts.  
Employee accounts are blocked from web access **before** any JWT is issued.  
Accounts locked due to repeated failures are blocked **before** bcrypt runs.

## Request

```
POST /functions/v1/login
Content-Type: application/json
apikey: <anon_key>
```

```json
{
  "username": "user@example.com",
  "password": "their_password",
  "platform": "web" | "mobile"
}
```

## Response — Success (200)

```json
{
  "data": {
    "access_token": "<jwt>",
    "refresh_token": "<token>",
    "expires_at": 1234567890,
    "role": "admin" | "employee",
    "must_change_password": false
  }
}
```

## Error Codes

| HTTP | code | When |
|------|------|------|
| 400 | `validation_error` | Missing or invalid fields |
| 401 | `unauthorised` | Wrong credentials or deactivated account |
| 403 | `unauthorised_platform` | Employee credentials used on `platform: "web"` |
| 429 | `account_locked` | Account locked after 5 failed attempts in 10 minutes |
| 500 | `internal_error` | DB lookup failed or Supabase Auth error |

## Platform Segregation Design

`platform` is provided by the client. This is intentional V1 design — security is layered:

1. **This function:** `role=employee + platform=web → 403` before any JWT issues.
2. **`src/middleware.ts`:** signs out any non-admin session on `/(app)/*` routes.
3. **`(app)/layout.tsx`:** checks `role !== "admin"` and redirects.

No single bypass breaks all three layers.

## Rate Limiting Design (Story 1.7)

5 consecutive failed attempts within a 10-minute window → 15-minute lockout.

**Check order:**
1. User lookup (service-role)
2. **Lockout check** — if `locked_until > now()` → 429 immediately (no bcrypt)
3. Bcrypt verify (constant-time — runs even for unknown usernames)
4. On failure: insert `auth_failed_attempts` row (fire-and-forget); count fails in last 10 min; lock if ≥ 5
5. On success: clear `locked_until`; insert success row (fire-and-forget)

Admin can unlock via `manage-employee` with `action: "unlock"`.

## Security Rules

- **NEVER log** `username`, `password`, `access_token`, `refresh_token`, or any substring.
- Bcrypt comparison always runs (constant-time), even for non-existent usernames — prevents user enumeration via timing.
- `is_active` is checked **after** bcrypt verify to prevent timing oracle on active vs inactive accounts.
- Platform check fires **after** credential validation — prevents platform enumeration.
- Early return for locked accounts is acceptable — attacker triggered lockout themselves and already knows the account exists.
