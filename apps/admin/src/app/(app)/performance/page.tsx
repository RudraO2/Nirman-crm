import { createClient } from '@/lib/supabase/server'
import { PerformanceDashboard } from '@/components/performance/performance-dashboard'

type EmployeeStat = {
  employee_id: string
  employee_name: string
  active_leads: number
  warm_count: number
  cold_count: number
  hot_count: number
  dead_count: number
  sold_count: number
  future_count: number
  followups_completed: number
  followups_missed: number
  total_assigned: number
  conversion_rate: number
}

type ChartDay = { day: string; new_leads: number; status_changes: number }
type StatusDist = { status: string; lead_count: number }

export default async function PerformancePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>
}) {
  const sp = await searchParams
  const range = typeof sp.range === 'string' ? sp.range : '30'
  // Mirrors PerformanceDashboard's p_days derivation so the fetched window always
  // matches what's displayed (same 730-day cap as the client-side Custom picker).
  const parsedDays = Number(range)
  const p_days =
    Number.isInteger(parsedDays) && parsedDays > 0 ? Math.min(parsedDays, 730) : 30

  const supabase = await createClient()

  const [
    { data: statsRaw, error: statsErr },
    { data: chartRaw, error: chartErr },
    { data: distRaw, error: distErr },
  ] = await Promise.all([
    supabase.rpc('get_employee_performance_stats', { p_days }),
    supabase.rpc('get_pipeline_activity_14d'),
    supabase.rpc('get_lead_status_distribution'),
  ])

  if (statsErr || chartErr || distErr) {
    return (
      <div className="p-6">
        <p className="text-destructive">
          Failed to load performance data:{' '}
          {statsErr?.message ?? chartErr?.message ?? distErr?.message}
        </p>
      </div>
    )
  }

  return (
    <PerformanceDashboard
      employeeStats={(statsRaw ?? []) as EmployeeStat[]}
      chartData={(chartRaw ?? []) as ChartDay[]}
      statusDist={(distRaw ?? []) as StatusDist[]}
      initialRange={range}
    />
  )
}
