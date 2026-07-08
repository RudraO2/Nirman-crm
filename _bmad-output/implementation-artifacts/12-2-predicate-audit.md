# Story 12.2 — role-vs-tier predicate audit

Classification of every shipped `role` check after introducing `role_tier`. Source: live defs
re-created in `0054_harden_admin_role_guards.sql` (+ `0055` share_lead). Class meanings:
- **is-admin** — guard means "caller must be the tenant admin". `builder_head` maps to `role='admin'` → **meaning unchanged**, no edit.
- **is-not-admin** — guard means "caller is a normal worker (non-admin)". Leaders/reps/partners all stay `role='employee'` → **meaning unchanged**, no edit.
- **is-rank-and-file-IC** — guard's intent was specifically "an individual contributor", where a leader being included would be wrong → **needs a tier-aware predicate**.

| Function | Guard | Class | Action |
|----------|-------|-------|--------|
| assign_lead (caller) | `role IS DISTINCT FROM 'admin'` | is-admin | unchanged |
| assign_lead (**target**) | `v_target.role <> 'employee'` | **is-rank-and-file-IC** | **FIX → require `role_tier='front_line_rep'`** |
| bulk_assign_leads | `role IS DISTINCT FROM 'admin'` | is-admin | unchanged (delegates to assign_lead) |
| get_builder_home_metrics | inline `IS DISTINCT FROM 'admin'` | is-admin | unchanged |
| get_employee_active_lead_count(s) | `IS DISTINCT FROM 'admin'` | is-admin | unchanged |
| get_employee_activity_stats | inline admin | is-admin | unchanged |
| get_employee_performance_stats | inline admin | is-admin | unchanged |
| get_funnel_stats | inline admin | is-admin | unchanged (13.7 edits body for visit_count, not guard) |
| get_future_pool_match_count | `IS DISTINCT FROM 'admin'` | is-admin | unchanged |
| get_lead_status_distribution | inline admin | is-admin | unchanged |
| get_pipeline_activity_14d | inline admin | is-admin | unchanged |
| list_assignable_leads | `IS DISTINCT FROM 'admin'` | is-admin | unchanged |
| **list_employees_for_assignment** | `IS DISTINCT FROM 'admin'` (caller) + returns `role='employee'` | **is-rank-and-file-IC** (the returned set) | **FIX → `AND role_tier='front_line_rep'`** |
| reactivate_future_leads | `IS DISTINCT FROM 'admin'` | is-admin | unchanged |
| search_leads_global | `IS DISTINCT FROM 'admin'` | is-admin | unchanged |
| get_lead_name_for_notification | `NOT IN ('admin','service_role')` | is-admin-or-service | unchanged |
| list_employees_for_share | caller `NOT IN ('employee','admin')`; returns `role='employee'` | is-not-admin (caller) / **borderline** (returned set now includes leaders/partners/receptionists) | **DEFER** — sharing targets should arguably exclude receptionist/partner; low-risk, flagged below |
| share_lead (0055) | `role IS DISTINCT FROM 'employee'` | is-not-admin | unchanged (any employee-tier may share) |
| revoke_share | positive `='employee'`/`='admin'` + ELSE deny | is-not-admin/admin | unchanged |
| get_my_leads, get_lead_by_id, edit/status/visit RPCs | ownership `assigned_to_user_id = auth.uid()` | (ownership, not role) | unchanged; receptionist denied separately in 12.6 |

**Fix set (this story):** `assign_lead` target filter + `list_employees_for_assignment` returned set → `role_tier='front_line_rep'`.

**Deferred / flagged:** `list_employees_for_share` returns all `role='employee'` users as share candidates, which now includes leaders/partners/receptionists. Sharing a lead with a receptionist or partner is nonsensical but not a security hole (share grants read of one lead). Recommend a follow-up filter `role_tier IN ('front_line_rep','team_leader')` — logged to `deferred-work.md`, not blocking.

**Claim-window note:** the target/returned-set filters read `public.users.role_tier` (DB column), NOT the JWT claim — so they are correct immediately, independent of the 12.3 stamping window. The stamping window only affects the *caller's* `auth_role_tier()` derivation, which for these admin-gated RPCs still resolves correctly (`builder_head` ⇐ `role='admin'`).
