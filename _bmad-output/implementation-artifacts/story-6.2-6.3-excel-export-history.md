# Stories 6.2 + 6.3 — Excel Export + Export History

**Epic:** 6 — Data Export
**Combined:** 6.3 export_log inserted atomically inside 6.2 RPC
**Status:** done

---

## Story 6.2: Admin Exports Leads to Excel

**As** an admin,
**I want** to filter leads and download them as an Excel file,
**so that** I can analyse data offline.

### Acceptance Criteria

- AC1: Filter UI — Status, Employee, Project, Property Type, date range (created_at from/to)
- AC2: Preview count updates on filter change with 400ms debounce; shows "…" while loading
- AC3: Export button downloads `crm-export-YYYY-MM-DD-HHMMSS.xlsx` within 10s for ≤10,000 rows
- AC4: Row 1 — merged watermark: `"Exported by [admin] on [YYYY-MM-DD HH:MM:SS tz]"` in tenant timezone
- AC5: Row 2 — column headers (17 columns)
- AC6: Row 3+ — one row per Lead with Name (decrypted), Phone (decrypted), Status, Source, Property Type, Location, Budget Min, Budget Max, Ticket Size, Remarks, Interest Type, Is Incomplete, Visit Date, Next Followup At, Created At, Assigned Employee, Last 3 Timeline Events
- AC7: Last 3 Timeline Events = last 3 lead_timeline rows newest-first: `"event_type (DD-Mon HH:MM) | ..."`; timestamps in tenant timezone

---

## Story 6.3: Export Audit Log

**As** an admin,
**I want** every export to be recorded with metadata,
**so that** I have a full audit trail.

### Acceptance Criteria

- AC1: `export_log` row inserted BEFORE data returned (inside `export_leads_data` RPC)
- AC2: Columns: id, tenant_id, admin_id, exported_at, filters_json, row_count, file_name
- AC3: Append-only — RLS allows INSERT + SELECT; no UPDATE or DELETE
- AC4: `/export/history` shows last 100 entries sorted newest-first
- AC5: Columns: file_name, row_count, exported_at, filters summary
- AC6: No delete/edit actions

---

## Implementation

### Migration: `supabase/migrations/0053_export_log_and_rpcs.sql`

Three objects: `export_log` table + `get_export_count()` + `export_leads_data()`

### Admin UI Files

- `apps/admin/src/app/(app)/export/page.tsx` — server component, fetches employees + projects
- `apps/admin/src/app/(app)/export/actions.ts` — server action `getExportCountAction`
- `apps/admin/src/app/(app)/export/download/route.ts` — GET route handler, returns xlsx buffer
- `apps/admin/src/app/(app)/export/history/page.tsx` — export audit log table
- `apps/admin/src/components/export/export-filters.tsx` — client component with filter state
- `apps/admin/src/app/(app)/layout.tsx` — added "Export" nav link after "Import"
