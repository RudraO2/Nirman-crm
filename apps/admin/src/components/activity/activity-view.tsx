'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { cn } from '@/lib/utils'
import { TabStrip } from '@/components/tab-strip'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

export type ActivityRow = {
  employee_id: string
  employee_name: string
  last_action_at: string | null
  leads_updated_today: number
  followups_completed_today: number
}

function timeAgo(ts: string | null): string {
  if (!ts) return ''
  const diffMs = Date.now() - new Date(ts).getTime()
  const diffMin = Math.floor(diffMs / 60_000)
  if (diffMin < 1) return 'just now'
  if (diffMin < 60) return `${diffMin} min ago`
  const diffHrs = Math.floor(diffMin / 60)
  if (diffHrs < 24) return `${diffHrs} hr${diffHrs === 1 ? '' : 's'} ago`
  const diffDays = Math.floor(diffHrs / 24)
  return `${diffDays}d ago`
}

/** Freshness tint for the last-seen pill (visual threshold only). */
function freshness(ts: string): 'sold' | 'warm' {
  const diffMin = Math.floor((Date.now() - new Date(ts).getTime()) / 60_000)
  return diffMin < 180 ? 'sold' : 'warm'
}

export function ActivityView({ employees }: { employees: ActivityRow[] }) {
  const router = useRouter()

  useEffect(() => {
    const id = setInterval(() => router.refresh(), 60_000)
    return () => clearInterval(id)
  }, [router])

  return (
    <div className="space-y-5">
      <div className="space-y-2">
        <p className="eyebrow">Home</p>
        <div className="flex items-end justify-between gap-4">
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            Activity
          </h1>
          <span className="inline-flex items-center gap-1.5 rounded-full bg-sold-bg px-2.5 py-1 text-xs font-medium text-sold">
            <span className="h-1.5 w-1.5 rounded-full bg-sold" />
            live
          </span>
        </div>
        <p className="text-[13.5px] text-ink-2">
          {employees.length} active {employees.length === 1 ? 'employee' : 'employees'} · Auto-refreshing every minute
        </p>
      </div>

      <TabStrip />

      <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Employee</TableHead>
              <TableHead>Last Action</TableHead>
              <TableHead className="text-right">Leads Updated Today</TableHead>
              <TableHead className="text-right">Follow-ups Done Today</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {employees.length === 0 && (
              <TableRow>
                <TableCell colSpan={4} className="text-center text-ink-3">
                  No active employees.
                </TableCell>
              </TableRow>
            )}
            {employees.map((emp) => (
              <TableRow key={emp.employee_id}>
                <TableCell className="font-medium">{emp.employee_name}</TableCell>
                <TableCell>
                  {emp.last_action_at ? (
                    <span
                      title={new Date(emp.last_action_at).toLocaleString()}
                      className={cn(
                        'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                        freshness(emp.last_action_at) === 'sold'
                          ? 'bg-sold-bg text-sold'
                          : 'bg-warm-bg text-warm',
                      )}
                    >
                      {timeAgo(emp.last_action_at)}
                    </span>
                  ) : (
                    <span className="text-ink-3 italic">No activity yet</span>
                  )}
                </TableCell>
                <TableCell className="text-right tabular-nums">{emp.leads_updated_today}</TableCell>
                <TableCell className="text-right tabular-nums">{emp.followups_completed_today}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
