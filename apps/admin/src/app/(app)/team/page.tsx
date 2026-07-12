import { createClient } from '@/lib/supabase/server'
import { InvitePanel } from '@/components/auth/invite-panel'
import { EmployeeActions } from '@/components/auth/employee-actions'
import { TabStrip } from '@/components/tab-strip'
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
    return <p className="text-danger">Failed to load team data. Please refresh the page.</p>
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <p className="eyebrow">People</p>
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            Team
          </h1>
        </div>
        {/* Progressive disclosure §4 — one primary entry point; the manual
            "create account directly" form lives inside the invite sheet. */}
        <InvitePanel />
      </div>

      <TabStrip />

      <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Username</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(employees ?? []).map((emp) => (
              <TableRow key={emp.id} className={emp.is_active ? '' : 'opacity-55'}>
                <TableCell className="font-medium">{emp.email_or_username}</TableCell>
                <TableCell>
                  <span
                    className={`inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11.5px] font-semibold ${
                      emp.is_active ? 'bg-sold-bg text-sold' : 'bg-dead-bg text-dead'
                    }`}
                  >
                    <span className="size-1.5 rounded-full bg-current" />
                    {emp.is_active ? 'Active' : 'Inactive'}
                  </span>
                </TableCell>
                <TableCell className="tabular-nums text-ink-2">
                  {new Date(emp.created_at).toLocaleDateString()}
                </TableCell>
                <TableCell className="text-right">
                  <EmployeeActions employeeId={emp.id} employeeName={emp.email_or_username} isActive={emp.is_active} />
                </TableCell>
              </TableRow>
            ))}
            {(employees ?? []).length === 0 && (
              <TableRow>
                <TableCell colSpan={4} className="text-center text-ink-3">
                  No employees yet. Invite your first teammate above.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
