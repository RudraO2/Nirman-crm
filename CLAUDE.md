# Nirman CRM — Agent Operating Guide

**Read this before touching git, Supabase, or migrations. It records work already
done so a fresh session does not redo or break it.** Last updated: 2026-05-28.

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

- Migrations are **file-based**, `supabase/migrations/0001…0030`, applied with
  **`supabase db push --linked`** (CLI 2.101, already `link`ed).
- **NEVER use the MCP `apply_migration` tool** — it creates timestamp-named entries
  that desync the migration history (this already had to be repaired once). Always
  add the next numbered file (after `0030`) and `db push`.
- Before adding a migration run `supabase migration list` to confirm state.
- Inline hotfixes 0027/0028 were applied via SQL editor and also exist as files.

## 🔒 Push notifications (Epic 3.5/3.6/3.7) — DONE + verified, DO NOT redo

- `FCM_SERVICE_ACCOUNT` edge secret **is set** (Firebase project `crm-lms-57c5d`).
- `process-overdue-followups` + `send-followup-notifications` edge fns deployed.
- pg_cron jobs **scheduled + active** (every 1 min / 5 min). pg_cron + pg_net enabled.
- **vault `service_role_key` is NOT needed** — both notification fns are
  `verify_jwt=false`, so the cron's gateway call works without it. Do not chase it.
- `SUPABASE_SERVICE_ROLE_KEY` env is platform-injected; do not set it.
- Verified live 2026-05-28: invoking the fn returned `{"sent":1}` (FCM accepted token).
- **There is no outstanding manual Supabase/Firebase config.**

## Auth gotcha (don't regress)

- Mobile login uses `supabase.auth.setSession(refreshToken)` — NOT `recoverSession`
  (recoverSession threw `FormatException: Expected user to be an object, got Null`
  on device). Keep `setSession`.
- `public.users.id` must equal the matching `auth.users.id` (FK target for
  `leads.assigned_to_user_id`). JWT carries `app_metadata.tenant_id` + `role`.

## Current status (truth — see `_bmad-output/implementation-artifacts/sprint-status.yaml`)

- **Epic 1 (1.1–1.8): done** · **Epic 2 (2.1–2.7): done** · **Epic 3 (3.1–3.9): done**
- **Epic 7.1: review** (Personal stats card; migration 0030 + `features/motivation/`)
- Remaining: Epic 7.2–7.4 (mobile, no blocker) → then Epic 4–6 (need `apps/admin` Next.js)

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
