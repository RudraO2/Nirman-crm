# Deferred Work

## Deferred from: code review of 2-1-lead-schema-normalized-phone-encrypted-pii (2026-05-27)

- **normalize_phone: 0091 prefix not handled** — 14-digit string after stripping non-digits skips both guards; returns NULL; leads to NOT NULL constraint violation if Edge Function sends this format. Edge Function Zod must reject non-standard Indian prefixes.
- **TypeScript: bytea columns typed as `string`** — PostgREST returns `bytea` as `\\x`-prefixed hex string, not a plaintext string. Story 2.3 Edge Function must handle hex decoding before decryption calls.
- **TypeScript: budget `bigint` columns typed as `number`** — PostgREST returns Postgres bigint as JS string to avoid precision loss. Add explicit `parseInt`/`BigInt` in display/calculation layer (currency.ts). Safe for Indian real estate domain.
- **ip_address stored as `text` not `inet`** — Pre-existing in already-applied 0007 migration. Minor type improvement; swap to `inet` in a future migration if audit/search by IP range is needed.
- **auth_failed_attempts 'success' in outcome CHECK** — Table named `auth_failed_attempts` but logs successful logins too (for audit trail). Naming is a misnomer. Consider renaming to `auth_attempts` in future.
- **projects table missing `updated_at`** — Not required by Story 2.1 spec. Add `updated_at timestamptz NOT NULL DEFAULT now()` + trigger in a future migration if sync or cache invalidation logic needs it.
- **normalize_phone: non-91 country codes produce NULL** — Any non-Indian number → NULL phone_hash → NOT NULL constraint violation at DB. Edge Function Zod must validate Indian phone format (10 digits, optionally +91 prefix) before reaching DB. Acceptable for India-only product.

## Deferred from: code review of 2-2-lead-timeline-schema-write-helper (2026-05-27)

- **W-1: actor_role column has no length cap or allow-list** — spec defines as `text`; a malformed JWT could store arbitrary string. Add `CHECK (char_length(actor_role) <= 64)` or domain enum in a future migration.
- **W-2: Race condition when lead deleted between the two INSERTs in log_timeline_event** — domain_events generic bus; no FK to leads by design. Downstream consumers of domain_events must handle missing lead_id gracefully (e.g., log and skip).
- **W-3: timeline_event_type enum exhaustion** — 21 values now; `ALTER TYPE ... ADD VALUE` outside transactions is fine in Postgres 16 (used). If list grows significantly, consider a lookup table for extensibility without DDL churn.
- **W-4: Index coverage for tenant-level audit queries** — existing (lead_id, occurred_at DESC) composite index doesn't serve "all events for a tenant in last 24h" queries. Add covering index (tenant_id, occurred_at DESC) INCLUDE (lead_id) if audit dashboard feature is built.

## Deferred from: code review of 2-2-lead-timeline-schema-write-helper patches (2026-05-27)

- **Per-lead access control in log_timeline_event** — function checks lead belongs to caller's tenant but not that the calling user (auth.uid()) has row-level permission to write to that specific lead. Story 2.5 (visibility isolation) should revisit whether log_timeline_event needs an employee-assignment check.
- **TOCTOU lead deletion race** — lead could be deleted between the EXISTS check and the INSERT in log_timeline_event; FK ON DELETE CASCADE on lead_timeline handles it with a FK violation error. Acceptable race; no fix needed unless soft-delete pattern is added.
- **domain_events ON DELETE CASCADE vs RESTRICT** — lead_timeline uses RESTRICT (prevents tenant deletion if rows exist), domain_events uses CASCADE (rows deleted when tenant deleted). Inconsistency is intentional (domain_events = event bus, not owner). Revisit if compliance requires retaining event history post-tenant-deletion.
- **p_payload size bound in log_timeline_event** — no size cap on payload JSONB. Multi-megabyte payloads stored in both lead_timeline and domain_events. Edge Function Zod schema should enforce max payload size at API boundary.

