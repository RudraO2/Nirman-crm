import { createClient } from '@/lib/supabase/server'
import { NewEmployeeForm } from '@/components/auth/new-employee-form'
import { EmployeeActions } from '@/components/auth/employee-actions'
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
            <TableHead>Actions</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {(employees ?? []).map((emp) => (
            <TableRow key={emp.id} className={emp.is_active ? '' : 'opacity-60'}>
              <TableCell className="font-mono">{emp.email_or_username}</TableCell>
              <TableCell>
                <span className={emp.is_active ? 'text-green-600' : 'text-muted-foreground'}>
                  {emp.is_active ? 'Active' : 'Inactive'}
                </span>
              </TableCell>
              <TableCell>{new Date(emp.created_at).toLocaleDateString()}</TableCell>
              <TableCell>
                <EmployeeActions employeeId={emp.id} isActive={emp.is_active} />
              </TableCell>
            </TableRow>
          ))}
          {(employees ?? []).length === 0 && (
            <TableRow>
              <TableCell colSpan={4} className="text-center text-muted-foreground">
                No employees yet. Add one above.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
    </div>
  )
}
