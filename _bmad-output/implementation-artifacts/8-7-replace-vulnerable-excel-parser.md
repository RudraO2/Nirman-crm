# Story 8.7 — Replace vulnerable Excel parser (`xlsx` → `exceljs`)

**Status:** in-review · **Epic:** 8 (SaaS Onboarding & Security hardening) · **Raised by:** dependency audit (D-6.1-2)
**Priority:** P1 — pre-launch security debt (unpatched high-sev CVEs in a prod dependency)
**Migration:** none (app-layer dependency swap only)

---

## Problem (the finding)

`apps/admin` depends on `xlsx@0.18.5` (SheetJS on the public npm registry). `npm audit`
reports it **high severity with _no fix available_**:

- **Prototype Pollution in SheetJS** — GHSA-4r6h-8v6p-xvw6
- **Regular Expression Denial of Service (ReDoS)** — GHSA-5pgg-2g8v-p4x9

The package is on the **attacker-reachable parse path**: the lead-import wizard
(`parseExcelAction`) reads an **admin-uploaded `.xlsx`** with `XLSX.read(buffer)` and
`XLSX.utils.sheet_to_json`. A malicious workbook can trigger the ReDoS / pollution during
parse. It is also used on the export side (`export/download/route.ts`) to _write_ a workbook.

There is no upstream patch on the npm distribution, so the only remediation is to **remove
`xlsx` entirely** and replace it with a maintained parser. `exceljs@4.4.0` is
audit-clean, MIT, pure-JS (no native build), and free — satisfies the "free + local, no
paid cloud" constraint.

**Blast radius:** import is admin-only (behind auth + `role === 'admin'`), so exploitation
requires an authenticated admin uploading a crafted file — lower than an unauthenticated
endpoint, but the file is untrusted input parsed server-side, and the CVEs are unpatched.
Killing the dependency removes the class entirely.

---

## Scope / non-goals

This is a **drop-in dependency replacement**. It MUST NOT change any observable behavior.

- **Import (Story 6.1) behavior preserved EXACTLY** — column synonym matching, auto-map,
  preview (first 10 rows), intra-file duplicate count, missing-phone count, and the equal
  distribution downstream are byte-for-byte identical. Verified by parity tests that compare
  the new parser's `ParseResult` against golden values captured from the **old `xlsx`**
  parser on the same fixtures.
- **Server Action contract unchanged** — `parseExcelAction(formData) → ParseResult`,
  `checkPhoneHashesAction`, `importLeadsAction` keep identical signatures and return types
  (`import/types.ts` untouched).
- **Import wizard UI unchanged** — `import-wizard.tsx` is not modified.
- **Export (Story 6.2) output preserved** — same sheet name (`Leads`), same watermark row,
  same `A1:Q1` merge, same column headers, same `.xlsx` MIME + filename.
- **Not in scope:** the other `npm audit` findings (`hono`, `js-yaml`, `postcss`/`next`) —
  unrelated packages, tracked separately. This story only clears the **Excel parsing path**.

---

## Acceptance Criteria

- **AC-1** — `xlsx` is removed from `apps/admin/package.json` (both `dependencies` and
  `devDependencies`) and from the lockfile. `npm ls xlsx` reports nothing.
- **AC-2** — `npm audit` no longer reports the two `xlsx` advisories (GHSA-4r6h-8v6p-xvw6,
  GHSA-5pgg-2g8v-p4x9). The Excel parse/write path is audit-clean.
- **AC-3** — `parseExcelAction` produces a `ParseResult` **identical** to the old `xlsx`
  implementation for every import fixture: `columns`, `mappings`, `rows`, `preview`,
  `totalRows`, `intraFileDupes`, `missingPhoneCount` all deep-equal. Proven by an automated
  parity test that captured golden output from the old parser before removal.
- **AC-4** — Error messages preserved exactly: `No file provided`, `Excel file has no sheets`,
  `Excel file is empty`, `Excel file has no column headers`.
- **AC-5** — The export route still emits a valid `.xlsx` with the watermark row, `A1:Q1`
  merge, `Leads` sheet, and the same 17 column headers; round-trips (re-parse) to the same data.
- **AC-6** — `tsc --noEmit` and `next build` are clean. No `import/types.ts` change; no
  `import-wizard.tsx` change.
- **AC-7** — Fixtures + tests are committed and runnable offline (`npm test`), covering:
  synonym auto-map, an unmatched column requiring manual map, intra-file phone duplicates,
  missing-phone rows, numeric-typed phone cells, an ignored/extra column, an empty header
  cell, and a >10-row file (preview truncation).

