// Pure, library-agnostic import parsing logic (no server / no Excel-lib deps).
// This is an exact port of the transformation that previously lived inline in
// parseExcelAction (Story 6.1). It operates on a dense 2-D grid of cell values,
// so any Excel reader that produces the same grid yields byte-for-byte identical
// results. Keeping it pure lets us unit/parity-test it without a server or a file.

import type { CrmField, ParsedRow, ParseResult } from './types'

export const SYNONYM_MAP: Record<CrmField, string[]> = {
  Name: ['name', 'customer name', 'lead name', 'client name', 'full name'],
  Phone: ['phone', 'mobile', 'number', 'contact', 'mob', 'cell'],
  Project: ['project', 'project name', 'development'],
  PropertyType: ['property type', 'type', 'unit type', 'property'],
  Location: ['location', 'area', 'city', 'address'],
  Budget: ['budget', 'budget range', 'price', 'price range'],
  TicketSize: ['ticket size', 'bhk', 'configuration', 'config'],
  Source: ['source', 'lead source', 'channel'],
  Remarks: ['remarks', 'notes', 'comments', 'comment'],
}

export function matchColumn(header: string): CrmField | null {
  const h = header.toLowerCase().trim()
  let bestField: CrmField | null = null
  let bestLen = -1

  for (const [field, synonyms] of Object.entries(SYNONYM_MAP) as [CrmField, string[]][]) {
    for (const syn of synonyms) {
      if (h.includes(syn) || syn.includes(h)) {
        if (syn.length > bestLen) {
          bestLen = syn.length
          bestField = field
        }
      }
    }
  }

  return bestField
}

/**
 * Build the ParseResult from a raw 2-D grid (row 0 = headers, rest = data).
 * The grid is expected to be dense (missing cells filled with '') — equivalent
 * to xlsx's `sheet_to_json(sheet, { header: 1, defval: '', raw: false })`.
 *
 * Throws the same error strings the Story 6.1 implementation threw.
 */
export function buildParseResult(rawRows: unknown[][]): ParseResult {
  if (rawRows.length === 0) throw new Error('Excel file is empty')

  const headers = (rawRows[0] as unknown[]).map((h) => String(h ?? '').trim()).filter(Boolean)
  if (headers.length === 0) throw new Error('Excel file has no column headers')

  const dataRows = rawRows.slice(1)

  const rows: ParsedRow[] = dataRows.map((row) => {
    const obj: ParsedRow = {}
    headers.forEach((h, idx) => {
      obj[h] = String((row as unknown[])[idx] ?? '').trim()
    })
    return obj
  })

  const mappings: Record<string, string | null> = {}
  for (const h of headers) {
    mappings[h] = matchColumn(h)
  }

  const phoneHeader = headers.find((h) => mappings[h] === 'Phone')
  const phoneValues = phoneHeader ? rows.map((r) => r[phoneHeader] ?? '').filter(Boolean) : []

  const phoneCount: Record<string, number> = {}
  for (const p of phoneValues) {
    phoneCount[p] = (phoneCount[p] ?? 0) + 1
  }
  const intraFileDupes = Object.values(phoneCount).filter((c) => c > 1).reduce((acc, c) => acc + (c - 1), 0)
  const missingPhoneCount = rows.filter((r) => !phoneHeader || !r[phoneHeader]).length

  return {
    columns: headers,
    mappings,
    rows,
    preview: rows.slice(0, 10),
    totalRows: rows.length,
    intraFileDupes,
    missingPhoneCount,
  }
}
