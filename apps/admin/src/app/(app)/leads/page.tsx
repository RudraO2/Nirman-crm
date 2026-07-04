import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { Button } from '@/components/ui/button'
import { TabStrip } from '@/components/tab-strip'
import { LeadsToolbar } from '@/components/leads/leads-toolbar'
import { LeadsTable } from '@/components/leads/leads-table'
import type { LeadRow, EmployeeRow } from '@/components/leads/leads-table'

const PAGE_SIZE = 50

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
    return <p className="text-danger">Failed to load leads: {leadsErr?.message ?? empErr?.message}</p>
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
    <div className="space-y-5">
      <div className="space-y-2">
        <p className="eyebrow">Sales</p>
        <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
          Leads
        </h1>
        <p className="text-[13.5px] text-ink-2">
          {Number(total)} {Number(total) === 1 ? 'lead' : 'leads'}
          {archived ? ' (including archived)' : ' active'}
        </p>
      </div>

      <TabStrip />

      <LeadsToolbar
        employees={employees}
        initialQ={q}
        initialStatus={statusFilter}
        initialEmployee={employeeFilter}
        initialArchived={archived}
      />

      <LeadsTable leads={leads} employees={employees} />

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
