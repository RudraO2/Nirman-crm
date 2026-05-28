import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

type FiltersJson = {
  status?:        string | null
  property_type?: string | null
  date_from?:     string | null
  date_to?:       string | null
  employee_id?:   string | null
  project_id?:    string | null
}

type ExportLogRow = {
  id:           string
  file_name:    string
  row_count:    number
  exported_at:  string
  filters_json: FiltersJson
}

function formatFilters(f: FiltersJson): string {
  const parts: string[] = []
  if (f.status)        parts.push(`Status: ${f.status}`)
  if (f.property_type) parts.push(`Property: ${f.property_type}`)
  if (f.date_from)     parts.push(`From: ${f.date_from}`)
  if (f.date_to)       parts.push(`To: ${f.date_to}`)
  if (f.employee_id)   parts.push('Employee: filtered')
  if (f.project_id)    parts.push('Project: filtered')
  return parts.length > 0 ? parts.join(' · ') : 'All leads'
}

export default async function ExportHistoryPage() {
  const supabase = await createClient()

  const { data: entries, error } = await supabase
    .from('export_log')
    .select('*')
    .order('exported_at', { ascending: false })
    .limit(100)

  if (error) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load export history. Please refresh the page.</p>
      </div>
    )
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center gap-4">
        <Link
          href="/export"
          className="text-sm text-muted-foreground hover:text-foreground transition-colors"
        >
          ← Back to Export
        </Link>
        <div>
          <h1 className="text-2xl font-semibold">Export History</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Last 100 exports — append-only audit log</p>
        </div>
      </div>

      <div className="rounded-lg border bg-card overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>File Name</TableHead>
              <TableHead className="text-right w-20">Rows</TableHead>
              <TableHead className="w-44">Exported At</TableHead>
              <TableHead>Filters Applied</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(entries as ExportLogRow[] ?? []).map((entry) => (
              <TableRow key={entry.id}>
                <TableCell className="font-mono text-xs">{entry.file_name}</TableCell>
                <TableCell className="text-right tabular-nums">
                  {entry.row_count.toLocaleString()}
                </TableCell>
                <TableCell className="text-sm">
                  {new Date(entry.exported_at).toLocaleString()}
                </TableCell>
                <TableCell className="text-sm text-muted-foreground">
                  {formatFilters(entry.filters_json)}
                </TableCell>
              </TableRow>
            ))}
            {(entries ?? []).length === 0 && (
              <TableRow>
                <TableCell
                  colSpan={4}
                  className="text-center text-muted-foreground py-12"
                >
                  No exports yet.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
