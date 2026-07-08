# Story 13.3: generate customer code and deliver via free channel

Status: review  (migration 0065 + edge fn written + self-reviewed; mobile UI + apply deferred)

## Story

As an employee,
I want a unique customer code generated and sent to the lead at no cost,
so that the lead can present it at reception to verify a visit.

## Acceptance Criteria

1. **Given** lead registration **When** the lead is created **Then** a tenant-unique `customer_code` (short, human-readable, e.g. `NIR-7F3K`) is generated with collision-retry against `leads_tenant_customer_code_idx`.
2. **And** the code is shown on the lead card for the agent to read out.
3. **And** a `code_delivery` adapter sends it free — default builds a `wa.me` link (reuses Epic 3 WhatsApp seam); SMS is a pluggable paid adapter, OFF by default.
4. **And** a `code_generated` event is appended to the lead Timeline (new `timeline_event_type` value).
5. **And** no paid-SMS dependency exists in the free tier.

## Tasks / Subtasks

- [ ] **Task 1 — Code gen in `create_lead_with_pii`**: generate base32-ish short code with tenant prefix; on `unique_violation` against `leads_tenant_customer_code_idx`, retry (≤5). Set `customer_code`.
- [ ] **Task 2 — `timeline_event_type` enum**: add `code_generated` (+ later `visit_verified`, `visit_logged`, `lead_reclaimed`, `unit_held`, `hold_expired`, `unit_booked`) — do the enum `ADD VALUE`s in one dedicated migration step to avoid scatter. Log via `log_timeline_event`.
- [ ] **Task 3 — `code_delivery` adapter**: interface `send(code, phone)`; default impl returns a `wa.me/{phone}?text=...code...` link (reuse `whatsapp-render`/Epic 3.4 seam). SMS adapter stubbed + disabled.
- [ ] **Task 4 — Mobile**: lead card shows `customer_code`; a "Send code via WhatsApp" action opens the wa.me link. `flutter analyze` 0.

## Dev Notes

- Reuse the existing WhatsApp deep-link seam (Epic 3.4 `whatsapp_repository` / `whatsapp-render`). No Meta API. [Source: 3-4 story; architecture.md Decision 7 WhatsApp seam]
- SMS deferred — adapter pattern keeps MSG91 swap to one edge fn later. [Source: architecture-builder-ops-v2.md §1.2]
- Timeline enum lives in `0012`/`0015` (`timeline_event_type`); extend via `ADD VALUE`. [Source: 0012_create_lead_timeline.sql, 0015]

## References
- [Source: epics.md#Story 13.3; architecture-builder-ops-v2.md §1.2, §5.1]
- [Source: 0012/0015 timeline, supabase/functions/whatsapp-render]

## Implementation (2026-06-27)

**Files:** `nirman-crm/supabase/migrations/0065_customer_code.sql` · edited `supabase/functions/create-lead/index.ts`.

- `0065`: bare `ALTER TYPE timeline_event_type ADD VALUE IF NOT EXISTS` for `code_generated, visit_verified, visit_logged, lead_reclaimed` (Epic-13 lead-side events, added once). `CREATE OR REPLACE create_lead_with_pii` (same 17-arg sig as 0063) generating a per-tenant-unique `NIR-XXXXX` code via bounded pre-check loop (10 tries) with `leads_tenant_customer_code_idx` as backstop; sets `customer_code` in the INSERT; logs `code_generated`. `gen_random_bytes` schema-qualified (`extensions.`) under `search_path=''`.
- `create-lead` edge fn: after create, fetches `customer_code` + returns it plus a free `https://wa.me/91{phone}?text=...code...` delivery link (SMS deferred).

**Self-review:** same-signature CREATE OR REPLACE (no DROP). `encode/substr/upper` resolve from pg_catalog (implicit); only `gen_random_bytes` needs qualifying. Code collision handled by pre-check + unique index. No phone-unique constraint currently (dropped 0016) so the INSERT's only unique risk is customer_code.

**Deferred:** mobile lead-card "show code + Send via WhatsApp" action. Apply.

**Status:** backend code-complete, awaiting apply + mobile UI.
