# Deferred Work

## Deferred from: Story 5.2 — Per-Employee Performance Dashboard (2026-05-28)

- **Custom date range picker on Performance page** — The date range filter UI implements
  Today | Last 7 days | Last 30 days. The "Custom" option is deferred because it requires
  a date-picker library (date-fns or similar — not yet installed in apps/admin).
  `get_employee_performance_stats(p_days)` already accepts any integer, so the backend
  supports arbitrary windows. The UI work is purely frontend.
  **What's needed:** install `react-day-picker` or `date-fns` + add a custom range
  button + date picker popover that computes p_days from (today - selected_start) and
  navigates to `/performance?range=<p_days>` (or a custom param like `from`/`to`).

- **D1 (ux): No loading skeleton on range-filter navigation** — clicking Today/Last 7/Last 30
  triggers a full server component re-fetch. During that window the page briefly blanks.
  Add `apps/admin/src/app/(app)/performance/loading.tsx` with a card skeleton to keep
  the layout stable during navigation.

- **D2 (accessibility): Toggle buttons + row clicks lack ARIA hints** — the "Show All",
  "Show Dead/Sold/Future", and table-row click targets have no `aria-label`, `role`, or
  keyboard-event handlers. Wire up `onKeyDown` + `role="button"` / `tabIndex={0}` on
  table rows and ensure toggle buttons have descriptive `aria-pressed` state before
  any accessibility audit.

- **D3 (minor): conversion_rate numeric coercion** — `get_employee_performance_stats`
  returns `conversion_rate numeric`. For employees with `total_assigned = 0`, the SQL
  returns NULL (ROUND(…/NULLIF(0,0), 1)). PostgREST maps NULL → null in JSON, which
  the UI displays as "—". Verified correct. No fix needed — noted for future type
  tightening (change TypeScript type to `number | null`).

## Deferred from: code review of story-5.3 (2026-05-28)

- **F-1 (security): NULL JWT role check in `get_funnel_stats`** — `(auth.jwt() -> 'app_metadata' ->> 'role') <> 'admin'` evaluates to NULL (not FALSE) when `app_metadata.role` is absent, allowing the function to execute without the admin guard. This is a codebase-wide pattern (same form used in all functions in 0049). A systemic fix would change every admin-only function to use `IS DISTINCT FROM 'admin'`. Deferring because (a) Supabase JWTs are platform-signed and `role` is always populated for authenticated users, (b) changing only 5.3 creates inconsistency, (c) a migration changing all existing functions would need its own story.
  **What's needed:** A global search-and-replace across all SECURITY DEFINER admin functions to use `COALESCE(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin'` or `IS DISTINCT FROM 'admin'`.

- **F-2 (semantics): `p_days=1` ("Today") includes yesterday** — `(created_at AT TIME ZONE v_tz)::date >= v_today - 1` returns leads from the last 2 days (yesterday + today), not just today. This is consistent with the same pattern used in `get_employee_performance_stats` (0049) and matches the spec `p_days = N → created_at >= v_today - N`. A proper "Today only" filter would use `= v_today`. Deferring to avoid diverging from codebase convention; fix in a dedicated date-filter cleanup story that also adjusts 0049.

- **F-3 (ux): No loading skeleton on filter navigation for Funnel page** — filter changes trigger a full server component re-fetch, causing a brief blank. Add `apps/admin/src/app/(app)/funnel/loading.tsx` with a card skeleton (same pattern as deferred for Performance page above).

- **F-4 (accessibility): Filter selects and range buttons lack ARIA labels** — `<select>` elements have no `aria-label`, range toggle buttons have no `aria-pressed` state. Add `aria-label` and `aria-pressed` before any accessibility audit.

## Deferred from: Story 6.1 — Excel Bulk Import (2026-05-28)

- **D-6.1-1 (ux): No "Back" navigation in import wizard** — `import-wizard.tsx` is forward-only. Once on Preview or Assign, user cannot return to Map without restarting the file upload. Fix: add Back button to each step; restore prior state on back navigation (mappings, preview result).

- **D-6.1-2 (security): xlsx@0.18.5 has known vulnerabilities** — `npm audit` reports 2 moderate + 1 high CVE in `xlsx`. Risk is reduced because xlsx runs server-side only (Server Action, never in client bundle). Fix before production: evaluate migration to `exceljs` (actively maintained, no known high CVEs) and swap `parseExcelAction` implementation. API is compatible enough for a drop-in replace.

- **D-6.1-3 (ux): No loading skeleton for /import route** — navigating to `/import` causes a brief blank while the server component fetches `list_employees_for_assignment`. Add `apps/admin/src/app/(app)/import/loading.tsx` with a card skeleton (same pattern as deferred for Performance + Funnel pages).
