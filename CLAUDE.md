# Nirman CRM — Agent Operating Guide

**Read this before touching git, Supabase, or migrations. It records work already
done so a fresh session does not redo or break it.** Last updated: 2026-07-08.

Repo: https://github.com/RudraO2/Nirman-crm · Supabase project: `vhgruadourflpxuzuxfn`

---

## 🔒 Git — DO NOT redo

- **`main` is the canonical, default branch.** All shipped work lives on `main`.
  Develop on `main` or a fresh `feat/epic-N-*` branch; push to `main`.
- The old `feat/1.x` / `feat/2.x` branches are **abandoned rebased duplicates**.
  8 of them (`feat/1.1-1.3`, `feat/1.5-1.8`) still exist on origin and show as
  "un-merged" because they were rebased/recreated — **their content is already in
  `main`. Do NOT merge them back in.** They will create massive false conflicts.
- Two histories were merged into `main` on 2026-05-28 (Epic 1.5–1.8 ⨉ Epic 2+3).
  Conflicts were hand-resolved to the superset. Do not "re-fix" merged files.

## 🔒 Supabase migrations — DO NOT redo, DO NOT use MCP apply

- Migrations are **file-based**, `supabase/migrations/0001…0086`, applied with
  **`supabase db push --linked`** (CLI 2.101, already `link`ed). **Prod is at 0086
  as of 2026-07-08** (0085 flexible unit numbering + 0086 unit add/rename/delete;
  builder-ops 0057–0084 before that; lead data verified untouched).
- **NEVER use the MCP `apply_migration` tool** — it creates timestamp-named entries
  that desync the migration history (this already had to be repaired once). Always
  add the next numbered file (after `0084`) and `db push`.
- Before adding a migration run `supabase migration list` to confirm state.
- Inline hotfixes 0027/0028 were applied via SQL editor and also exist as files.
- Ad-hoc **prod SQL (read or write) without service key: `supabase db query --linked "SQL"`**.
- The local-only `00075_local_seed_tenant.sql` shim was deleted 2026-07-07 (pre-push);
  recreate it only for a from-scratch local reset, and delete again before any push.

## 🔒 Push notifications (Epic 3.5/3.6/3.7) — DONE + verified, DO NOT redo

- `FCM_SERVICE_ACCOUNT` edge secret **is set** (Firebase project `crm-lms-57c5d`).
- `process-overdue-followups` + `send-followup-notifications` edge fns deployed.
- pg_cron jobs **scheduled + active** (every 1 min / 5 min). pg_cron + pg_net enabled.
- `SUPABASE_SERVICE_ROLE_KEY` env is platform-injected; do not set it.
- Verified live 2026-05-28: invoking the fn returned `{"sent":1}` (FCM accepted token).
- **Story 8.3 (2026-07-09) superseded the old "cron needs no secret" note.** The 3
  cron fns (`process-overdue-followups`, `send-followup-notifications`, `streak-at-risk`)
  now enforce a shared `CRON_SECRET` in the `x-cron-secret` header (in-function, still
  `--no-verify-jwt`). Migration `0087_cron_secret_auth.sql` re-schedules the jobs to send it.
  **Required post-deploy config (both values identical):**
    - `SELECT vault.create_secret('<SECRET>', 'cron_secret');` (for the cron SQL)
    - `supabase secrets set CRON_SECRET='<SECRET>'` (for the edge fns)
  Generate once (`openssl rand -hex 32`). Without both, scheduled pushes will 401.
  The 4 admin fns also now authenticate their caller (2 via admin JWT, 2 via service-role
  bearer) — see story `8-3-harden-edge-function-auth.md`.

## 🔒 Admin `next dev` points at PROD (footgun — 2026-07-08)

- `apps/admin/.env.development.local` (which overrode `.env.local` in `next dev` to
  hit the local Docker stack `127.0.0.1:54321`) was **renamed to `.env.development.local.bak`**.
  So `npm run dev` in `apps/admin` now talks to **PRODUCTION** Supabase.
- **Consequence:** editing employees / running admin actions in local dev mutates
  **real prod data**. There is no visual difference. Treat local admin as prod.
