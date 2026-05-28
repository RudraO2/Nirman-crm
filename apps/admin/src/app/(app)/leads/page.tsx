import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { LeadsToolbar } from '@/components/leads/leads-toolbar'
import { AssignDialog } from '@/components/leads/assign-dialog'
import { StatusPill } from '@/components/leads/status-pill'

const PAGE_SIZE = 50

interface LeadRow {
  id: string
  name: string | null
  phone_last4: string | null
  status: string
  assigned_to_user_id: string | null
  assignee_username: string | null
  assignment_deadline: string | null
  created_at: string
  total_count: number
}

interface EmployeeRow { id: string; username: string }

function fmtDate(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return d.toLocaleString(undefined, { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' })
}

export default async function LeadsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const sp = await searchParams
  const q = typeof sp.q === 'string' ? sp.q : ''
  const statusFilter = typeof sp.status === 'string' ? sp.status : ''
  const employeeFilter = typeof sp.employee === 'string' ? sp.employee : ''
  const archived = sp.archived === '1'
  const pageNum = Math.max(1, parseInt(typeof sp.page === 'string' ? sp.page : '1', 10) || 1)
  const offset = (pageNum - 1) * PAGE_SIZE

  const supabase = await createClient()

  const unassignedOnly = employeeFilter === '__unassigned__'
  const [{ data: leadsRaw, error: leadsErr }, { data: employeesRaw, error: empErr }] = await Promise.all([
    supabase.rpc('list_assignable_leads', {
      p_q: q || null,
      p_status: statusFilter || null,
      p_employee: !unassignedOnly && employeeFilter ? employeeFilter : null,
      p_include_archived: archived,
      p_limit: PAGE_SIZE,
      p_offset: offset,
      p_unassigned_only: unassignedOnly,
    }),
    supabase.rpc('list_employees_for_assignment'),
  ])

  if (leadsErr || empErr) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load leads: {leadsErr?.message ?? empErr?.message}</p>
      </div>
    )
  }

  const leads = (leadsRaw ?? []) as LeadRow[]
  const employees = (employeesRaw ?? []) as EmployeeRow[]
  const total = leads[0]?.total_count ?? 0
  const totalPages = Math.max(1, Math.ceil(Number(total) / PAGE_SIZE))

  function pageHref(p: number) {
    const params = new URLSearchParams()
    if (q) params.set('q', q)
    if (statusFilter) params.set('status', statusFilter)
    if (employeeFilter) params.set('employee', employeeFilter)
    if (archived) params.set('archived', '1')
    if (p > 1) params.set('page', String(p))
    const qs = params.toString()
    return qs ? `/leads?${qs}` : '/leads'
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Leads</h1>
          <p className="text-sm text-muted-foreground">
            {Number(total)} {Number(total) === 1 ? 'lead' : 'leads'}
            {archived ? ' (including archived)' : ' active'}
          </p>
        </div>
      </div>

      <LeadsToolbar
        employees={employees}
        initialQ={q}
        initialStatus={statusFilter}
        initialEmployee={employeeFilter}
        initialArchived={archived}
      />

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Assigned to</TableHead>
              <TableHead>Deadline</TableHead>
              <TableHead>Created</TableHead>
              <TableHead className="text-right">Action</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {leads.map((l) => (
              <TableRow key={l.id} className="hover:bg-muted/40">
                <TableCell className="font-medium">{l.name ?? <span className="text-muted-foreground italic">Unnamed</span>}</TableCell>
                <TableCell className="font-mono text-xs text-muted-foreground">•••{l.phone_last4 ?? '----'}</TableCell>
                <TableCell><StatusPill status={l.status} /></TableCell>
                <TableCell>
                  {l.assignee_username ?? <span className="text-muted-foreground italic">Unassigned</span>}
                </TableCell>
                <TableCell className="text-sm text-muted-foreground">{fmtDate(l.assignment_deadline)}</TableCell>
                <TableCell className="text-sm text-muted-foreground">{fmtDate(l.created_at)}</TableCell>
                <TableCell className="text-right">
                  <AssignDialog
                    leadId={l.id}
                    leadName={l.name}
                    phoneLast4={l.phone_last4}
                    currentAssigneeId={l.assigned_to_user_id}
                    currentDeadline={l.assignment_deadline}
                    employees={employees}
                  />
                </TableCell>
              </TableRow>
            ))}
            {leads.length === 0 && (
              <TableRow>
                <TableCell colSpan={7} className="text-center text-muted-foreground py-8">
                  {(q || statusFilter || employeeFilter || archived) ? 'No leads match these filters.' : 'No leads yet.'}
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {totalPages > 1 && (
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">Page {pageNum} of {totalPages}</span>
          <div className="flex gap-2">
            {pageNum > 1 ? (
              <Button asChild variant="outline" size="sm">
                <Link href={pageHref(pageNum - 1)}>Previous</Link>
              </Button>
            ) : (
              <Button variant="outline" size="sm" disabled>Previous</Button>
            )}
            {pageNum < totalPages ? (
              <Button asChild variant="outline" size="sm">
                <Link href={pageHref(pageNum + 1)}>Next</Link>
              </Button>
            ) : (
              <Button variant="outline" size="sm" disabled>Next</Button>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
