'use client'

import { useState, useMemo, useRef, useEffect, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { Search, TriangleAlert } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { StatusPill } from '@/components/status-pill'
import { TenantDetailSheet } from '@/components/tenant-detail-sheet'
import { cn } from '@/lib/utils'
import { relativeDays, rowUrgency, rpcErrorMessage } from '@/lib/format'
import type { OpsTenant, Plan } from '@/lib/types'
import { toast } from 'sonner'

const URGENCY_BORDER: Record<string, string> = {
  overdue: 'border-l-2 border-l-st-suspended',
  expiring: 'border-l-2 border-l-st-grace',
  none: 'border-l-2 border-l-transparent',
}

export function TenantConsole({
  initialTenants,
  plans,
  loadError,
}: {
  initialTenants: OpsTenant[]
  plans: Plan[]
  loadError: string | null
}) {
  const router = useRouter()
  const [tenants, setTenants] = useState<OpsTenant[]>(initialTenants)
  const [query, setQuery] = useState('')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const searchRef = useRef<HTMLInputElement>(null)

  // Keep local list in sync when the server component re-fetches (router.refresh).
  useEffect(() => setTenants(initialTenants), [initialTenants])

  // ⌘K / Ctrl-K focuses the filter (command-palette affordance).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        searchRef.current?.focus()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return tenants
    return tenants.filter(
      (t) =>
        t.name.toLowerCase().includes(q) ||
        (t.plan_name ?? '').toLowerCase().includes(q) ||
        t.status.toLowerCase().includes(q),
    )
  }, [tenants, query])

  const selected = useMemo(
    () => tenants.find((t) => t.tenant_id === selectedId) ?? null,
    [tenants, selectedId],
  )

  // After any mutation: re-fetch the list client-side (immediate) + refresh the
  // server component (keeps SSR props authoritative). Derives fresh `selected`.
  const refresh = useCallback(async () => {
    const supabase = createClient()
    const { data, error } = await supabase.rpc('ops_list_tenants')
    if (!error && data) setTenants(data as OpsTenant[])
    else if (error) toast.error(rpcErrorMessage(error))
    router.refresh()
  }, [router])

  return (
    <div className="flex min-h-screen flex-col">
      {/* Header + filter */}
      <header className="sticky top-0 z-10 border-b border-border bg-background/90 px-6 py-3.5 backdrop-blur-sm">
        <div className="flex items-center justify-between gap-4">
          <div>
            <h1 className="text-[17px] font-semibold">Tenants</h1>
            <p className="text-xs text-muted-foreground">
              {tenants.length} total · soonest-to-lapse first
            </p>
          </div>
          <div className="relative w-[300px]">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
            <input
              ref={searchRef}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Filter name, plan, status…"
              className="h-8 w-full rounded-[8px] border border-input bg-card pl-8 pr-12 text-sm text-foreground outline-none placeholder:text-muted-foreground focus:border-ring focus:ring-3 focus:ring-ring/30"
            />
            <kbd className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 rounded border border-border bg-muted px-1.5 py-0.5 font-mono text-[10px] text-muted-foreground">
              ⌘K
            </kbd>
          </div>
        </div>
      </header>

      <div className="flex-1 px-6 py-5">
        {loadError ? (
          <ErrorState message={rpcErrorMessage({ message: loadError })} />
        ) : tenants.length === 0 ? (
          <EmptyState />
        ) : (
          <div className="overflow-hidden rounded-[11px] border border-border bg-card">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead className="pl-4">Builder</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Plan</TableHead>
                  <TableHead className="text-right">Paid until</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((t) => {
                  const urgency = rowUrgency(t.days_remaining)
                  return (
                    <TableRow
                      key={t.tenant_id}
                      tabIndex={0}
                      onClick={() => setSelectedId(t.tenant_id)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') setSelectedId(t.tenant_id)
                      }}
                      className={cn(
                        'cursor-pointer outline-none focus-visible:bg-accent',
                        URGENCY_BORDER[urgency],
                      )}
                    >
                      <TableCell className="pl-4 font-medium text-foreground">{t.name}</TableCell>
                      <TableCell>
                        <StatusPill status={t.status} days={t.days_remaining} />
                      </TableCell>
                      <TableCell className="text-muted-foreground">{t.plan_name ?? '—'}</TableCell>
                      <TableCell
                        className={cn(
                          'text-right font-mono text-[12px] tabular-nums',
                          urgency === 'overdue'
                            ? 'text-st-suspended'
                            : urgency === 'expiring'
                              ? 'text-st-grace'
                              : 'text-muted-foreground',
                        )}
                      >
                        {relativeDays(t.days_remaining)}
                      </TableCell>
                    </TableRow>
                  )
                })}
                {filtered.length === 0 && (
                  <TableRow className="hover:bg-transparent">
                    <TableCell colSpan={4} className="py-8 text-center text-sm text-muted-foreground">
                      No tenants match “{query}”.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        )}
      </div>

      <TenantDetailSheet
        tenant={selected}
        plans={plans}
        open={selectedId !== null}
        onOpenChange={(o) => { if (!o) setSelectedId(null) }}
        onMutated={refresh}
      />
    </div>
  )
}

function EmptyState() {
  return (
    <div className="grid place-items-center rounded-[11px] border border-dashed border-border py-20 text-center">
      <div>
        <p className="text-sm font-medium">No tenants yet</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Provisioning is a separate story — this console operates on existing tenants.
        </p>
      </div>
    </div>
  )
}

function ErrorState({ message }: { message: string }) {
  return (
    <div className="flex items-start gap-3 rounded-[11px] border border-destructive/40 bg-destructive/10 px-4 py-3.5">
      <TriangleAlert className="mt-0.5 size-4 flex-shrink-0 text-destructive" />
      <div>
        <p className="text-sm font-medium text-destructive">Could not load tenants</p>
        <p className="mt-0.5 text-xs text-muted-foreground">{message}</p>
      </div>
    </div>
  )
}
