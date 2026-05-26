# create-employee Edge Function

## Purpose

Creates a new employee account in both `auth.users` and `public.users`, generates a 12-character cryptographically secure temporary password, and returns the plaintext **exactly once** in the response. The plaintext is never written to the database, never logged, and never included in any subsequent response.

## Request

**Method:** `POST`  
**Auth:** Admin JWT required (`Authorization: Bearer <admin_jwt>`)

```json
{
  "username": "alice"
}
```

`username` is lowercased before storage. Min 3 chars, max 100.

## Response

**201 Created**

```json
{
  "data": {
    "user_id": "<uuid>",
    "temp_password": "<12-char plaintext — shown once>"
  }
}
```

## Error Codes

| HTTP | Code | Trigger |
|------|------|---------|
| 400 | `validation_error` | Invalid/missing `username`, non-POST method |
| 401 | `unauthorised` | Missing or invalid JWT |
| 403 | `forbidden_role` | Caller is not an admin |
| 409 | `user_already_exists` | `username` already registered in this tenant (case-insensitive) |
| 500 | `internal_error` | Auth user creation or bcrypt failure (auth user cleaned up on failure) |

## Plaintext-once guarantee

1. `tempPassword` is generated in-memory with `crypto.getRandomValues()` (CSPRNG).
2. Bcrypt hash (cost 12) is stored in `public.users.bcrypt_password_hash`.
3. `tempPassword` appears **only** in the `201` response body — never in logs, never in DB.
4. On any failure after auth user creation, `adminClient.auth.admin.deleteUser()` rolls back the `auth.users` entry.
5. After the response is sent, the plaintext has no persistence path — not in cache, not in logs, not in DB.

## Side effects

- Creates `auth.users` entry (UUID, `app_metadata: {tenant_id, role: "employee"}`, email confirmed).
- Creates `public.users` row (`role = employee`, `must_change_password = true`, `is_active = true`).
- Inserts `user_events` row (`event_type = account_created`, `actor_id = admin UUID`) — best-effort; failure does not fail the response.
