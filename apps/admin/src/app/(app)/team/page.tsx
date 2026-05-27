import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { NewEmployeeForm } from '@/components/auth/new-employee-form'
import { EmployeeActions } from '@/components/auth/employee-actions'
import { UnlockAccountButton } from '@/components/auth/unlock-account-button'
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
  const { data: employees } = await supabase
    .from('users')
    .select('id, email_or_username, is_active, locked_until, created_at')
    .eq('role', 'employee')
    .order('created_at', { ascending: false })

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Team</h1>
        <div className="flex items-center gap-4">
          <Link href="/team/security-log" className="text-sm text-muted-foreground underline">
            Security Log
          </Link>
          <NewEmployeeForm />
        </div>
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
                <div className="flex flex-col gap-1">
                  <span className={emp.is_active ? 'text-green-600' : 'text-muted-foreground'}>
                    {emp.is_active ? 'Active' : 'Inactive'}
                  </span>
                  {emp.locked_until && new Date(emp.locked_until) > new Date() && (
                    <span className="text-xs text-destructive font-medium">Locked</span>
                  )}
                </div>
              </TableCell>
              <TableCell>{new Date(emp.created_at).toLocaleDateString()}</TableCell>
              <TableCell>
                <div className="flex flex-wrap gap-2">
                  <EmployeeActions employeeId={emp.id} isActive={emp.is_active} />
                  {emp.locked_until && new Date(emp.locked_until) > new Date() && (
                    <UnlockAccountButton employeeId={emp.id} />
                  )}
                </div>
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
