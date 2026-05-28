'use client'

import { useRouter } from 'next/navigation'
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Cell,
  LabelList,
  ResponsiveContainer,
} from 'recharts'

type FunnelStage = { stage: string; lead_count: number; dropoff_pct: number | null }
type Employee = { id: string; username: string }
type Project = { id: string; name: string }

const STAGE_CONFIG: Record<string, { label: string; color: string }> = {
  total:   { label: 'Total Leads', color: '#64748b' },
  warm:    { label: 'Warm',        color: '#f59e0b' },
  hot:     { label: 'Hot',         color: '#ef4444' },
  visited: { label: 'Visited',     color: '#8b5cf6' },
  sold:    { label: 'Sold',        color: '#22c55e' },
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

  const chartData = stages.map((s) => ({
    ...s,
    label: STAGE_CONFIG[s.stage]?.label ?? s.stage,
    color: STAGE_CONFIG[s.stage]?.color ?? '#94a3b8',
  }))

  const renderBarLabel = (props: any) => {
    const { x, y, width, height, index } = props
    const entry = chartData[index]
    // F-5: skip label for zero-count bars (would render at y-axis left edge)
    if (entry == null || entry.lead_count === 0) return null
    const lx = (x as number) + (width as number) + 10
    const cy = (y as number) + (height as number) / 2
    return (
      <g>
        <text
          x={lx}
          y={cy - 6}
          fontSize={12}
          fill="hsl(var(--foreground))"
          dominantBaseline="middle"
          fontWeight={500}
        >
          {entry.lead_count} leads
        </text>
        {/* F-3: only show directional drop/gain text when dropoff_pct is non-null */}
        {entry.dropoff_pct != null && entry.dropoff_pct > 0 && (
          <text x={lx} y={cy + 8} fontSize={11} fill="#6b7280" dominantBaseline="middle">
            ▼ {entry.dropoff_pct}% drop
          </text>
        )}
        {entry.dropoff_pct != null && entry.dropoff_pct < 0 && (
          <text x={lx} y={cy + 8} fontSize={11} fill="#6b7280" dominantBaseline="middle">
            ▲ {Math.abs(entry.dropoff_pct)}% gain
          </text>
        )}
      </g>
    )
  }

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
    <div className="p-6 space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Conversion Funnel</h1>
        <p className="text-sm text-muted-foreground">
          Pipeline drop-off from first contact to sale
        </p>
      </div>

      {/* Filters */}
      <div className="rounded-lg border bg-card p-4 space-y-3">
        {/* Employee filter */}
        <div className="flex items-center gap-3">
          <span className="text-sm text-muted-foreground w-20 shrink-0">Employee</span>
          <select
            value={activeEmployee}
            onChange={(e) => navigate(e.target.value, activeProject, activeRange)}
            className="rounded-md border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
          >
            <option value="">All Employees</option>
            {employees.map((emp) => (
              <option key={emp.id} value={emp.id}>
                {emp.username}
              </option>
            ))}
          </select>
        </div>

        {/* Project filter */}
        <div className="flex items-center gap-3">
          <span className="text-sm text-muted-foreground w-20 shrink-0">Project</span>
          <select
            value={activeProject}
            onChange={(e) => navigate(activeEmployee, e.target.value, activeRange)}
            className="rounded-md border bg-background px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-ring"
          >
            <option value="">All Projects</option>
            {projects.map((proj) => (
              <option key={proj.id} value={proj.id}>
                {proj.name}
              </option>
            ))}
          </select>
        </div>

        {/* Date range */}
        <div className="flex items-center gap-3">
          <span className="text-sm text-muted-foreground w-20 shrink-0">Range</span>
          <div className="flex items-center gap-1 rounded-lg border bg-muted p-1">
            {(['', '1', '7', '30'] as const).map((r) => (
              <button
                key={r}
                onClick={() => navigate(activeEmployee, activeProject, r)}
                className={
                  activeRange === r
                    ? 'rounded-md px-3 py-1.5 text-sm font-medium bg-background shadow-sm text-foreground'
                    : 'rounded-md px-3 py-1.5 text-sm text-muted-foreground hover:text-foreground transition'
                }
              >
                {RANGE_LABELS[r]}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Summary stat cards */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {statCards.map((card) => (
          <div key={card.label} className="rounded-lg border bg-card p-4">
            <p className="text-xs text-muted-foreground">{card.label}</p>
            <p className="mt-1 text-2xl font-semibold tabular-nums">{card.value}</p>
            <p className="text-xs text-muted-foreground mt-0.5">{card.sub}</p>
          </div>
        ))}
      </div>

      {/* Funnel chart */}
      <div className="rounded-lg border bg-card p-6">
        <p className="text-sm font-medium mb-1">Funnel Stages</p>
        <p className="text-xs text-muted-foreground mb-4">
          Lead count at each pipeline stage
        </p>
        {totalCount === 0 ? (
          <p className="text-sm text-muted-foreground py-8 text-center">
            No leads match the selected filters.
          </p>
        ) : (
          <ResponsiveContainer width="100%" height={320}>
            <BarChart
              data={chartData}
              layout="vertical"
              margin={{ top: 4, right: 180, bottom: 4, left: 4 }}
              barCategoryGap="20%"
            >
              <CartesianGrid
                strokeDasharray="3 3"
                horizontal={false}
                stroke="hsl(var(--border))"
              />
              <XAxis
                type="number"
                domain={[0, 'auto']}
                tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }}
                axisLine={false}
                tickLine={false}
                allowDecimals={false}
              />
              <YAxis
                type="category"
                dataKey="label"
                width={80}
                tick={{ fontSize: 12, fill: 'hsl(var(--foreground))' }}
                axisLine={false}
                tickLine={false}
              />
              <Tooltip
                cursor={{ fill: 'hsl(var(--muted))' }}
                contentStyle={{
                  background: 'hsl(var(--card))',
                  border: '1px solid hsl(var(--border))',
                  borderRadius: '8px',
                  fontSize: 12,
                }}
                formatter={(value, _name, props) => [
                  `${value} leads${props.payload?.dropoff_pct != null ? ` (▼ ${props.payload.dropoff_pct}% drop)` : ''}`,
                  props.payload?.label,
                ]}
              />
              <Bar dataKey="lead_count" radius={[0, 4, 4, 0]} maxBarSize={40}>
                {chartData.map((entry) => (
                  <Cell key={entry.stage} fill={entry.color} />
                ))}
                <LabelList content={renderBarLabel} />
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Drop-off table */}
      <div className="rounded-lg border bg-card">
        <div className="border-b px-4 py-3">
          <p className="text-sm font-medium">Stage Breakdown</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-left">
                <th className="px-4 py-2.5 font-medium text-muted-foreground">Stage</th>
                <th className="px-4 py-2.5 font-medium text-muted-foreground text-right">Count</th>
                <th className="px-4 py-2.5 font-medium text-muted-foreground text-right">Drop-off %</th>
                <th className="px-4 py-2.5 font-medium text-muted-foreground text-right">vs Total %</th>
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
