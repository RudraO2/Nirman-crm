# Epic 11 — Web WhatsApp Template Management (11.1 + 11.2 + 11.3)

**Status:** review · **Implemented:** 2026-07-07 · **Migration:** none (reuses `0023` schema, RLS, max-3 trigger)

## What shipped

### 11.1 — Admin manages templates on the web (`apps/admin`)
- New **`/templates`** page: `(app)/templates/page.tsx` (server, fetches rows + `tenant_id` from JWT) + `templates-client.tsx` (client CRUD), mirroring the `developer-updates` page pattern.
- Direct table CRUD on `whatsapp_templates` through existing RLS (`whatsapp_templates_select` / `whatsapp_templates_admin_write`); inserts carry `tenant_id` explicitly (column has no default; RLS re-checks it).
- `template_limit_exceeded` trigger error mapped to "You can have at most 3 templates — delete one to add another"; **New template** button disables at 3.
- Non-empty name/body validated inline; delete has a confirm dialog; structured `console.info` log `{event: whatsapp_template_write, action, template_id}` on writes.
- Nav: **Templates** tab added to the **Team** group (`nav.ts`), TabStrip picks it up automatically.

### 11.2 — Variable chips + live preview
- Static 8-token catalog: `{{name}} {{phone}} {{project}} {{property_type}} {{ticket_size}} {{budget}} {{status}} {{followup_date}}`.
- Chips insert `{{token}}` **at the cursor** in the body textarea (selection preserved).
- Live preview renders the body against a sample lead; stored body keeps literal `{{token}}`s (substitution is send-time only).

### 11.3 — Mobile send-time substitution (`apps/mobile`)
- `WhatsAppTemplate.render()` (`lead_model.dart`) rewritten catalog-driven: exposes `tokenCatalog` (same 8 tokens — **must stay in sync with the admin chip list**), fills all 8 from the lead, null/empty → `—` (was `[Not set]`), unknown `{{token}}`s stripped (single rule; message never carries raw braces).
- `whatsapp_sheet.dart` now passes phone (`displayPhone`), status, formatted `next_followup_at`, and project names (via `availableProjectsProvider` matched against `lead.projectIds`).
- Confirm-before-send + `whatsapp_sent` timeline logging unchanged.

## Bug fixed alongside
- **wa.me link missing country code** (`whatsapp_sheet.dart` `_send`): leads store raw 10-digit numbers; `wa.me/$phone` opened no chat. Now non-digits stripped and `91` prefixed for 10-digit numbers — same rule as the `create-lead` edge fn's `whatsapp_link`.

## Verification
- Mobile: `flutter analyze` 0 errors · full suite **133/133 pass**.
- Admin: `npx tsc --noEmit` clean · `npx next build` green, `/templates` route emitted.

## Notes / seams
- Token catalog duplicated by design (Dart + TS static lists) — one-line comment on each points at the other.
- Story 8.6 (starter templates on tenant create) still backlog; empty state on `/templates` covers the gap.
