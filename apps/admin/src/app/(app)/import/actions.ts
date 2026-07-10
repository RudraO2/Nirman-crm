'use server'

import { createClient } from '@/lib/supabase/server'
import type { ParsedRow, ParseResult, ImportResult } from './types'
import { buildParseResult } from './parse-core'
import { readSheetGrid } from './xlsx-read'

export async function parseExcelAction(formData: FormData): Promise<ParseResult> {
  const file = formData.get('file') as File
  if (!file || file.size === 0) throw new Error('No file provided')

  const arrayBuffer = await file.arrayBuffer()
  const buffer = Buffer.from(arrayBuffer)

  const rawRows = await readSheetGrid(buffer)
  return buildParseResult(rawRows)
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
