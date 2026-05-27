import { createClient } from '@/lib/supabase/server'
import { NewEmployeeForm } from '@/components/auth/new-employee-form'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

export default async function TeamPage() {
  const supabase = await createClient()
  const { data: employees, error: employeesErr } = await supabase
    .from('users')
    .select('id, email_or_username, is_active, created_at')
    .eq('role', 'employee')
    .order('created_at', { ascending: false })

  if (employeesErr) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load team data. Please refresh the page.</p>
      </div>
    )
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Team</h1>
        <NewEmployeeForm />
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Username</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Created</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {(employees ?? []).map((emp) => (
            <TableRow key={emp.id}>
              <TableCell className="font-mono">{emp.email_or_username}</TableCell>
              <TableCell>{emp.is_active ? 'Active' : 'Inactive'}</TableCell>
              <TableCell>{new Date(emp.created_at).toLocaleDateString()}</TableCell>
            </TableRow>
          ))}
          {(employees ?? []).length === 0 && (
            <TableRow>
              <TableCell colSpan={3} className="text-center text-muted-foreground">
                No employees yet. Add one above.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
    </div>
  )
}
