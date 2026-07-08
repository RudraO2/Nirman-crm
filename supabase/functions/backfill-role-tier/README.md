# backfill-role-tier

Story 12.3 — one-off (re-runnable) ops job that stamps `app_metadata.role_tier` onto existing
auth users so the fine-grained tier appears in their JWT on next token refresh.

- **Method:** `POST` (no body).
- **Auth:** admin only (`role='admin'`, i.e. `builder_head`). Tenant-scoped — stamps only the
  caller's tenant's users (driven from `public.users`).
- **Idempotent:** skips users whose `app_metadata.role_tier` already matches
  `public.users.role_tier`. Preserves `tenant_id` + `role` (metadata spread).
- **Returns:** `{ data: { stamped, skipped, errors } }`.

## When to run
After migration `0057` (which populates `public.users.role_tier`) and before enabling leader
features (12.5) — leaders only gain subtree visibility once their JWT carries `role_tier`
(until then `auth_role_tier()` falls back to a rep tier). Users must re-authenticate (or refresh)
to pick up the stamped claim.

## Deploy
`supabase functions deploy backfill-role-tier`
Then invoke once (admin JWT). `SUPABASE_SERVICE_ROLE_KEY` is platform-injected.

## Notes
- Mirrors the `create-employee` privileged-stamping pattern (`auth.admin.updateUserById`).
- No `app_metadata` write path exists for clients — only this + signup/accept-invite.
