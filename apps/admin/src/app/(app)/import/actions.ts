'use server'

import * as XLSX from 'xlsx'
import { createClient } from '@/lib/supabase/server'
import type { CrmField, ParsedRow, ParseResult, ImportResult } from './types'

const SYNONYM_MAP: Record<CrmField, string[]> = {
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

function matchColumn(header: string): CrmField | null {
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

export async function parseExcelAction(formData: FormData): Promise<ParseResult> {
  const file = formData.get('file') as File
  if (!file || file.size === 0) throw new Error('No file provided')

  const arrayBuffer = await file.arrayBuffer()
  const buffer = Buffer.from(arrayBuffer)
  const workbook = XLSX.read(buffer, { type: 'buffer' })

  const sheetName = workbook.SheetNames[0]
  if (!sheetName) throw new Error('Excel file has no sheets')

  const sheet = workbook.Sheets[sheetName]
  const rawRows = (XLSX.utils.sheet_to_json(sheet, {
    header: 1,
    defval: '',
    raw: false,
  }) as unknown) as unknown[][]

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

export async function checkPhoneHashesAction(phoneValues: string[]): Promise<string[]> {
  if (phoneValues.length === 0) return []

  const encoder = new TextEncoder()
  const hashes = await Promise.all(
    phoneValues.map(async (phone) => {
      const normalized = normalizePhoneClient(phone)
      if (!normalized) return null
      const buf = await crypto.subtle.digest('SHA-256', encoder.encode(normalized))
      return Array.from(new Uint8Array(buf))
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('')
    })
  )
  const validHashes = hashes.filter((h): h is string => h !== null)

  const supabase = await createClient()
  const { data, error } = await supabase.rpc('check_phone_hashes', { p_hashes: validHashes })
  if (error) throw new Error(error.message)

  return (data ?? []).map((row: { phone_hash: string }) => row.phone_hash)
}

function normalizePhoneClient(phone: string): string | null {
  let p = phone.trim().replace(/\D/g, '')
  if (p.length === 12 && p.startsWith('91')) p = p.slice(2)
  if (p.length === 11 && p.startsWith('0')) p = p.slice(1)
  if (p.length === 10) return p
  return null
}

export async function importLeadsAction(
  rows: ParsedRow[],
  mappings: Record<string, string>,
  employeeIds: string[]
): Promise<ImportResult> {
  const pRows = rows.map((row) => {
    const mapped: Record<string, string> = {}
    for (const [col, crmField] of Object.entries(mappings)) {
      if (!crmField || crmField === 'Ignore') continue
      const fieldKey = crmFieldToKey(crmField)
      if (fieldKey) mapped[fieldKey] = row[col] ?? ''
    }
    return {
      name: mapped.name ?? null,
      phone_raw: mapped.phone_raw ?? null,
      project_name: mapped.project_name ?? null,
      property_type: mapped.property_type ?? null,
      location: mapped.location ?? null,
      budget_raw: mapped.budget_raw ?? null,
      ticket_size: mapped.ticket_size ?? null,
      source_raw: mapped.source_raw ?? null,
      remarks: mapped.remarks ?? null,
    }
  })

  const supabase = await createClient()
  const { data, error } = await supabase.rpc('bulk_import_leads', {
    p_rows: pRows,
    p_employee_ids: employeeIds,
  })
  if (error) throw new Error(error.message)

  return data as ImportResult
}

function crmFieldToKey(field: string): string | null {
  const map: Record<string, string> = {
    Name: 'name',
    Phone: 'phone_raw',
    Project: 'project_name',
    PropertyType: 'property_type',
    Location: 'location',
    Budget: 'budget_raw',
    TicketSize: 'ticket_size',
    Source: 'source_raw',
    Remarks: 'remarks',
  }
  return map[field] ?? null
}
