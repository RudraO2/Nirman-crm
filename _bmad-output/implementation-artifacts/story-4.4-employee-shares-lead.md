# Story 4.4 — Employee Shares a Lead with Another Employee

**Epic:** 4 — Admin Lead Management  
**Status:** in-progress  
**Created:** 2026-05-28  

---

## User Story

As an Employee, I want to share a specific Lead with another Employee while retaining ownership, so that we can collaborate on a high-value lead without transferring assignment.

---

## Acceptance Criteria

| ID | Criterion |
|----|-----------|
| AC-1 | Employee taps Share in lead detail → bottom sheet lists active employees (excluding self) |
| AC-2 | Tapping an employee calls `share_lead` RPC → `lead_shares` row inserted |
| AC-3 | Timeline records `shared` event with owner as actor |
| AC-4 | Recipient sees the Lead in their list (`get_my_leads`) with `is_shared = true` → "Shared" badge rendered |
| AC-5 | Any action by recipient logs timeline with recipient's `actor_id`; owner sees it in timeline |
| AC-6 | Owner detail screen shows "Shared with X, Y" chips; each chip has × to revoke |
| AC-7 | Tapping × calls `revoke_share` RPC → share row deleted, timeline records `share_revoked` |
| AC-8 | Lead immediately disappears from recipient's list on revoke (provider invalidated) |
| AC-9 | Cascade-revoke on reassign is already handled by `assign_lead` (0039) — do NOT re-implement |
| AC-10 | `share_lead` is idempotent — duplicate share is a no-op (ON CONFLICT DO NOTHING) |
| AC-11 | `revoke_share` is idempotent — no-op if row already absent |
| AC-12 | Employee cannot share a lead they don't own (RPC validates `assigned_to_user_id = auth.uid()`) |

---

## Technical Design

### Migration 0042 — `supabase/migrations/0042_share_lead_rpc.sql`

**RLS INSERT policy on `lead_shares`:**
- Name: `lead_shares_owner_insert`
- FOR INSERT TO authenticated
- WITH CHECK: `tenant_id = auth_tenant_id()` AND lead exists with `assigned_to_user_id = auth.uid()`

**RLS DELETE policy on `lead_shares`:**
- Name: `lead_shares_owner_delete`
- FOR DELETE TO authenticated
- USING: `granted_by_user_id = auth.uid()` OR caller has `role = 'admin'` in JWT

**`share_lead(p_lead_id uuid, p_recipient_user_id uuid) RETURNS void`:**
- SECURITY DEFINER; search_path = public, extensions
- Employee-only: role = 'employee'
- Validates: lead belongs to caller's tenant AND `assigned_to_user_id = auth.uid()`
- Validates: recipient exists, is_active=true, role='employee', same tenant, NOT caller
- INSERT INTO lead_shares ON CONFLICT DO NOTHING
- PERFORM log_timeline_event(p_lead_id, 'shared', jsonb payload with recipient_user_id + recipient_username)
- REVOKE/GRANT EXECUTE: revoke PUBLIC/anon, grant authenticated

**`revoke_share(p_lead_id uuid, p_recipient_user_id uuid) RETURNS void`:**
- SECURITY DEFINER; search_path = public, extensions
- Employee (owner only) OR admin
- Employee path: validates `assigned_to_user_id = auth.uid()`
- Admin path: validates lead belongs to caller's tenant
- DELETE FROM lead_shares WHERE lead_id + recipient_user_id (no error if absent)
- IF deleted: PERFORM log_timeline_event(p_lead_id, 'share_revoked', jsonb with recipient_user_id)
- REVOKE/GRANT EXECUTE: revoke PUBLIC/anon, grant authenticated