- To go back to the local stack: `mv .env.development.local.bak .env.development.local`
  (and `supabase start` for the Docker stack). Delete the `.bak` to make prod permanent.

## Password reset (2026-07-08) — DO NOT special-case

- Edge fn `reset-employee-password` (admin-only, tenant-scoped, deployed to prod)
  generates a temp password and updates **BOTH** stores in lockstep, same as
  `create-employee`: `auth.users` (GoTrue) **and** `public.users.bcrypt_password_hash`
  (login verifies the latter first, then `signInWithPassword`). Sets
  `must_change_password=true`, signs out all sessions, audit-logs `password_reset_by_admin`
  (enum value already in 0004). Surfaced in Team→Accounts. Uniform — no per-user/role guards.
- To reset a password directly in SQL (both stores), use pgcrypto in `extensions` schema:
  `crypt('<pw>', extensions.gen_salt('bf', 12))` — bcryptjs-compatible ($2a).

## Auth gotcha (don't regress)

- Mobile login uses `supabase.auth.setSession(refreshToken)` — NOT `recoverSession`
  (recoverSession threw `FormatException: Expected user to be an object, got Null`
  on device). Keep `setSession`.
- `public.users.id` must equal the matching `auth.users.id` (FK target for
  `leads.assigned_to_user_id`). JWT carries `app_metadata.tenant_id` + `role`.

## Current status (truth — see `_bmad-output/implementation-artifacts/sprint-status.yaml`)

- Epics 1–4, 7, 10 shipped; **Epic 11 (web WhatsApp templates) implemented 2026-07-07**:
  admin `/templates` page (CRUD + variable chips + preview, Team nav group), mobile
  8-token send-time substitution, and the **wa.me missing-`91` bug** fixed in
  `whatsapp_sheet.dart`. See `_bmad-output/implementation-artifacts/11-web-whatsapp-template-management.md`.
- **Builder-ops (Epics 12–16) backend DEPLOYED to prod 2026-07-07**: migrations
  0057–0084 + edge fns (create-lead, update-lead, manage-employee, backfill-role-tier,
  send-developer-update, send-amendment-notification). Before/after lead counts identical
  (1673 total / Sangeeta 1668). `backfill-role-tier` fn not yet invoked (needs live admin
  JWT; optional — `auth_role_tier()` falls back from role). Mobile builder-ops UI deferred.
- **Git ↔ prod reconciled 2026-07-08.** All the above shipped/prod work was previously
  **disk-only (uncommitted)** — migrations 0054–0084, edge fns, admin builder-ops pages,
  mobile alarms (Epic 10) + whatsapp fix (11), and the whole `apps/marketing` landing page.
  Now committed + pushed to `main` (fast-forward, 23 commits). Generated `ios/Flutter/*`
  glue untracked + gitignored; `*.bak` and `apps/*/.mcp.json` gitignored. `main` = truth again.
- **App icon** set to the Nirman logo via `flutter_launcher_icons` (config in
  `apps/mobile/pubspec.yaml`, source `apps/mobile/assets/icon/app_logo.png`). Re-run
  `dart run flutter_launcher_icons` after changing it (iOS gen is disabled — no appiconset).

## BMAD docs

- Canonical planning + story files live at the **workspace root**
  `../_bmad-output/` (one level above this repo, outside git), and are **synced into
  the committed copy `_bmad-output/`** here. Keep both in sync when you change one.
- Follow the BMAD flow for new work: `bmad-create-story` → `bmad-dev-story`.
- Story slugs are canonical in `epics.md`. (Note: Epic 3 has 9 stories, not 5.)

## Toolchain

- Flutter: `C:\Users\rpxi1\flutter\bin\flutter` (3.44 / Dart 3.12). After adding
  `@riverpod` providers run `dart run build_runner build --delete-conflicting-outputs`.
- **python is NOT on PATH** — the BMAD `resolve_customization.py` script fails;
  resolve `customize.toml` overrides manually (base → team → user).
- Keep `flutter analyze` at 0 errors; full mobile suite green before pushing.