## Deferred from: code review of 1-7-login-rate-limiting-and-lockout (2026-05-27)

- **No tenant_id filter in fail-count query** — `login/index.ts` count query for lockout trigger has no `.eq("tenant_id", SEED_TENANT_ID)`. V1 no-op (single tenant hardcoded), but inconsistent pattern; fix before multi-tenant.
- **x-forwarded-for IP is attacker-controllable** — leftmost IP taken without validation; attacker can spoof to attribute attempts to another IP. V1 audit-only, acceptable.
- **manage-employee unlock inserts duplicate user_events** — no idempotency check before inserting `account_unlocked` event; repeated unlocks on already-unlocked account pollutes audit log.

## Deferred from: code review of 1-2-bootstrap-initial-admin-account (2026-05-26)

- **Dual password storage credential sync** — `public.users.bcrypt_password_hash` and `auth.users` both store credentials. Story 1.4/1.5 must enforce sync on password change. Documented as intentional in Dev Notes.
- **validatePasswordStrength redundant with Zod** — min(8) enforced twice; cosmetic inconsistency, no behavior impact.
- **Race condition concurrent bootstrap calls** — two simultaneous calls can both pass idempotency check. Recommend `UNIQUE INDEX on public.users (tenant_id) WHERE role='admin'`. Low probability for one-time endpoint.
- **_shared/errors.ts duplication** — `bootstrap-admin/_shared/errors.ts` is a local copy due to MCP bundler limitation. Must stay in sync with canonical `functions/_shared/errors.ts`. Resolve when switching to Supabase CLI deploy.
- **Content-Type not validated** — `req.json()` parses any JSON regardless of Content-Type. Low risk for server-to-server endpoint.
- **No rate limiting** — bootstrap endpoint has no per-IP throttle or invocation counter. Acceptable for one-time bootstrap; disable after use.
- **No max body size** — large bodies buffered before Zod rejects. Low risk given Edge Function memory limits.
- **SEED_TENANT_ID existence not pre-checked** — FK violation if seed tenant missing. Documented dependency: seed.sql must run before bootstrap.
- **app_metadata role vs users.role drift** — both written at bootstrap; if one updated independently they diverge. Story 1.4/1.5 must treat one as canonical (recommend `auth.users.app_metadata` as JWT source of truth).
- **must_change_password=false** — spec AC-1 requires false for bootstrap admin. Story 1.5 may revisit for security hardening.

## Deferred from: Epic 3 close-out + deployment (2026-05-28)

### Outstanding manual config (user action required)

- **Vault `service_role_key` holds bad value** — user pasted `agZosG38eJP2E2oB` (16 chars) when correct value is the service_role JWT (~180 chars). pg_cron jobs `send-followup-notifications` + `process-overdue-followups` will fail authentication against Edge Functions until fixed. Fix via dashboard → Project Settings → Vault → edit `service_role_key` entry.
- **`FCM_SERVICE_ACCOUNT` Edge Function secret not set** — Firebase service account JSON (`crm-lms-57c5d-firebase-adminsdk-fbsvc-f119877e1b.json` in Downloads) must be uploaded via `supabase secrets set FCM_SERVICE_ACCOUNT=<minified-json> --project-ref vhgruadourflpxuzuxfn`. Without this, FCM sends in the cron functions will 500.

### Bugs found + fixed during E2E run

