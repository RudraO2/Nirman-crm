export type ParsedRow = Record<string, string>

export type CrmField =
  | 'Name'
  | 'Phone'
  | 'Project'
  | 'PropertyType'
  | 'Location'
  | 'Budget'
  | 'TicketSize'
  | 'Source'
  | 'Remarks'

export type ColumnMapping = Record<string, CrmField | 'Ignore' | null>

export interface ParseResult {
  columns: string[]
  mappings: Record<string, string | null>
  rows: ParsedRow[]
  preview: ParsedRow[]
  totalRows: number
  intraFileDupes: number
  missingPhoneCount: number
}

export interface ImportResult {
  imported: number
  duplicates_skipped: number
  errors: number
  batch_id: string
}
