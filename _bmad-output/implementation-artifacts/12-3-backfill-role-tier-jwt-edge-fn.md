# Story 12.3: stamp role_tier into JWT via backfill edge function

Status: review  (edge fn written + self-reviewed; deploy + run deferred to batch apply)

## Story

As an admin,
I want existing users' `app_metadata.role_tier` stamped server-side,
so that tier claims become explicit on next token refresh and leaders gain subtree authority.

## Acceptance Criteria

1. **Given** a service-role edge function `backfill-role-tier` (mirrors Epic 8 `signup-create-tenant` privileged-stamping) **When** it runs **Then** each `auth.users` row is stamped `app_metadata.role_tier` = matching `public.users.role_tier` via `auth.admin.updateUserById`.
2. **And** running it twice is idempotent — no double-stamp; a manually-set tier is not clobbered (skip rows already carrying the correct tier).
3. **And** a user who re-authenticates afterward carries `role_tier` in their JWT.
4. **And** no client path can write `app_metadata` (only this service-role function).

## Tasks / Subtasks

- [ ] **Task 1 — Edge fn** `supabase/functions/backfill-role-tier/index.ts` (+ README): service-role client; page `auth.admin.listUsers`; for each, look up `public.users.role_tier` by id; if JWT `app_metadata.role_tier` ≠ DB value, `updateUserById(id,{app_metadata:{...existing, role_tier}})`. `verify_jwt=false` is NOT appropriate — gate to `role='admin'` caller OR run as a one-shot ops script invoked with service-role key. Choose admin-gated invoke (consistent with create-employee).
- [ ] **Task 2 — Idempotency** (AC 2): merge into existing `app_metadata` (never overwrite `tenant_id`/`role`); skip if already correct. Log counts {stamped, skipped}.
- [ ] **Task 3 — Deploy + run**: `supabase functions deploy backfill-role-tier`; invoke once; verify a sample user's JWT after refresh carries the claim.

## Dev Notes

- Preserve existing `app_metadata.tenant_id` + `role` — spread then add `role_tier`. Clobbering `tenant_id` would break RLS for that user. [Source: nirman-crm/CLAUDE.md auth gotcha — public.users.id must equal auth.users.id]
- Pattern reference: Epic 8 `signup-create-tenant` stamps `app_metadata` via `auth.admin.updateUserById`. [Source: architecture.md Decision 31; architecture-builder-ops-v2.md §1.1]
- Run AFTER 12.1 (role_tier column populated). Leaders won't get subtree visibility (12.5) until stamped + token refresh — sequence this before enabling leader features. [Source: architecture-builder-ops-v2.md §10 flag 5]
- No migration. Edge fn only. No mobile.

## References
- [Source: epics.md#Story 12.3]
- [Source: architecture-builder-ops-v2.md §1.1 backfill-role-tier, §10 flag 5]
- [Source: supabase/functions/create-employee — admin-gated edge fn pattern]

## Implementation (2026-06-27)

**Files:** `nirman-crm/supabase/functions/backfill-role-tier/index.ts` + `README.md`.

- Import structure + `verifyJwtAndScope`/`isAuthFailure`/`errorResponse`/`successResponse` usage copied verbatim from the working `create-employee` fn (`./_shared/...`).
- Admin-gated (`role==='admin'`). **Tenant-scoped**: drives from `public.users WHERE tenant_id = caller` (service client bypasses RLS → explicit filter) so an admin only stamps their own tenant.
- Per user: `getUserById` → skip if `app_metadata.role_tier` already correct (idempotent) → else `updateUserById` with `{ ...meta, role_tier }` (spread preserves `tenant_id` + `role`). Returns `{ stamped, skipped, errors }`. Structured logs; no secrets logged.

**Self-review:** metadata spread is the critical safety point — clobbering `tenant_id` would break that user's RLS; verified preserved. Null `role_tier` guarded (0057 backfill prevents it, but skip-with-count anyway). Re-run is safe (skip path).

**Verification:** static (matches proven create-employee pattern). Deploy (`supabase functions deploy backfill-role-tier`) + one invocation + JWT-after-refresh check deferred to apply step. No migration, no mobile/web.

**Status:** code-complete, awaiting deploy + run.
