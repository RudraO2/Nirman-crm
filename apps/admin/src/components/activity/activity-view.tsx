'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
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

export function ActivityView({ employees }: { employees: ActivityRow[] }) {
  const router = useRouter()

  useEffect(() => {
    const id = setInterval(() => router.refresh(), 60_000)
    return () => clearInterval(id)
  }, [router])

  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Activity</h1>
        <p className="text-sm text-muted-foreground">
          {employees.length} active {employees.length === 1 ? 'employee' : 'employees'} · Auto-refreshing every minute
        </p>
      </div>

      <div className="rounded-lg border bg-card">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Employee</TableHead>
              <TableHead>Last Action</TableHead>
              <TableHead>Leads Updated Today</TableHead>
              <TableHead>Follow-ups Done Today</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {employees.length === 0 && (
              <TableRow>
                <TableCell colSpan={4} className="text-center text-muted-foreground">
                  No active employees.
                </TableCell>
              </TableRow>
            )}
            {employees.map((emp) => (
              <TableRow key={emp.employee_id}>
                <TableCell className="font-medium">{emp.employee_name}</TableCell>
                <TableCell>
                  {emp.last_action_at ? (
                    <span title={new Date(emp.last_action_at).toLocaleString()}>
                      {timeAgo(emp.last_action_at)}
                    </span>
                  ) : (
                    <span className="text-muted-foreground">No activity yet</span>
                  )}
                </TableCell>
                <TableCell>{emp.leads_updated_today}</TableCell>
                <TableCell>{emp.followups_completed_today}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
