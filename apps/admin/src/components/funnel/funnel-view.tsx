'use client'

import { useRouter } from 'next/navigation'
import { TabStrip } from '@/components/tab-strip'

type FunnelStage = { stage: string; lead_count: number; dropoff_pct: number | null }
type Employee = { id: string; username: string }
type Project = { id: string; name: string }

// §3 palette — colors used for both the CSS funnel bars and the breakdown dots.
const STAGE_CONFIG: Record<string, { label: string; color: string }> = {
  total:   { label: 'Total',   color: 'var(--ink-2)' },
  warm:    { label: 'Warm',    color: 'var(--warm)' },
  hot:     { label: 'Hot',     color: 'var(--hot)' },
  visited: { label: 'Visited', color: 'var(--future)' },
  sold:    { label: 'Sold',    color: 'var(--sold)' },
}

const RANGE_LABELS: Record<string, string> = {
  '1':  'Today',
  '7':  'Last 7 days',
  '30': 'Last 30 days',
  '':   'All Time',
}

function safeRound1(num: number, denom: number): string {
  if (!denom) return '—'
  return (Math.round((num * 1000) / denom) / 10).toFixed(1) + '%'
}

export function FunnelView({
  stages,
  employees,
  projects,
  activeEmployee,
  activeProject,
  activeRange,
}: {
  stages: FunnelStage[]
  employees: Employee[]
  projects: Project[]
  activeEmployee: string
  activeProject: string
  activeRange: string
}) {
  const router = useRouter()

  function navigate(emp: string, proj: string, rng: string) {
    const params = new URLSearchParams()
    if (emp)  params.set('employee', emp)
    if (proj) params.set('project',  proj)
    if (rng)  params.set('range',    rng)
    const qs = params.toString()
    router.push(qs ? `/funnel?${qs}` : '/funnel')
  }

  const totalStage   = stages.find((s) => s.stage === 'total')
  const warmStage    = stages.find((s) => s.stage === 'warm')
  const hotStage     = stages.find((s) => s.stage === 'hot')
  const visitedStage = stages.find((s) => s.stage === 'visited')
  const soldStage    = stages.find((s) => s.stage === 'sold')

  const totalCount = totalStage?.lead_count ?? 0

  // CSS funnel bars — width relative to the Total stage (same numbers as before).
  const bars = stages.map((s) => ({
    ...s,
    label: STAGE_CONFIG[s.stage]?.label ?? s.stage,
    color: STAGE_CONFIG[s.stage]?.color ?? 'var(--ink-3)',
    pct: totalCount > 0 ? Math.round((s.lead_count / totalCount) * 100) : 0,
  }))

  const statCards = [
    {
      label: 'Total Leads',
      value: String(totalCount),
      sub: RANGE_LABELS[activeRange] ?? 'All Time',
    },
    {
      label: 'Warm → Hot',
      value: safeRound1(hotStage?.lead_count ?? 0, warmStage?.lead_count ?? 0),
      sub: 'conversion',
    },
    {
      label: 'Visit Rate',
      value: safeRound1(visitedStage?.lead_count ?? 0, totalCount),
      sub: 'of total leads',
    },
    {
      label: 'Close Rate',
      value: safeRound1(soldStage?.lead_count ?? 0, totalCount),
      sub: 'of total leads',
    },
  ]

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <p className="eyebrow">Sales</p>
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            Conversion Funnel
          </h1>
          <p className="text-[13.5px] text-ink-2">
            Pipeline drop-off from first contact to sale
          </p>
        </div>

        {/* Filters — employee, project, range */}
        <div className="flex flex-wrap items-center gap-2.5">
          <select
            value={activeEmployee}
            onChange={(e) => navigate(e.target.value, activeProject, activeRange)}
            aria-label="Filter by employee"
            className="rounded-[9px] border border-line-2 bg-paper px-3 py-1.5 text-sm text-ink focus:outline-none focus:ring-2 focus:ring-brass"
          >
            <option value="">All Employees</option>
            {employees.map((emp) => (
              <option key={emp.id} value={emp.id}>
                {emp.username}
              </option>
            ))}
          </select>
          <select
            value={activeProject}
            onChange={(e) => navigate(activeEmployee, e.target.value, activeRange)}
            aria-label="Filter by project"
            className="rounded-[9px] border border-line-2 bg-paper px-3 py-1.5 text-sm text-ink focus:outline-none focus:ring-2 focus:ring-brass"
          >
            <option value="">All Projects</option>
            {projects.map((proj) => (
              <option key={proj.id} value={proj.id}>
                {proj.name}
              </option>
            ))}
          </select>
          <div className="inline-flex gap-0.5 rounded-[10px] border border-line bg-mist p-[3px]">
            {(['1', '7', '30', ''] as const).map((r) => (
              <button
                key={r}
                onClick={() => navigate(activeEmployee, activeProject, r)}
                aria-pressed={activeRange === r}
                aria-label={`Show ${RANGE_LABELS[r]}`}
                className={
                  activeRange === r
                    ? 'rounded-[8px] bg-paper px-3.5 py-[5px] text-[12.5px] font-semibold text-ink shadow-[0_1px_3px_rgba(0,0,0,.08)]'
                    : 'rounded-[8px] px-3.5 py-[5px] text-[12.5px] font-medium text-ink-2 transition hover:text-ink'
                }
              >
                {RANGE_LABELS[r]}
              </button>
            ))}
          </div>
        </div>
      </div>

      <TabStrip />

      {/* Summary stat cards */}
      <div className="grid grid-cols-2 gap-3.5 sm:grid-cols-4">
        {statCards.map((card) => (
          <div key={card.label} className="rounded-[14px] border border-line bg-paper p-4 shadow-[var(--shadow)]">
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-ink-2">{card.label}</p>
            <p className="mt-1.5 font-serif text-[30px] font-medium tabular-nums text-ink">{card.value}</p>
            <p className="mt-0.5 text-xs text-ink-3">{card.sub}</p>
          </div>
        ))}
      </div>

      {/* Funnel — CSS bars (§7: replaces recharts, same numbers) */}
      <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
        <div className="flex items-center gap-2 border-b border-line px-5 py-3.5 text-[13.5px] font-semibold">
          Funnel <span className="font-normal text-ink-2">· where leads drop off</span>
        </div>
        <div className="p-5">
          {totalCount === 0 ? (
            <p className="py-8 text-center text-sm text-ink-2">
              No leads match the selected filters.
            </p>
          ) : (
            <div className="flex flex-col gap-3">
              {bars.map((b) => (
                <div
                  key={b.stage}
                  className="grid items-center gap-3.5"
                  style={{ gridTemplateColumns: '80px 1fr 160px' }}
                >
                  <span className="text-right text-[13px] font-semibold">{b.label}</span>
                  <div className="h-[30px] overflow-hidden rounded-[8px] bg-mist">
                    <div
                      className="flex h-full min-w-[34px] items-center rounded-[8px] pl-3 text-xs font-bold text-white"
                      style={{ width: `${Math.max(b.pct, b.lead_count > 0 ? 8 : 0)}%`, background: b.color }}
                    >
                      {b.lead_count > 0 ? b.lead_count : ''}
                    </div>
                  </div>
                  <span className="text-xs text-ink-2">
                    <b className="text-[13px] text-ink">{b.lead_count}</b>
                    {b.dropoff_pct == null ? (
                      ' leads'
                    ) : b.dropoff_pct >= 0 ? (
                      <>
                        {' · '}
                        <span className={b.dropoff_pct > 50 ? 'font-semibold text-hot' : ''}>
                          ▼ {b.dropoff_pct}%
                        </span>
                      </>
                    ) : (
                      <> · ▲ {Math.abs(b.dropoff_pct)}% gain</>
                    )}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Drop-off table */}
      <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
        <div className="border-b border-line px-5 py-3.5">
          <p className="text-[13.5px] font-semibold">Stage Breakdown</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-line text-left">
                <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3">Stage</th>
                <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-ink-3">Count</th>
                <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-ink-3">Drop-off %</th>
                <th className="px-4 py-2.5 text-right text-[11px] font-semibold uppercase tracking-wide text-ink-3">vs Total %</th>
              </tr>
            </thead>
            <tbody>
              {stages.length === 0 ? (
                <tr>
                  <td colSpan={4} className="px-4 py-8 text-center text-muted-foreground">
                    No data.
                  </td>
                </tr>
              ) : (
                stages.map((s) => {
                  const cfg = STAGE_CONFIG[s.stage]
                  const vsTotal = totalCount > 0
                    ? (Math.round((s.lead_count * 1000) / totalCount) / 10).toFixed(1) + '%'
                    : '—'
                  return (
                    <tr key={s.stage} className="border-b last:border-0">
                      <td className="px-4 py-3">
                        <span className="flex items-center gap-2">
                          <span
                            className="inline-block h-2.5 w-2.5 rounded-full shrink-0"
                            style={{ background: cfg?.color ?? '#94a3b8' }}
                          />
                          {cfg?.label ?? s.stage}
                        </span>
                      </td>
                      <td className="px-4 py-3 tabular-nums text-right font-medium">
                        {s.lead_count}
                      </td>
                      <td className="px-4 py-3 tabular-nums text-right text-muted-foreground">
                        {s.dropoff_pct != null ? (
                          <span className={s.dropoff_pct > 50 || s.dropoff_pct < 0 ? 'text-destructive' : ''}>
                            {s.dropoff_pct >= 0 ? '▼' : '▲'} {Math.abs(s.dropoff_pct)}%
                          </span>
                        ) : (
                          '—'
                        )}
                      </td>
                      <td className="px-4 py-3 tabular-nums text-right text-muted-foreground">
                        {s.stage === 'total' ? '100%' : vsTotal}
                      </td>
                    </tr>
                  )
                })
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
