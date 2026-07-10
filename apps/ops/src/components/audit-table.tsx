'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { fmtDateTime, rpcErrorMessage } from '@/lib/format'
import type { OpsAuditRow } from '@/lib/types'
import { toast } from 'sonner'

const ACTION_TONE: Record<string, string> = {
  renew_tenant: 'text-st-active',
  reactivate_tenant: 'text-st-trial',
  suspend_tenant: 'text-st-suspended',
}

export function AuditTable({
  initialRows,
  loadError,
  pageSize,
}: {
  initialRows: OpsAuditRow[]
  loadError: string | null
  pageSize: number
}) {
  const [rows, setRows] = useState<OpsAuditRow[]>(initialRows)
  const [loading, setLoading] = useState(false)
  const [done, setDone] = useState(initialRows.length < pageSize)

  async function loadMore() {
    setLoading(true)
    const supabase = createClient()
    const { data, error } = await supabase.rpc('ops_list_audit', {
      p_limit: pageSize,
      p_offset: rows.length,
    })
    setLoading(false)
    if (error) {
      toast.error(rpcErrorMessage(error))
      return
    }
    const next = (data ?? []) as OpsAuditRow[]
    setRows((r) => [...r, ...next])
    if (next.length < pageSize) setDone(true)
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="sticky top-0 z-10 border-b border-border bg-background/90 px-6 py-3.5 backdrop-blur-sm">
        <h1 className="text-[17px] font-semibold">Audit log</h1>
        <p className="text-xs text-muted-foreground">Immutable · newest first · read-only</p>
      </header>

      <div className="flex-1 px-6 py-5">
        {loadError ? (
          <p className="rounded-[11px] border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
            {rpcErrorMessage({ message: loadError })}
          </p>
        ) : rows.length === 0 ? (
          <div className="grid place-items-center rounded-[11px] border border-dashed border-border py-20 text-center text-sm text-muted-foreground">
            No audit entries yet.
          </div>
        ) : (
          <div className="overflow-hidden rounded-[11px] border border-border bg-card font-mono text-[12px]">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead className="pl-4">When</TableHead>
                  <TableHead>Action</TableHead>
                  <TableHead>Target</TableHead>
                  <TableHead>Actor</TableHead>
                  <TableHead>Detail</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((r) => (
                  <TableRow key={r.id} className="hover:bg-accent/40">
                    <TableCell className="pl-4 whitespace-nowrap text-muted-foreground">
                      {fmtDateTime(r.created_at)}
                    </TableCell>
                    <TableCell className={ACTION_TONE[r.action] ?? 'text-foreground'}>
                      {r.action}
                    </TableCell>
                    <TableCell
                      className="text-muted-foreground"
                      title={r.target_tenant_id ?? undefined}
                    >
                      {r.target_tenant_id ? r.target_tenant_id.slice(0, 8) : '—'}
                    </TableCell>
                    <TableCell
                      className="text-muted-foreground"
                      title={r.actor_user_id ?? undefined}
                    >
                      {r.actor_user_id ? r.actor_user_id.slice(0, 8) : '—'}
                    </TableCell>
                    <TableCell className="max-w-[420px] truncate text-foreground/70" title={JSON.stringify(r.detail)}>
                      {r.detail ? JSON.stringify(r.detail) : '—'}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            <div className="flex items-center justify-between border-t border-border px-4 py-2.5">
              <span className="text-[11px] text-muted-foreground">{rows.length} entries</span>
              {!done && (
                <Button size="sm" variant="outline" onClick={loadMore} disabled={loading}>
                  {loading ? 'Loading…' : 'Load more'}
                </Button>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
