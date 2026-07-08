# reset-employee-password

Admin-triggered password reset (forgot-password recovery). Generates a new temporary
password for any account in the caller's tenant and returns it **once**.

## Behaviour

1. Verifies the caller JWT — must be `role = admin`.
2. Confirms the target user exists in the caller's tenant (cross-tenant reset blocked).
3. Generates a 12-char secure temp password (same policy as `create-employee`).
4. Updates **both** password stores in lockstep:
   - `auth.users` via `auth.admin.updateUserById` (hash used by `signInWithPassword`).
   - `public.users.bcrypt_password_hash` (hash `login` verifies first).
5. Sets `must_change_password = true` — the user is forced to change it on next login.
6. Revokes all existing sessions (`auth.admin.signOut(id, "global")`).
7. Appends a `password_reset_by_admin` row to `user_events` (audit, best-effort).

**Uniform by design:** no role-based target restriction and no per-user special cases.
Any admin can reset any account in their own tenant (including another admin, or self).
The admin UI surfaces this only for employees, because the Team page lists employees.

## Request

```
POST /functions/v1/reset-employee-password
Authorization: Bearer <admin access_token>
Content-Type: application/json

{ "targetUserId": "<uuid>" }
```

## Responses

| Status | Code | Meaning |
|--------|------|---------|
| 200 | — | Reset succeeded; body carries the new temp password |
| 400 | `validation_error` | Bad JSON / missing/invalid `targetUserId` / target not in tenant |
| 401 | `unauthorised` | Missing or invalid caller JWT |
| 403 | `forbidden_role` | Caller is not an admin |
| 500 | `internal_error` | Hash / auth / DB failure (safe to retry — retry self-heals any desync) |

### Success (200)

```json
{ "data": { "temp_password": "Xy7$k2Pm9qRt" } }
```

## Notes

- The plaintext password is returned **once** and never logged. Convey it out of band.
- If step 7 (`public.users` update) fails after step 6 (`auth.users` update) the two
  stores are briefly out of sync; a retry regenerates and re-sets both, self-healing.
- No migration required — the `password_reset_by_admin` enum value already exists
  (`0004_create_user_events.sql`).
