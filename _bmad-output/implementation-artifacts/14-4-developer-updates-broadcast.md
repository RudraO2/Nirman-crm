# Story 14.4: developer-updates broadcast channel

Status: review  (migration 0073 + edge fn written + smoke ALL PASS 2026-06-28; FCM deploy + feed UI deferred)

## Implementation (2026-06-28)

**Reality correction:** story referenced a `pending_notifications` table/dispatcher — no such table exists. Real infra = per-event edge fns pushing FCM to `device_tokens`. Followed that pattern.

**File:** `nirman-crm/supabase/migrations/0073_developer_updates.sql`
- `dev_update_type` enum (construction, pricing, inventory, announcement); `developer_updates` table (project_id nullable = tenant-wide, `shareable_to_partners` default FALSE, posted_by). RLS ENABLE+FORCE.
- **SELECT RLS policy** scopes partners to shareable + agency-shared (0072) rows only → privacy at rest. No direct write grant.
- `post_developer_update(type, body, project?, shareable?)` head-only → insert + emit `domain_events('developer_update_posted')`. Returns id.
- `get_developer_updates(project?, limit, offset)` **SECURITY INVOKER** feed (RLS does the partner filtering automatically), newest-first, attributed.
- `get_developer_update_audience(update_id)` SECURITY DEFINER (service_role) → recipient user_ids: internal team always; partner_agency only if shareable + agency-shared. Powers the FCM fan-out.

**File:** `nirman-crm/supabase/functions/send-developer-update/index.ts` (NEW) — mirrors send-assignment-notification: service-role, resolves audience via RPC, fans out FCM to device_tokens, deletes stale tokens, emits `notification_sent`. Body `{update_id}`.

**Tested (local runtime):** 2 posts → 2 domain_events; private-update audience excludes partner (internal-only); shareable-update audience includes partner; non-head denied; internal feed=2, partner feed=1 (only shareable, via RLS).

**Deferred:** `supabase functions deploy send-developer-update --no-verify-jwt` + admin server-action invoke after post; mobile/admin Updates feed UI.

## Story

As a Builder Head,
I want to post construction/pricing/inventory updates that reach my sales teams,
so that the field always has current information.

## Acceptance Criteria

1. **Given** migration `0060_developer_updates.sql` (`developer_updates`, `dev_update_type` enum, `shareable_to_partners` default false) **When** I (head only) post an update with type, body, optional project scope **Then** the row is inserted AND an FCM notification is enqueued via the existing `pending_notifications` + dispatcher to the project's sales team.
2. **And** external partner teams receive only updates with `shareable_to_partners = true` (opt-in, default off).
3. **And** an in-app "Updates" feed shows posts newest-first, RLS-scoped, attributed to the poster.
4. **And** only `builder_head` may post.

## Tasks / Subtasks

- [ ] **Task 1 — Migration `0060`**: `CREATE TYPE dev_update_type (construction,pricing,inventory,announcement)`; `CREATE TABLE developer_updates(id, tenant_id, project_id nullable, update_type, body, shareable_to_partners bool default false, posted_by, created_at)` + RLS+FORCE + tenant policy.
- [ ] **Task 2 — `post_developer_update` RPC** (head-only): insert row; enqueue `pending_notifications` rows for the target sales team (project members / tenant); for partners, include only if `shareable_to_partners`.
- [ ] **Task 3 — In-app feed**: RLS-scoped SELECT newest-first; Realtime optional. Mobile + admin.
- [ ] **Task 4 — Tests**: head posts → team notified; partner excluded unless shareable; non-head denied.

## Dev Notes

- Reuse `pending_notifications` + dispatcher (Decision 13 / Epic 3.6) — new producer, no new transport. [Source: 3-6 story; architecture-builder-ops-v2.md §3.2]
- Opt-in partner share default OFF. [Source: §3.2 decided, Q5]
- One-way (no reply thread) in V2.

## References
- [Source: epics.md#Story 14.4; architecture-builder-ops-v2.md §3.2]
- [Source: 0007/pending_notifications, supabase/functions/notification-dispatcher / send-followup-notifications]
