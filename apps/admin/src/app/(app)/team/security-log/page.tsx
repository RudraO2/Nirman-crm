import { createClient } from '@/lib/supabase/server'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

export default async function SecurityLogPage() {
  const supabase = await createClient()
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()

  const { data: attempts } = await supabase
    .from('auth_failed_attempts')
    .select('id, user_id, attempted_at, ip_address, outcome')
    .neq('outcome', 'success')
    .gte('attempted_at', since)
    .order('attempted_at', { ascending: false })
    .limit(100)

  return (
    <div className="p-6 space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Security Log</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Failed login attempts — last 24 hours (max 100)
        </p>
      </div>

      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Time</TableHead>
            <TableHead>Outcome</TableHead>
            <TableHead>User ID</TableHead>
            <TableHead>IP Address</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {(attempts ?? []).map((row) => (
            <TableRow key={row.id}>
              <TableCell className="text-sm">
                {new Date(row.attempted_at).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}
              </TableCell>
              <TableCell>
                <span
                  className={
                    row.outcome === 'locked'
                      ? 'text-destructive font-medium'
                      : 'text-muted-foreground'
                  }
                >
                  {row.outcome.replace(/_/g, ' ')}
                </span>
              </TableCell>
              <TableCell className="font-mono text-xs">
                {row.user_id ?? 'unknown'}
              </TableCell>
              <TableCell className="text-sm">{row.ip_address ?? '—'}</TableCell>
            </TableRow>
          ))}
          {(attempts ?? []).length === 0 && (
            <TableRow>
              <TableCell colSpan={4} className="text-center text-muted-foreground py-8">
                No failed attempts in the last 24 hours.
              </TableCell>
            </TableRow>
          )}
        </TableBody>
      </Table>
    </div>
  )
}
