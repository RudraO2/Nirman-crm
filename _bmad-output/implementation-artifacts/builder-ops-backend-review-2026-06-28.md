# Builder-ops backend review — 2026-06-28

Adversarial review + thorough runtime testing of Epics 12-16 (migrations 0057-0084) on the free local
Docker stack. Goal: a robust, verified backend foundation before any UI work.

## Security audit (DB introspection — all PASS)
- **RLS:** all 9 new tables (`agencies, agency_projects, towers, units, developer_updates, unit_holds,
  amendments, amendment_events, tenant_execution_team`) have `ENABLE` + `FORCE` row-level security.
- **anon:** every sensitive new RPC denies `anon` EXECUTE. (`auth_role_tier` / `get_developer_updates`
  are intentionally SECURITY INVOKER and safe.)
- **search_path:** pinned on every new SECURITY DEFINER function (no mutable-search-path hijack).
- **Append-only:** `amendment_events` denies UPDATE/DELETE to authenticated (hard error).
- Cross-tenant probes: SECURITY DEFINER reads/writes all filter tenant explicitly → other-tenant access
  rejected (`project_not_found`, etc.).

## Bugs found + fixed (migration 0084, roll-forward, same signatures)
1. **🔴 Orphan hold (correctness).** `change_unit_inventory_state('force_release')` of a *held* unit set
   the unit to `available` but left the `unit_holds` row active → unit looked available yet could not be
   re-held (partial-unique still occupied → `unit_unavailable`); only self-healed when the cron later
   expired it. **Fix:** force_release now also releases the active hold (`outcome='cancelled'`). Verified:
   active_holds=0 after force_release, re-hold succeeds.
2. **🟠 Partner sandbox leak.** `hold_unit` let a `partner_agency` hold a unit in a project NOT shared to
   their agency (inconsistent with the 14.3 read scoping). **Fix:** partner holds gated to agency-shared
   projects (`project_not_shared`).
3. **🟠 Amendment mis-attribution.** `log_amendment` allowed an amendment for a (visible) lead not linked
   to the unit. **Fix:** the lead must have an active hold OR a confirmed booking on the unit
   (`lead_not_linked_to_unit`). Sold-unit amendments for the booked lead still work.

## Coverage added
- **Epic 12 live tests** (were static-only before the test harness existed): `auth_role_tier`
  fallback/override; `set_user_hierarchy` partner-needs-agency / cycle / tier-rank / admin-only;
  tier-aware `assign_lead` (front_line_rep targets only); assignable list rep-only. All pass.
- **Full cross-epic integration lifecycle** (register→verify→hold→confirm→sold→amend→execute→done) +
  expire path (hold→expire→release→re-hold). End-to-end audit trail asserted. Pass.
- **Real two-connection CAS race** for `hold_unit` — exactly one winner, loser clean `unit_unavailable`.
- **Durable pgTAP suite** `supabase/tests/builder_ops_invariants.test.sql` (15 assertions) — `supabase
  test db` → 23/23 pass (with existing tenant-isolation). Behavioral scripts saved under
  `supabase/tests/manual/`.

## Verdict
Backend logic is **robust and verified** (84 migrations apply clean from scratch; security invariants
hold; lifecycles compose; 3 real bugs fixed). Still backend-only — UI + prod deploy are the next phase.
Migrations now 0057-0084 (28 files). Sprint stories 12-16 remain at `review`.
