# Story 4.3 — Admin Global Search by Name and Phone

**Epic:** 4 — Admin Lead Management  
**Status:** in-progress  
**Created:** 2026-05-28  

---

## User Story

As an Admin, I want to search across all Leads in my tenant by name or phone number, so that I can find a specific Lead in under 3 seconds.

---

## Acceptance Criteria

| ID | Criterion |
|----|-----------|
| AC-1 | Global search bar accessible from any page in the admin UI (in the sticky header, not the leads-page toolbar). |
| AC-2 | `⌘K` / `Ctrl+K` opens the search overlay from anywhere. |
| AC-3 | Searches ALL leads in the tenant including Archived (no status filter). |
| AC-4 | Phone input: `normalize_phone(p_q)` → sha256 hash → match `phone_hash` (O(1) index lookup). |
| AC-5 | Name input: server-side `pgp_sym_decrypt` + `ILIKE`, limit 50 results. |
| AC-6 | Results render within 1.5 seconds for a tenant with up to 50,000 leads. |
| AC-7 | Employee calling the search endpoint receives HTTP 403 / `permission_denied`. |
| AC-8 | Results display: `StatusPill`, decrypted name, `•••phone_last4`, assignee username, quick Assign button. |
| AC-9 | Search is debounced 300 ms; no request fires on empty input. |
| AC-10 | Keyboard navigable — cmdk handles arrow/enter natively; Escape closes overlay. |

---

## Technical Design

### New RPC: `search_leads_global(p_q text, p_limit int DEFAULT 50)`

- **Migration:** `supabase/migrations/0041_search_leads_global.sql`
- **Pattern:** SECURITY DEFINER, `search_path = public, extensions, vault`
- **Auth gate:** `v_actor_role <> 'admin'` → ERRCODE `42501`
- **Exclusive branching:**
  - `normalize_phone(p_q)` returns non-null → phone-hash branch (O(1), no full-table decrypt)
  - else → name ILIKE branch (decrypt all rows, LIMIT p_limit)
- **Returns:** `id uuid, name text, phone_last4 text, status text, assigned_to_user_id uuid, assignee_username text`
- **No total_count** — global search always returns at most p_limit rows; no pagination needed.

### New UI Component: `apps/admin/src/components/global-search.tsx`

- Client component
- `⌘K` / `Ctrl+K` toggles overlay (document `keydown` listener in `useEffect`)
- `CommandDialog` + `Command shouldFilter={false}` + `CommandInput` + `CommandList`
- Debounced 300 ms via `useRef<ReturnType<typeof setTimeout>>`
- Calls `supabase.rpc('search_leads_global', { p_q })` from browser client
- Employees fetched lazily on first overlay open via `list_employees_for_assignment`
- "Assign" button closes overlay, stores `assignTarget` state, opens `AssignDialog` with `initialOpen`

### Modified: `apps/admin/src/app/(app)/layout.tsx`

- Import and render `<GlobalSearch />` in the sticky header (right of nav, left of email).

### Modified: `apps/admin/src/components/leads/assign-dialog.tsx`

- Add `initialOpen?: boolean` and `onClose?: () => void` props for controlled/headless mode.
- When `initialOpen=true`, suppress the trigger `<Button>` (the caller manages opening).

---

## Files Changed

| File | Change |
|------|--------|
| `supabase/migrations/0041_search_leads_global.sql` | New |
| `apps/admin/src/components/global-search.tsx` | New |
| `apps/admin/src/app/(app)/layout.tsx` | Modified — add `<GlobalSearch />` |
| `apps/admin/src/components/leads/assign-dialog.tsx` | Modified — `initialOpen` + `onClose` |

---

## Test / Verify Checklist

- [ ] RPC: admin call with phone input → returns matching lead(s)
- [ ] RPC: admin call with name input → returns up to 50 matching leads
- [ ] RPC: employee call → `permission_denied` (42501)
- [ ] RPC: archived lead appears in results
- [ ] UI: `⌘K` opens overlay from `/leads` and `/team` pages
- [ ] UI: typing phone number → results appear within 1.5 s
- [ ] UI: typing name → results appear within 1.5 s (for test dataset)
- [ ] UI: Assign button → closes overlay, opens AssignDialog, router.refresh() on success
- [ ] UI: empty input → no RPC call fired
- [ ] UI: Escape closes overlay

---

## Live Verification IDs

- Admin user: `e6973416-a4ee-46bf-b539-b779c79079b6`
- Employee user: `7e5a3253-429a-4e8c-beab-980e291ee1c6`
- Tenant: `00000000-0000-0000-0000-000000000001`
