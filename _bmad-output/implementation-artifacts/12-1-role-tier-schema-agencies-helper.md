# Story 12.1: role_tier schema, agencies, and tenant-safe tier helper

Status: review  (migration written + self-reviewed; live `db push` deferred to batch apply)

## Story

As a developer,
I want a `role_tier` dimension and an org-hierarchy schema added additively to `users`,
so that five tiers (+receptionist) exist without changing the `role` claim the shipped RPCs depend on.

## Acceptance Criteria

1. **Given** migration `0057_role_tier_and_hierarchy.sql` **When** applied **Then** enum `public.role_tier` exists with values `super_admin, builder_head, team_leader, front_line_rep, partner_agency, receptionist`.
2. **And** table `public.agencies(id uuid pk, tenant_id uuid not null → tenants, name text not null, created_at timestamptz)` exists with `ENABLE` + `FORCE ROW LEVEL SECURITY` and policy `USING/WITH CHECK (tenant_id = public.auth_tenant_id())`.
3. **And** `public.users` gains `role_tier public.role_tier` (nullable), `reports_to_user_id uuid → users(id) ON DELETE SET NULL`, `is_external boolean NOT NULL DEFAULT false`, `agency_id uuid → agencies(id) ON DELETE SET NULL`.
4. **And** existing users backfilled: `role_tier = builder_head` where `role='admin'`, else `front_line_rep`.
5. **And** `public.auth_role_tier()` returns `app_metadata.role_tier`, falling back to `builder_head`/`front_line_rep` derived from the `role` claim when the claim is absent (zero-downtime for existing JWTs). GRANT EXECUTE to `authenticated, service_role`.
6. **And** indexes `users_reports_to_idx (reports_to_user_id) WHERE NOT NULL` and `users_agency_idx (agency_id) WHERE NOT NULL` exist.
7. **And** an RLS smoke test confirms a query with no `app.current_tenant`/JWT tenant returns 0 rows from `agencies`.

## Tasks / Subtasks

- [ ] **Task 1 — Write migration `0057`** (AC 1-6)
  - [ ] `CREATE TYPE public.role_tier AS ENUM (...)` (6 values incl. `receptionist`).
  - [ ] `CREATE TABLE public.agencies` + `ENABLE`/`FORCE` RLS + tenant policy (mirror `0009` leads policy shape, `public.auth_tenant_id()`). `GRANT SELECT,INSERT,UPDATE,DELETE ON public.agencies TO authenticated`.
  - [ ] `ALTER TABLE public.users ADD COLUMN ...` (4 cols).
  - [ ] Backfill `UPDATE public.users SET role_tier = CASE WHEN role='admin' THEN 'builder_head'::role_tier ELSE 'front_line_rep'::role_tier END WHERE role_tier IS NULL`.
  - [ ] `CREATE OR REPLACE FUNCTION public.auth_role_tier()` (LANGUAGE sql STABLE, `SET search_path=''`) per arch §1.1. GRANT EXECUTE.
  - [ ] Two partial indexes.
  - [ ] Header comment naming FR-39 + Story 12.1 + arch refs.
- [ ] **Task 2 — Apply** (AC 1): `supabase migration list` → `supabase db push --linked`. NEVER MCP `apply_migration` (CLAUDE.md rule 2).
- [ ] **Task 3 — RLS smoke + helper test** (AC 5,7): add to `supabase/tests/rls/` a query asserting `agencies` returns 0 rows without tenant context; assert `auth_role_tier()` returns derived tier when no `role_tier` claim and stamped tier when present.
- [ ] **Task 4 — Regenerate types**: `supabase gen types typescript --linked > packages/shared-types/index.ts`.

## Dev Notes

- **Additive only.** No existing column/enum altered. `user_role` enum (`admin`/`employee`) and the JWT `role` claim are untouched — this is the whole safety strategy (arch §1.1). Do NOT rename `role` or expand `user_role`.
- `auth_role_tier()` MUST fall back to a derived tier so existing JWTs (no `role_tier` claim) keep working until 12.3 stamps them. [Source: architecture-builder-ops-v2.md §1.1, §2.1]
- Tenant policy uses the existing `public.auth_tenant_id()` helper (migration `0003`), not the GUC. [Source: 0003_cr_patch_jwt_only_rls.sql]
- Hierarchy constraints (reports_to higher tier, cycle reject, partner needs agency) are enforced in the **edit-user RPC** (Story 12.4), NOT as DB CHECKs — matches the codebase's app-layer-validation convention. [Source: 0009 interest_type pattern]
- Migration target: `0057` (head is `0056_tenant_lifecycle_status.sql`). [Source: sprint-status.yaml]
- Mobile not touched → no `flutter analyze`. Pure DDL + 1 helper fn.
- Keep `_bmad-output/` (canonical) and `nirman-crm/_bmad-output/` story copies in sync. [Source: CLAUDE.md]

## References
- [Source: epics.md#Story 12.1]
- [Source: architecture-builder-ops-v2.md §1.1 role-mapping, §2.1 schema, §2.2 visible_user_ids, §13.1 actors]
- [Source: nirman-crm/CLAUDE.md — file-based migrations via `supabase db push --linked`; never MCP apply_migration]
- [Source: 0001_init_tenants_users.sql (user_role enum, users table), 0003 (auth_tenant_id), 0009 (RLS+FORCE policy shape)]

## Implementation (2026-06-27)

**File:** `nirman-crm/supabase/migrations/0057_role_tier_and_hierarchy.sql`

Built to conventions confirmed from live migrations (0001/0003/0009/0056): `extensions.gen_random_uuid()`, `DO $$ IF NOT EXISTS … CREATE TYPE`, `ENABLE`+`FORCE` RLS, `public.auth_tenant_id()` policy, explicit GRANTs, `BEGIN;…COMMIT;`.

- role_tier enum (6 values incl. `receptionist`).
- `agencies` table + indexes + RLS.
- `users` += `role_tier, reports_to_user_id, is_external, agency_id` (all `IF NOT EXISTS`); backfill admin→builder_head else front_line_rep; two partial indexes.
- `auth_role_tier()` STABLE, claim-with-role-fallback, grants mirror `auth_tenant_id()`.

**Self-review fix applied:** initial `agencies` policy was `FOR ALL` (any tenant member could write). Tightened to SELECT-all-in-tenant + **admin-only DML** (insert/update/delete), mirroring the `users` policy split in `0003`. Partner/receptionist members can read agency names but not mutate.

**Verification:** static review vs codebase patterns (no destructive DDL; additive only; no `ALTER TYPE ADD VALUE` so `BEGIN/COMMIT` is safe). **Runtime verification deferred** to the batch `supabase db push --linked` (with RLS smoke test: `agencies` returns 0 rows without tenant context). No mobile/web touched → no `flutter analyze`.

**Status:** code-complete, awaiting apply + code-review.
