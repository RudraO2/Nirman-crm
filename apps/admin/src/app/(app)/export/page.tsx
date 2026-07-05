import { createClient } from '@/lib/supabase/server'
import { ExportFilters } from '@/components/export/export-filters'
import { TabStrip } from '@/components/tab-strip'

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
    <div className="space-y-5">
      <div className="space-y-2">
        <p className="eyebrow">Builder Ops</p>
        <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
          Export Leads
        </h1>
        <p className="text-[13.5px] text-ink-2">
          Filter leads and download as Excel. Each export is logged for audit.
        </p>
      </div>

      <TabStrip />

      <ExportFilters employees={employees} projects={projects} />
    </div>
  )
}
