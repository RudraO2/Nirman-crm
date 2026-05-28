import { createClient } from '@/lib/supabase/server'
import { FuturePoolView } from './future-pool-view'
import type { EmployeeRow } from '@/components/leads/leads-table'
import type { FutureLeadRow } from './future-pool-view'

export default async function FuturePoolPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const sp = await searchParams
  const interestTypeFilter = typeof sp.interestType === 'string' ? sp.interestType : ''
  const projectMatch = typeof sp.projectMatch === 'string' ? sp.projectMatch : ''
  const matchCount = typeof sp.matchCount === 'string' ? (parseInt(sp.matchCount, 10) || 0) : 0

  const supabase = await createClient()

  const [{ data: leadsRaw, error: leadsErr }, { data: employeesRaw, error: empErr }] = await Promise.all([
    supabase.rpc('list_assignable_leads', {
      p_q: null,
      p_status: 'future',
      p_employee: null,
      p_include_archived: true,
      p_limit: 200,
      p_offset: 0,
      p_unassigned_only: false,
    }),
    supabase.rpc('list_employees_for_assignment'),
  ])

  if (leadsErr || empErr) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load: {leadsErr?.message ?? empErr?.message}</p>
      </div>
    )
  }

  return (
    <FuturePoolView
      leads={(leadsRaw ?? []) as FutureLeadRow[]}
      employees={(employeesRaw ?? []) as EmployeeRow[]}
      interestTypeFilter={interestTypeFilter}
      projectMatch={projectMatch}
      matchCount={matchCount}
    />
  )
}
