import { createClient } from '@/lib/supabase/server'
import { FunnelView } from '@/components/funnel/funnel-view'

type FunnelStage = { stage: string; lead_count: number; dropoff_pct: number | null }
type Employee = { id: string; username: string }
type Project = { id: string; name: string }

export default async function FunnelPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const sp = await searchParams
  const employee = typeof sp.employee === 'string' ? sp.employee : ''
  const project  = typeof sp.project  === 'string' ? sp.project  : ''
  const range    = typeof sp.range    === 'string' ? sp.range    : ''

  const p_days =
    range === '1'  ? 1  :
    range === '7'  ? 7  :
    range === '30' ? 30 :
    null

  const supabase = await createClient()

  const [
    { data: funnelRaw, error: funnelErr },
    { data: employeesRaw },
    { data: projectsRaw },
  ] = await Promise.all([
    supabase.rpc('get_funnel_stats', {
      p_employee_id: employee || null,
      p_project_id:  project  || null,
      p_days,
    }),
    supabase.rpc('list_employees_for_assignment'),
    supabase.from('projects').select('id, name').eq('is_active', true).order('name'),
  ])

  if (funnelErr) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load funnel data: {funnelErr.message}</p>
      </div>
    )
  }

  return (
    <FunnelView
      stages={(funnelRaw ?? []) as FunnelStage[]}
      employees={(employeesRaw ?? []) as Employee[]}
      projects={(projectsRaw ?? []) as Project[]}
      activeEmployee={employee}
      activeProject={project}
      activeRange={range}
    />
  )
}