- **`auth_repository.dart` cast bug** — `response.data as Map<String, dynamic>` failed when supabase_flutter returned `Map<dynamic, dynamic>`. Replaced with `Map<String, dynamic>.from(...)` pattern (same fix already applied to `lead_repository._throwFromEdgeError`). Also in `changePassword`.
- **`auth_repository.recoverSession` rejected by supabase_flutter 2.10** — inline JSON missing required `user` field. Switched to `setSession(refreshToken)` API. Same change in `changePassword`.
- **`get_my_leads` and `get_lead_by_id` ambiguous `name` column** — RETURNS TABLE has column `name` which collides with `vault.decrypted_secrets.name` in SECURITY DEFINER context with `search_path = vault`. Fixed by aliasing the secrets table and qualifying `s.name = 'lead_pii_key'`.
- **`get_lead_by_id` missing `remarks`** — RPC didn't return remarks column; detail screen always showed empty remarks section. Added `remarks text` to RETURNS TABLE + selected `l.remarks` in body. Required `DROP FUNCTION` first because return type changed.
- **Budget unit mismatch** — DB stores paise (₹1 = 100 paise) per 0009 schema, but `new_lead_sheet` + `edit_lead_sheet` sent/displayed raw input as paise. Form now converts rupees ↔ paise on save + prefill.
- **Android click-to-call blocked** — Android 11+ package visibility filter rejected `tel:` intent without `<queries>` declaration. Added intent filters for `tel:` (DIAL) and `https://wa.me` (VIEW) in `AndroidManifest.xml`.
- **`public.users.id` ≠ `auth.users.id`** — initial seeded admin user had `public.users.id = gen_random_uuid()` not matching `auth.users.id`. `leads.assigned_to_user_id FK → public.users(id)` rejected inserts using `auth.uid()`. Fixed by re-inserting `public.users` row with `id` selected from `auth.users` where email matches. New seed/bootstrap scripts should INSERT with the auth.users id pinned.
- **JWT missing tenant_id claim** — auth.users row created via Supabase dashboard had no `raw_app_meta_data.tenant_id`, so `auth_tenant_id()` returned NULL → all RLS-scoped queries blocked. Manually updated via SQL. Future create-employee flow already sets this; only manual dashboard-created users are affected.

### Pubspec / SDK bumps

- `flutter_lints: ^4.0.0 → ^5.0.0`
- `build_runner: ^2.4.12 → ^2.4.13`
- `drift_dev: ^2.20.0 → ^2.22.0`
- `riverpod_generator: ^2.4.3 → ^2.6.3`
- `riverpod_lint: ^2.3.13 → ^2.6.3`
- `custom_lint: ^0.6.5 → ^0.7.0`
- `sdk: '>=3.4.0 <4.0.0' → '>=3.7.0 <4.0.0'` (required by test_api 0.7.11 pinned by Flutter 3.44)

### Toolchain installed (host = Windows 11)

