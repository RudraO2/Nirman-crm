# change-password Edge Function

**Story:** 1.5 — Force password change on first login + self-service password change

## Purpose

Allows authenticated users (employees and admins) to change their password. Enforces current-password verification, complexity requirements, and syncs both `public.users.bcrypt_password_hash` and `auth.users` (dual-store pattern established in Stories 1.2–1.4).

## Auth

Requires `Authorization: Bearer <jwt>` header. Both `employee` and `admin` roles accepted. Returns HTTP 401 if JWT is missing or invalid.

## Request

```json
POST /functions/v1/change-password
Content-Type: application/json
Authorization: Bearer <access_token>

{
  "currentPassword": "string (1–200 chars)",
  "newPassword": "string (8–200 chars, complexity enforced)"
}
```

### New Password Complexity

- Minimum 8 characters
- At least one uppercase letter (A–Z)
- At least one lowercase letter (a–z)
- At least one digit (0–9)

## Response (200 OK)

```json
{
  "data": {
    "access_token": "string",
    "refresh_token": "string",
    "expires_at": 1234567890
  }
}
```

The client MUST replace the current session with these new tokens — they carry updated `app_metadata.must_change_password: false`.

## Error Codes

| HTTP | Code | When |
|------|------|------|
| 400 | `validation_error` | Wrong current password / complexity failure / bad JSON |
| 401 | `unauthorised` | Missing or invalid JWT |
| 500 | `internal_error` | Bcrypt failure / auth update failure / credential sync failure |

## Dual-Store Sync

Updates `auth.users` first, then `public.users`. If `public.users` fails, logs `credential_sync_failure` at severity=error.

## Credential Logging Guarantee

`currentPassword` and `newPassword` are NEVER logged anywhere.
