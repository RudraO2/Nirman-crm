import { createClient } from '@/lib/supabase/server'
import { ExportFilters } from '@/components/export/export-filters'

type Employee = { id: string; username: string }
type Project  = { id: string; name: string }

export default async function ExportPage() {
  const supabase = await createClient()

  const [empResult, projResult] = await Promise.all([
    supabase.rpc('list_employees_for_assignment'),
    supabase.from('projects').select('id, name').order('name'),
  ])

  const employees = (empResult.data ?? []) as Employee[]
  const projects  = (projResult.data ?? []) as Project[]

  return (
    <div className="p-6 space-y-2">
      <div className="flex items-center justify-between pb-4">
        <div>
          <h1 className="text-2xl font-semibold">Export Leads</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Filter leads and download as Excel. Each export is logged for audit.
          </p>
        </div>
      </div>

      <ExportFilters employees={employees} projects={projects} />
    </div>
  )
}