---

## Implementation notes

**Refactor for testability + guaranteed parity.** Split the pure logic from the I/O so the
byte-for-byte behavior lives in one testable function fed an identical 2-D grid regardless of
which library produced it:

- `import/parse-core.ts` (new, pure, no server/deno deps): `SYNONYM_MAP`, `matchColumn`,
  and `buildParseResult(rawRows: unknown[][]): ParseResult` — an **exact port** of the
  transformation that used to live inline in `parseExcelAction` (header filter → per-row
  object keyed by filtered-header index → mappings → phone dupe/missing counts → preview
  slice). Downstream logic is _unchanged code_, so identical grid input ⇒ identical output.
- `import/xlsx-read.ts` (new): `readSheetGrid(buffer): Promise<unknown[][]>` — the only
  library-specific code. Loads with `exceljs` and emits a dense `string[][]` grid
  **equivalent to** `XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '', raw: false })`:
  iterate `1..rowCount × 1..columnCount`, push `cell.text` (formatted text, `''` for empties),
  so number/text formatting and empty-cell filling match `raw:false` + `defval:''`. Throws
  `Excel file has no sheets` when there is no worksheet.
- `parseExcelAction` becomes: read file → `readSheetGrid` → `buildParseResult`. Same signature.

**Export (`export/download/route.ts`):** rebuild the workbook with `exceljs` —
`new ExcelJS.Workbook()`, `addWorksheet('Leads')`, `addRow(watermark)`, `mergeCells(1,1,1,17)`,
`addRow(COLS)`, `addRows(dataRows)`, `workbook.xlsx.writeBuffer()` → `Response` with the
same `Content-Disposition` and MIME. No `XLSX.*` remains.

**Parity method (how "EXACTLY" is proven):** while `xlsx` is still installed, a harness parses
each fixture through _both_ the old `xlsx` path and the new `exceljs` path and asserts
deep-equal. The exact `ParseResult`s are then frozen as golden JSON; `xlsx` is removed; the
committed test asserts the `exceljs` output equals the frozen golden — so the parity guarantee
survives without keeping the vulnerable package around.

**Runtime:** both files run under the Node runtime (server action + route handler), same as
`xlsx` did. `exceljs` is pure-JS; no edge-runtime flags, no native build.

---

## Test / verification

- **Parity/unit:** `node --import tsx --test` over `import/*.test.ts`. Fixtures generated as
  real `.xlsx` and committed under `import/__fixtures__/`. Each fixture asserts the full
  `ParseResult` against golden values captured from the old `xlsx` parser (AC-3, AC-7).
- **Export round-trip:** write via `exceljs`, re-load, assert watermark + merge + headers + rows.
- **Audit:** `npm audit` shows the two `xlsx` advisories gone; `npm ls xlsx` empty (AC-1/AC-2).
- **Build:** `tsc --noEmit` + `next build` clean (AC-6).

## Conventions (from `nirman-crm/CLAUDE.md`)

- No migration. No Supabase change. Free + local only (npm registry; no paid cloud branch).
- Keep admin `tsc`/`next build` green before pushing.

## Dev Agent Record (Amelia, 2026-07-10)

**Approach — refactor for guaranteed parity.** The old inline `parseExcelAction` was split
into a pure port + a thin library adapter, so the byte-for-byte behavior is driven by an
identical 2-D grid regardless of the Excel library:

- `import/parse-core.ts` (new, pure) — `SYNONYM_MAP`, `matchColumn`, `buildParseResult(grid)`.
  Exact port of the Story 6.1 transform; **downstream logic is unchanged code**.
- `import/xlsx-read.ts` (new) — `readSheetGrid(buffer)`: the only exceljs-specific code.
  Iterates `1..rowCount × 1..columnCount`, pushing `cell.text` (formatted, `''` for empty),
  producing a grid equivalent to `sheet_to_json(sheet, { header:1, defval:'', raw:false })`.
- `import/actions.ts` — `parseExcelAction` now = read file → `readSheetGrid` → `buildParseResult`.
  **Same signature/return type.** `checkPhoneHashesAction` / `importLeadsAction` untouched.
- `export/download/route.ts` — workbook rebuilt with exceljs (`addWorksheet('Leads')`,
  watermark row, `mergeCells(1,1,1,17)`, `COLS` row, `addRows`, `writeBuffer`). Same MIME/filename.
- `xlsx` **removed** from `package.json` + lockfile (`npm ls xlsx` empty). `exceljs@4.4.0` added
  (MIT, pure-JS, audit-clean). `tsx@4.23.0` added as devDep to run `node --test` over TS.

