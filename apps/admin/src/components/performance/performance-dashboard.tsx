'use client'

import { useState, useMemo } from 'react'
import { useRouter } from 'next/navigation'
import { TabStrip } from '@/components/tab-strip'
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
} from 'recharts'

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

// §3 status palette
const STATUS_COLORS: Record<string, string> = {
  warm: '#C07A17',
  cold: '#3E6DA6',
  hot: '#C24638',
  dead: '#78817B',
  sold: '#2F7D4F',
  future: '#7A5BA8',
}

const RANGE_LABELS: Record<string, string> = {
  '1': 'Today',
  '7': 'Last 7 days',
  '30': 'Last 30 days',
}

const DEFAULT_STATUSES = ['warm', 'cold', 'hot']
const EXTRA_STATUSES = ['dead', 'sold', 'future']

function formatDayLabel(day: string) {
  const d = new Date(day + 'T00:00:00')
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${mm}/${dd}`
}

export function PerformanceDashboard({
  employeeStats,
  chartData,
  statusDist,
  initialRange,
}: {
  employeeStats: EmployeeStat[]
  chartData: ChartDay[]
  statusDist: StatusDist[]
  initialRange: string
}) {
  const router = useRouter()
  const p_days = initialRange === '1' ? 1 : initialRange === '7' ? 7 : 30

  const [sortDesc, setSortDesc] = useState(true)
  const [showExtra, setShowExtra] = useState(false)
  const [showDonutExtra, setShowDonutExtra] = useState(false)

  // Sort employees by active_leads
  const sortedStats = useMemo(
    () =>
      [...employeeStats].sort((a, b) =>
        sortDesc
          ? b.active_leads - a.active_leads
          : a.active_leads - b.active_leads,
      ),
    [employeeStats, sortDesc],
  )

  // Bar chart data with formatted day labels
  const barData = useMemo(
    () => chartData.map((d) => ({ ...d, day: formatDayLabel(d.day) })),
    [chartData],
  )

  // Donut slices filtered by toggle
  const visibleStatuses = showDonutExtra
    ? [...DEFAULT_STATUSES, ...EXTRA_STATUSES]
    : DEFAULT_STATUSES

  const donutData = statusDist
    .filter((s) => visibleStatuses.includes(s.status))
    .map((s) => ({ name: s.status, value: s.lead_count }))

  const totalLeads = statusDist.reduce((sum, s) => sum + s.lead_count, 0)

  return (
    <div className="space-y-5">
      {/* Header */}
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <p className="eyebrow">Sales</p>
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            Performance
          </h1>
          <p className="text-[13.5px] text-ink-2">
            Team metrics — {totalLeads} total leads
          </p>
        </div>

        {/* Date range filter */}
        <div className="inline-flex gap-0.5 rounded-[10px] border border-line bg-mist p-[3px]">
          {(['1', '7', '30'] as const).map((r) => (
            <button
              key={r}
              onClick={() => router.push(`/performance?range=${r}`)}
              className={
                initialRange === r
                  ? 'rounded-[8px] bg-paper px-3.5 py-[5px] text-[12.5px] font-semibold text-ink shadow-[0_1px_3px_rgba(0,0,0,.08)]'
                  : 'rounded-[8px] px-3.5 py-[5px] text-[12.5px] font-medium text-ink-2 transition hover:text-ink'
              }
            >
              {RANGE_LABELS[r]}
            </button>
          ))}
        </div>
      </div>

      <TabStrip />

      {/* Charts row */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
        {/* 14-day bar chart — spans 3 cols on lg */}
        <div className="rounded-[14px] border border-line bg-paper p-6 shadow-[var(--shadow)] lg:col-span-3">
          <div className="mb-4">
            <p className="text-[13.5px] font-semibold">Pipeline Activity — Last 14 Days</p>
            <p className="text-xs text-ink-2">
              New leads + status changes per day (not affected by date filter)
            </p>
          </div>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={barData} barSize={10} barGap={2}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis
                dataKey="day"
                tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }}
                axisLine={false}
                tickLine={false}
              />
              <YAxis
                allowDecimals={false}
                tick={{ fontSize: 11, fill: 'hsl(var(--muted-foreground))' }}
                axisLine={false}
                tickLine={false}
                width={28}
              />
              <Tooltip
                contentStyle={{
                  background: 'hsl(var(--card))',
                  border: '1px solid hsl(var(--border))',
                  borderRadius: '8px',
                  fontSize: 12,
                }}
              />
              <Legend
                wrapperStyle={{ fontSize: 12 }}
                formatter={(v) =>
                  v === 'new_leads' ? 'New Leads' : 'Status Changes'
                }
              />
              <Bar dataKey="new_leads" fill="#132A21" radius={[3, 3, 0, 0]} />
              <Bar
                dataKey="status_changes"
                fill="#C9A354"
                radius={[3, 3, 0, 0]}
              />
            </BarChart>
          </ResponsiveContainer>
        </div>

        {/* Status donut — spans 2 cols on lg */}
        <div className="rounded-[14px] border border-line bg-paper p-6 shadow-[var(--shadow)] lg:col-span-2">
          <div className="mb-4 flex items-center justify-between">
            <div>
              <p className="text-[13.5px] font-semibold">Lead Status Distribution</p>
              <p className="text-xs text-ink-2">Current snapshot</p>
            </div>
            <button
              onClick={() => setShowDonutExtra((v) => !v)}
              className="rounded-[8px] border border-line-2 px-2.5 py-1 text-xs font-medium text-ink-2 transition hover:bg-mist hover:text-ink"
            >
              {showDonutExtra ? 'Hide Dead/Sold/Future' : 'Show All'}
            </button>
          </div>

          <ResponsiveContainer width="100%" height={200}>
            <PieChart>
              <Pie
                data={donutData}
                dataKey="value"
                nameKey="name"
                cx="50%"
                cy="50%"
                innerRadius="55%"
                outerRadius="80%"
                paddingAngle={2}
              >
                {donutData.map((entry) => (
                  <Cell
                    key={entry.name}
                    fill={STATUS_COLORS[entry.name] ?? '#94a3b8'}
                  />
                ))}
              </Pie>
              <Tooltip
                contentStyle={{
                  background: 'hsl(var(--card))',
                  border: '1px solid hsl(var(--border))',
                  borderRadius: '8px',
                  fontSize: 12,
                }}
                formatter={(value, name) => [
                  value,
                  String(name).charAt(0).toUpperCase() + String(name).slice(1),
                ]}
              />
            </PieChart>
          </ResponsiveContainer>

          {/* Legend */}
          <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1">
            {donutData.map((s) => (
              <div key={s.name} className="flex items-center gap-1.5">
                <span
                  className="inline-block h-2.5 w-2.5 rounded-full"
                  style={{ background: STATUS_COLORS[s.name] ?? '#94a3b8' }}
                />
                <span className="text-xs text-muted-foreground capitalize">
                  {s.name}
                </span>
                <span className="text-xs font-medium">{s.value}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Employee table */}
      <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
        <div className="flex items-center justify-between border-b border-line px-5 py-3.5">
          <p className="text-[13.5px] font-semibold">
            Employee Performance
            <span className="ml-2 text-xs font-normal text-ink-2">
              ({employeeStats.length} active · click a row for their leads)
            </span>
          </p>
          <button
            onClick={() => setShowExtra((v) => !v)}
            className="rounded-[8px] border border-line-2 px-2.5 py-1 text-xs font-medium text-ink-2 transition hover:bg-mist hover:text-ink"
          >
            {showExtra ? 'Hide Dead/Sold/Future' : 'More columns'}
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-line text-left">
                <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
                  Name
                </th>
                <th
                  className="cursor-pointer select-none px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3 hover:text-ink"
                  onClick={() => setSortDesc((v) => !v)}
                >
                  Active {sortDesc ? '↓' : '↑'}
                </th>
                <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-warm">
                  Warm
                </th>
                <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-cold">
                  Cold
                </th>
                <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-hot">Hot</th>
                {showExtra && (
                  <>
                    <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
                      Dead
                    </th>
                    <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-sold">
                      Sold
                    </th>
                    <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-future">
                      Future
                    </th>
                  </>
                )}
                <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3 whitespace-nowrap">
                  Done ({p_days}d)
                </th>
                <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3 whitespace-nowrap">
                  Missed ({p_days}d)
                </th>
                <th className="px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-ink-3">
                  Conv%
                </th>
              </tr>
            </thead>
            <tbody>
              {sortedStats.length === 0 ? (
                <tr>
                  <td
                    colSpan={showExtra ? 11 : 8}
                    className="px-4 py-8 text-center text-muted-foreground"
                  >
                    No active employees found.
                  </td>
                </tr>
              ) : (
                sortedStats.map((emp) => (
                  <tr
                    key={emp.employee_id}
                    className="border-b last:border-0 cursor-pointer hover:bg-muted/50 transition"
                    onClick={() =>
                      router.push(`/leads?employee=${emp.employee_id}`)
                    }
                  >
                    <td className="px-4 py-3 font-medium max-w-[160px] truncate">
                      {emp.employee_name}
                    </td>
                    <td className="px-4 py-3 tabular-nums">
                      {emp.active_leads}
                    </td>
                    <td className="px-4 py-3 tabular-nums text-warm">
                      {emp.warm_count}
                    </td>
                    <td className="px-4 py-3 tabular-nums text-cold">
                      {emp.cold_count}
                    </td>
                    <td className="px-4 py-3 tabular-nums text-hot">
                      {emp.hot_count}
                    </td>
                    {showExtra && (
                      <>
                        <td className="px-4 py-3 tabular-nums text-ink-2">
                          {emp.dead_count}
                        </td>
                        <td className="px-4 py-3 tabular-nums text-sold">
                          {emp.sold_count}
                        </td>
                        <td className="px-4 py-3 tabular-nums text-future">
                          {emp.future_count}
                        </td>
                      </>
                    )}
                    <td className="px-4 py-3 tabular-nums">
                      {emp.followups_completed}
                    </td>
                    <td className="px-4 py-3 tabular-nums">
                      {emp.followups_missed > 0 ? (
                        <span className="text-hot">
                          {emp.followups_missed}
                        </span>
                      ) : (
                        emp.followups_missed
                      )}
                    </td>
                    <td className="px-4 py-3 tabular-nums">
                      {emp.conversion_rate !== null &&
                      emp.conversion_rate !== undefined
                        ? `${emp.conversion_rate}%`
                        : '—'}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
