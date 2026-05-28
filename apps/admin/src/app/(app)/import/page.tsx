import { createClient } from '@/lib/supabase/server'
import { ImportWizard } from '@/components/import/import-wizard'

export default async function ImportPage() {
  const supabase = await createClient()
  const { data: employees, error } = await supabase.rpc('list_employees_for_assignment')

  if (error) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load employees: {error.message}</p>
      </div>
    )
  }

  const employeeList = (employees ?? [] as { id: string; username: string }[]).map(
    (e: { id: string; username: string }) => ({ id: e.id, name: e.username })
  )

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Import Leads</h1>
        <p className="text-sm text-muted-foreground">
          Upload an Excel file to bulk-import leads with automatic column matching and equal distribution.
        </p>
      </div>
      <ImportWizard employees={employeeList} />
    </div>
  )
}