**`get_my_leads` (CREATE OR REPLACE):**
- Add `is_shared boolean` to RETURNS TABLE
- UNION ALL approach: owned leads (is_shared=false) UNION ALL shared leads WHERE recipient_user_id = auth.uid() (is_shared=true)
- Shared leads use same urgency scoring and all existing filters EXCEPT the ownership filter
- Deduplication: owned leads take precedence (shouldn't overlap but handle via UNION structure)

### Flutter — `apps/mobile/lib/features/leads/`

**`data/models/lead_model.dart`:**
- Add `isShared` field to `LeadListItem` (bool, default false)
- Update `fromJson` to read `j['is_shared'] as bool? ?? false`

**`data/lead_repository.dart`:**
- `shareLead(String leadId, String recipientUserId)` → calls `share_lead` RPC
- `revokeLead(String leadId, String recipientUserId)` → calls `revoke_share` RPC
- `getLeadShares(String leadId)` → SELECT from `lead_shares` table for owner view (filtered by lead_id, tenant RLS handles rest); returns List<LeadShareEntry>
- `listEmployeesForShare()` → reuses `list_employees_for_assignment` RPC (filter self in UI)

**`data/models/lead_model.dart` — add `LeadShareEntry`:**
```dart
class LeadShareEntry {
  final String id;
  final String recipientUserId;
  final String recipientUsername;
  final DateTime grantedAt;
}
```

**`providers/lead_providers.dart`:**
- `leadSharesProvider(String leadId)` → calls `repository.getLeadShares(leadId)`
- `employeesForShareProvider` → calls `repository.listEmployeesForShare()`

**`ui/share_lead_sheet.dart`** (new file):
- `showShareLeadSheet(context, leadId)` → modal bottom sheet
- Lists active employees (from `list_employees_for_assignment` RPC, filter out current user in Dart)
- Tapping employee → calls `shareLead`, shows snackbar, pops + invalidates `leadSharesProvider`

**`ui/lead_detail_screen.dart`** (modify):
- Add Share action button in quick-actions row (only for owned leads — `!lead.isShared`)
- Below quick-actions, for owned leads: render `leadSharesProvider` chips
  - Each chip: "username ×" — tap × calls `revokeLead`, invalidates providers
- Timeline already handles `shared`/`share_revoked` display (entries in `_eventDisplay`)

**`ui/lead_card.dart`** (modify):
- If `lead.isShared`: render "Shared" badge (same pattern as Stale/Pending outcome badges)

---

## Files Changed

| File | Change |
|------|--------|
| `supabase/migrations/0042_share_lead_rpc.sql` | New — RLS policies + share_lead + revoke_share + get_my_leads |
| `apps/mobile/lib/features/leads/data/models/lead_model.dart` | Modified — isShared field, LeadShareEntry |
| `apps/mobile/lib/features/leads/data/lead_repository.dart` | Modified — shareLead, revokeLead, getLeadShares, listEmployeesForShare |
| `apps/mobile/lib/features/leads/providers/lead_providers.dart` | Modified — leadSharesProvider, employeesForShareProvider |
| `apps/mobile/lib/features/leads/ui/share_lead_sheet.dart` | New |
| `apps/mobile/lib/features/leads/ui/lead_detail_screen.dart` | Modified — Share button, shares chips, revoke |
| `apps/mobile/lib/features/leads/ui/lead_card.dart` | Modified — Shared badge |

---

## Test / Verify Checklist

- [ ] RPC: `share_lead` as employee owner → lead_shares row exists, timeline `shared` event
- [ ] RPC: `share_lead` duplicate call → no error, no duplicate row (idempotent)
- [ ] RPC: `share_lead` as non-owner → `permission_denied`
- [ ] RPC: `revoke_share` as owner → row deleted, timeline `share_revoked` event
- [ ] RPC: `revoke_share` idempotent (row already gone) → no error
- [ ] RPC: `get_my_leads` as recipient → shared lead appears with `is_shared=true`
- [ ] RPC: `get_my_leads` as recipient after revoke → lead no longer in list
- [ ] UI: Share button visible on owned lead detail; hidden on shared lead detail
- [ ] UI: Bottom sheet lists employees (not self)
- [ ] UI: Chips show on owned detail; × revokes and chip disappears
- [ ] UI: Shared badge on lead card where `isShared=true`
- [ ] UI: Timeline shows `shared`/`share_revoked` events with correct labels
- [ ] flutter analyze: 0 errors

---

## Live Verification IDs

- Admin user: `e6973416-a4ee-46bf-b539-b779c79079b6`
- Employee (owner): `7e5a3253-429a-4e8c-beab-980e291ee1c6`
- Tenant: `00000000-0000-0000-0000-000000000001`