**Parity proof (how "EXACTLY" was verified).** A dev harness (`__fixtures__/parity.ts`, since
removed with xlsx) parsed all 8 fixtures through **both** the old `xlsx` path and the new
`exceljs` path and asserted `deepStrictEqual` on the full `ParseResult`. **All 8 matched**,
including the tricky cases: numeric-typed phone cells (`9876543210` → `"9876543210"`,
`7500000.5` → `"7500000.5"`), and the empty-middle-header index-shift (filtered-header index
still reads the shifted raw column — old behavior preserved). The matching `ParseResult`s were
frozen to `__fixtures__/expected.json`; the committed `parse.test.ts` asserts exceljs output ==
that golden, so parity is locked without keeping the vulnerable package.

**Files changed:**
- `import/parse-core.ts`, `import/xlsx-read.ts` (new); `import/actions.ts`, `export/download/route.ts` (swapped).
- `import/__fixtures__/` — 8 `.xlsx` fixtures + `expected.json` (golden) + `gen.mjs` (regenerator).
- `import/parse.test.ts` (new) — 13 tests. `package.json` — `+exceljs`, `-xlsx`, `+tsx`, `test` script.
- `import/types.ts` and `components/import/import-wizard.tsx` — **unchanged** (per hard constraint).

**Verification (free + local — no paid cloud, no Supabase change):**
- `npm test` ⇒ **13/13 pass** (8 fixture-parity + 3 error-contract + 1 graceful-load + 1 export round-trip).
- `npm audit` ⇒ the two `xlsx` advisories (GHSA-4r6h-8v6p-xvw6, GHSA-5pgg-2g8v-p4x9) **gone**;
  `npm ls xlsx` empty. (Remaining `hono`/`js-yaml`/`postcss` findings are unrelated, out of scope.)
- `tsc --noEmit` clean; `next build` clean (all routes incl `/import`, `/export/download` compiled).

**AC status:** AC-1 ✓, AC-2 ✓, AC-3 ✓ (8-fixture parity, frozen golden), AC-4 ✓ (all 4 error
strings preserved), AC-5 ✓ (export round-trip test), AC-6 ✓ (tsc + build), AC-7 ✓ (fixtures +
tests committed, run offline via `npm test`).

## Code review (3-lens adversarial, 2026-07-10)

Blind Hunter + Edge Case Hunter + Acceptance Auditor over the full diff.

- **F1 (HIGH, Edge Case) — `.xls` capability regression. FIXED (graceful).** The wizard picker
  advertises `.xlsx,.xls`; the old `xlsx` package parsed legacy BIFF/OLE `.xls`, but
  `exceljs.xlsx.load` reads only the OOXML `.xlsx` (zip) format and throws a raw zip-parser
  error on `.xls`. Per the hard "wizard UI unchanged" constraint the picker was **not** touched;
  instead `readSheetGrid` now wraps `load` in try/catch and throws a clean, actionable message
  (`"Could not read the file. Please upload a valid .xlsx spreadsheet (legacy .xls is not
  supported)."`). **⚠️ Deviation for Rudra to ack:** genuine `.xls` uploads that previously
  imported will now be rejected with that message. Real-world exports are `.xlsx`; dropping the
  unpatchable `xlsx` package is the whole point. If `.xls` ingest is still required, that needs a
  separate non-vulnerable converter — out of scope here.
- **F2 (MED, Blind Hunter) — raw errors on corrupt/non-spreadsheet uploads. FIXED.** Same
  try/catch now yields the clean message instead of a stack trace. Covered by a test.
- **F3 (LOW, Blind Hunter) — trailing styled-blank rows / date / formula cells.** `cell.text`
  vs xlsx `raw:false` *could* format these differently. The import maps only the 9 text CRM
  fields (no date columns), and the missing-phone/dupe counts are preview-only stats (the
  `bulk_import_leads` RPC re-filters server-side). Accepted limitation; no code change.
- **F4 (Acceptance Auditor).** AC-1…AC-7 all satisfied; no gap found.

Re-verified after the F1/F2 fix: `npm test` 13/13, `tsc` clean, `next build` clean.
**Verdict: review-clean, ready for merge.** Not deployed (app-layer only; ships with the next
`apps/admin` deploy — no migration, no Supabase change).

## Out of scope

- `hono`, `js-yaml`, `postcss`/`next` audit findings (unrelated dependencies).
- Any change to the import wizard UX, mapping UI, or distribution RPC (`bulk_import_leads`).
