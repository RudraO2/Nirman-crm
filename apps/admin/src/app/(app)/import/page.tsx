import { createClient } from '@/lib/supabase/server'
import { ImportWizard } from '@/components/import/import-wizard'
import { TabStrip } from '@/components/tab-strip'

export default async function ImportPage() {
  const supabase = await createClient()
  const { data: employees, error } = await supabase.rpc('list_employees_for_assignment')

  if (error) {
    return <p className="text-danger">Failed to load employees: {error.message}</p>
  }

  const employeeList = (employees ?? [] as { id: string; username: string }[]).map(
    (e: { id: string; username: string }) => ({ id: e.id, name: e.username })
  )

  return (
    <div className="space-y-5">
      <div className="space-y-2">
        <p className="eyebrow">Builder Ops</p>
        <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
          Import Leads
        </h1>
        <p className="text-[13.5px] text-ink-2">
          Upload an Excel file to bulk-import leads with automatic column matching and equal distribution.
        </p>
      </div>

      <TabStrip />

      <ImportWizard employees={employeeList} />
    </div>
  )
}
