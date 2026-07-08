# Builder-ops (Epics 12-16) tests

## Automated (pgTAP) — runs in CI
`../tests/builder_ops_invariants.test.sql` — structural + privilege guardrails (FORCE RLS on all new
tables, enum shapes, single-active-hold index, amendment_events append-only, anon denied on sensitive
RPCs, search_path pinned). Run with:

```
supabase test db
```

## Manual behavioral scripts — run against the local stack
These use `set_config('request.jwt.claims', …)` to simulate authenticated roles and exercise the
full RPC flows. Each is wrapped in `BEGIN … ROLLBACK` (no residue). Run with:

```
docker exec -i supabase_db_supabase psql -U postgres -d postgres -q < supabase/manual-tests/<file>.sql
```

- `builder_ops_lifecycle.sql` — full cross-epic happy path: register (customer code) → reception
  verify visit → hold (CAS) → confirm booking (→sold, celebration seam) → log amendment → execution
  team walks status to done; plus the hold→expire→release→re-hold path. Asserts the audit trail.
- `builder_ops_adversarial.sql` — edge probes incl. the three bugs fixed in migration `0084`
  (force_release orphan hold, partner hold in non-shared project, amendment lead-not-linked) and
  cross-tenant isolation.
- `epic12_hierarchy_assignment.sql` — role_tier fallback/override, set_user_hierarchy
  (partner-needs-agency, cycle/tier-rank reject, admin-only), tier-aware assign_lead.

A real two-connection concurrency race for `hold_unit` (exactly one winner) is documented in story
`15-2`; it requires two parallel psql connections against committed setup (see that story's notes).

Prereq: `supabase start` (Docker) + the local `lead_pii_key` vault secret from `seed.sql`.
Note: `00075_local_seed_tenant.sql` is a LOCAL-ONLY shim — delete before any prod `db push`.