- Flutter 3.44.0 (Dart 3.12.0) at `%USERPROFILE%\flutter\`
- Supabase CLI 2.101.0 via scoop
- Gradle 9.1.0-all.zip pre-staged at `%USERPROFILE%\.gradle\wrapper\dists\` (wrapper's HTTPS download kept timing out at 120s; BITS retry succeeded)

### Epic 4-7 status

Not started. ~42% of total scope remains. All four require web admin dashboard (no Flutter web shell scaffolded yet). Order of attack per epics.md:
- Epic 4 (Admin Control) — assignment, sharing, search, future pool
- Epic 5 (Builder Analytics) — 3-metric home, per-employee perf, funnel
- Epic 6 (Bulk Excel) — import w/ synonym matching, export + watermark + audit
- Epic 7 (Motivation Layer) — personal stats, sold celebration, streak push, monthly best

## Deferred from: code review of story-4.6-future-pool-and-project-match-trigger (2026-05-28)

- **D1 (ux): toggleAll clears entire selectedIds, not just filteredLeads subset** — theoretical; filter chip clicks cause full navigation (state reset), so cross-filter selection persistence doesn't occur. Fix if client-side filtering is added later.
- **D2 (security): error messages leak lead UUID in RAISE EXCEPTION** — `lead_not_found_or_not_future: <uuid>` and `employee_id_required for lead: <uuid>` surface UUID to client via Supabase RPC error payload. Refactor to use USING DETAIL or omit identifier from message in security hardening pass.
- **D3 (ux): assign_lead silently nulls assignment_deadline on reactivation** — `reactivate_future_leads` calls `assign_lead(lead_id, employee_id, NULL)` which unconditionally sets `assignment_deadline = NULL`. Future leads are not expected to carry deadlines, but undocumented. Add comment or guard if convention changes.
- **D4 (ux): column header "Days in Future" vs spec "days since marked Future"** — minor wording deviation. Change to "Days in Pool" or "Days since Future" in a UX polish pass.
- **D5 (ux): matchCount URL param shown in banner without server re-verification** — banner displays URL-injected count, which becomes stale if leads are reactivated by another session before the user acts. After reactivation, banner is dismissed (fixed). Stale count on page load is acceptable for V1.
- **D6 (pre-existing): list_assignable_leads backslash escape uses non-standard PG string syntax** — `replace(v_q, '\', '\\')` relies on `standard_conforming_strings=off` behavior. Works in practice but fragile. Refactor to `E'\\'` or dollar-quoting in future migration.
- **D7 (pre-existing): phone_encrypted null guard missing** — `list_assignable_leads` calls `pgp_sym_decrypt(l.phone_encrypted, v_pii_key)` without IS NOT NULL guard (unlike name_encrypted). Returns NULL phone_last4 silently for any row with NULL phone_encrypted. Pre-existing since 0038; fix in a future patch migration.

## Deferred from: code review of 1-1-initialize-multi-tenant-schema-with-rls (2026-05-26)

- 0001→0002 deployment window: security gap exists between the two migration files being applied sequentially. Any user who authenticates after 0001 but before 0002 lands operates under permissive old policies and can call `set_current_tenant` as authenticated. Mitigate via atomic deployment practice (disable external access / Supabase pause during migration run) — not a code-level fix.

## Deferred from: code review of 4-3-admin-global-search (2026-05-28)

- **D1 (perf): name search decrypts all rows in tenant** — `search_leads_global` name branch calls `pgp_sym_decrypt` for every `name_encrypted` row, then applies ILIKE. For tenants with 50k leads this is the theoretical worst case. No index is possible on encrypted data. Mitigation path: add a deterministic-hash prefix column (`name_prefix_hash`) truncated at N chars, index it, and use it to pre-filter before full decrypt. Not blocking for V1.
- **D2 (ux): stale employee list if employee added/deactivated mid-session** — `GlobalSearch` caches `employees` after first overlay open; re-fetches only on full page reload. If an employee is deactivated between overlay open and assign, `AssignDialog` will show them; server-side `assign_lead` will return `target_not_assignable`. Error surfaced to user. Mitigation: re-fetch `list_employees_for_assignment` on every assign dialog open.
- **D3 (ux): no loading indicator on Assign button inside search results** — clicking "Assign" closes the overlay and opens `AssignDialog` immediately (no async before that), but if the employee list hasn't loaded yet the dialog's picker will be empty. A micro-spinner on the Assign button guarded by `employees.length === 0` would signal "loading employees…".

## Deferred from: code review of 4-2-bulk-assign-leads (2026-05-28)

- **D1 (ux): no loading state on "Preview Distribution" button** — `handleAdvance` awaits `get_employee_active_lead_counts` RPC before setting step. If network is slow, the button gives no feedback for the duration of the request. Add a `advancing` boolean state + spinner on the advance button.
- **D2 (security): send-bulk-assignment-notification shares same verify_jwt=false exposure as D2 from 4.1** — same mitigation note applies; harden with caller role check in edge fn before V2.
- **D3 (ux): keyboard navigation in Manual DnD canvas** — @dnd-kit/core supports accessibility via keyboard sensors; not enabled in current impl. Wire up `KeyboardSensor` + `screenReaderInstructions` before shipping to users with accessibility requirements.

## Deferred from: code review of 4-4-employee-shares-lead (2026-05-28)

- **D1 (ux): generic error message** — `share_lead_sheet._onTap` catch swallows all RPC error codes into "Could not share lead. Try again." Distinct codes (`cannot_share_with_self`, `recipient_not_eligible`) should map to human-readable variants. Schedule as UX polish pass.
- **D2 (ux): revoke_share timeline payload omits revoker username** — logs only `revoked_by` (UUID), not username. Consistent reads require a JOIN at display time; add `revoked_by_username` to payload if timeline display needs it later.
- **D3 (product): archived-lead visibility for recipients** — when owner archives (dead/sold/future) a shared lead, recipient silently loses sight of it (get_my_leads and get_my_archived_leads both exclude it). Confirm whether recipients should see archived shared leads; track as product backlog for Epic 4 or 4.5.
- **D4 (minor): share_lead returns void — no "already shared" signal** — idempotent no-op is silent; UI invalidates providers on every call regardless. If UX needs to distinguish "new share" vs "already shared," change return type to boolean.
- **D5 (minor): no client-side UUID format validation before RPC call** — malformed leadId caught by server-side Postgres cast error; catch block handles gracefully. Low risk.

## Deferred from: code review of 4-5-lead-reassignment-blocks-deactivation (2026-05-28)

- **D1 (ux): single-employee tenant blocks modal** — if the employee being deactivated is the only employee, `list_employees_for_assignment()` returns 1 record which is then filtered out (can't self-assign). Pickers show "No employee found." and button stays disabled. Add a hint: "No other active employees. Create another employee before deactivating this one." Guard in dialog when `employees.length === 0` after the filter.
- **D2 (ux): stale employee list in dialog** — `list_employees_for_assignment()` is fetched once on dialog open. If an employee is deactivated while the dialog is open, they still appear in pickers; server-side `assign_lead` returns `target_not_assignable`. Same mitigation pattern as 4.3/D2: re-fetch on submit if any `target_not_assignable` error is returned, then show "Employee no longer active. Please re-select."
- **D3 (minor): no AbortController on in-flight fetches in dialog** — `Promise.all([list_assignable_leads, list_employees_for_assignment])` not cancelled on dialog close. Stale state updates are invisible (dialog hidden) but React may warn on unmounted components in future. Wrap in `useEffect` cleanup with an `aborted` flag or `AbortController`.
- **D4 (minor): client-side status filter in dialog is redundant** — `deactivation-blocked-dialog.tsx` filters `!['dead','sold','future']` client-side after `list_assignable_leads` returns. The RPC already excludes archived leads when `p_include_archived=false` (default). Remove the client-side filter in a future cleanup pass.
- **D5 (reliability): "not_found" catch in updateLead is broad** — `LeadReassignedError` is thrown for any `"not_found"` from `update-lead`. In practice this only occurs when ownership check fails (i.e., reassignment). If future update-lead versions return `"not_found"` for other reasons (e.g., project not found), the catch would surface a misleading snackbar. Tighten by adding a distinguishing error code (e.g., `"lead_not_owned"`) to the update-lead edge function.

## Deferred from: code review of 4-1-admin-assigns-single-lead-to-employee (2026-05-28)

- **D1 (perf): list_assignable_leads decrypts every row's PII before filtering** — Same class as 2.8/D11. For tenants with >5k leads + a search query, the base CTE decrypts every lead before the ILIKE filter. Optimise via partial indexing on `(tenant_id, status)` + push the search down into a SQL function that scans the index, decrypts only the matching window, then filters. Not blocking for V1 (≤50k leads/org budget).
- **D2 (security): send-assignment-notification edge fn accepts any Bearer** — `verify_jwt=false` lets the gateway through any caller with the publishable key. The fn currently only checks `Authorization: Bearer …` is present, not the role of the caller. An employee with publishable-key access could craft a request to push a fake "New lead assigned" to any user. Mitigation: V1 UI exposes the trigger only inside `/leads` (admin-gated route). Hardening path: forward the user JWT through the edge fn and call `supabase.rpc('check_is_admin')` from inside the fn before fanning out.
- **D3 (test infra): no Playwright / E2E suite in apps/admin** — `pnpm --filter admin lint` + `npm run -w admin build` are the only automated gates. A dedicated `apps/admin/tests/` scaffold + a single happy-path E2E for the Assign flow would catch UI regressions in subsequent Epic-4 stories (4.2 bulk-assign, 4.3 search, 4.6 Future Pool).
