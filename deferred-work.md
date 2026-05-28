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
