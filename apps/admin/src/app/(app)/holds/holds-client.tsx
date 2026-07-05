"use client"
import { useCallback, useEffect, useMemo, useState, useTransition } from 'react'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { Label } from '@/components/ui/label'
import { cn } from '@/lib/utils'
import { TabStrip } from '@/components/tab-strip'
import type { HoldsProjectRow } from './page'

interface ActiveHold {
  hold_id: string
  unit_id: string
  unit_no: string
  project_id: string
  lead_id: string
  lead_name: string | null
  holding_agent_id: string
  agent_name: string | null
  held_at: string
  expires_at: string
  seconds_to_expiry: number
}

interface BookingStats {
  confirmed_bookings: number
  active_holds: number
  total_holds: number
  conversion_pct: number | null
}

const ALL_PROJECTS = '__all__'

function fmtCountdown(secs: number): string {
  if (secs <= 0) return 'Expired'
  const h = Math.floor(secs / 3600)
  const m = Math.floor((secs % 3600) / 60)
  const s = Math.floor(secs % 60)
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m ${s}s`
  return `${s}s`
}

// ── Confirm-booking dialog ───────────────────────────────────────────────────
function ConfirmDialog({ hold, onClose, onDone }: { hold: ActiveHold | null; onClose: () => void; onDone: () => void }) {
  const [verified, setVerified] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  useEffect(() => { setVerified(false); setError(null) }, [hold])
  if (!hold) return null

  function submit() {
    if (!hold) return
    setError(null)
    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('confirm_booking', {
        p_hold_id: hold.hold_id,
        p_payment_verified: verified,
      })
      if (rpcErr) { setError(rpcErr.message); return }
      toast.success(`Unit ${hold.unit_no} booked — sold! 🎉`)
      onDone()
    })
  }

  return (
    <Dialog open={!!hold} onOpenChange={(v) => { if (!v) onClose() }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">Confirm booking · Unit {hold.unit_no}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <p className="text-sm text-muted-foreground">
            Lead <span className="font-medium text-foreground">{hold.lead_name ?? '—'}</span> ·
            agent <span className="font-medium text-foreground">{hold.agent_name ?? '—'}</span>.
            Confirming marks the unit <span className="font-medium text-foreground">sold</span> and closes the lead.
          </p>
          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={verified}
              onChange={(e) => setVerified(e.target.checked)}
              className="size-4 rounded border-input cursor-pointer"
            />
            <span className="text-sm">Payment verified by reception</span>
          </label>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={pending}>Cancel</Button>
          <Button onClick={submit} disabled={pending || !verified}>
            {pending ? 'Confirming…' : 'Confirm booking'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Main ─────────────────────────────────────────────────────────────────────
export function HoldsClient({ projects }: { projects: HoldsProjectRow[] }) {
  const [projectId, setProjectId] = useState<string>(ALL_PROJECTS)
  const [period, setPeriod] = useState('30')
  const [holds, setHolds] = useState<ActiveHold[]>([])
  const [stats, setStats] = useState<BookingStats | null>(null)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [confirming, setConfirming] = useState<ActiveHold | null>(null)
  const [now, setNow] = useState(() => Date.now())
  const [releasing, startRelease] = useTransition()

  const load = useCallback(async () => {
    setLoading(true); setLoadError(null)
    const supabase = createClient()
    const pid = projectId === ALL_PROJECTS ? null : projectId
    const [holdsRes, statsRes] = await Promise.all([
      supabase.rpc('get_active_holds', { p_project_id: pid, p_agent_id: null }),
      supabase.rpc('get_booking_stats', { p_period_days: parseInt(period, 10), p_project_id: pid }),
    ])
    if (holdsRes.error) { setLoadError(holdsRes.error.message); setLoading(false); return }
    setHolds((holdsRes.data ?? []) as ActiveHold[])
    setStats(((statsRes.data ?? [])[0] ?? null) as BookingStats | null)
    setNow(Date.now())
    setLoading(false)
  }, [projectId, period])

  useEffect(() => { load() }, [load])

  // 1s ticker drives the live countdown
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(t)
  }, [])

  function remaining(h: ActiveHold): number {
    return Math.max(0, Math.round((Date.parse(h.expires_at) - now) / 1000))
  }

  function forceRelease(h: ActiveHold) {
    startRelease(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('change_unit_inventory_state', {
        p_unit_id: h.unit_id,
        p_action: 'force_release',
        p_expected_version: null,
      })
      if (rpcErr) { toast.error(rpcErr.message); return }
      toast.success(`Hold on unit ${h.unit_no} released`)
      load()
    })
  }

  const statCards = useMemo(() => ([
    { label: 'Active holds', value: stats?.active_holds ?? 0 },
    { label: 'Confirmed bookings', value: stats?.confirmed_bookings ?? 0, ref: `last ${period} days` },
    { label: 'Conversion', value: stats?.conversion_pct != null ? `${stats.conversion_pct}%` : '—', ref: 'hold → sold' },
  ]), [stats, period])

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <p className="eyebrow">Builder Ops</p>
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            Holds &amp; Bookings
          </h1>
          <p className="text-[13.5px] text-ink-2">Live holds with countdown · confirm or release</p>
        </div>
        <div className="flex items-end gap-2">
          <div className="space-y-1.5">
            <Label htmlFor="h-proj" className="text-xs">Project</Label>
            <Select value={projectId} onValueChange={setProjectId}>
              <SelectTrigger id="h-proj" className="w-48"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL_PROJECTS}>All projects</SelectItem>
                {projects.map((p) => <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="h-period" className="text-xs">Period</Label>
            <Select value={period} onValueChange={setPeriod}>
              <SelectTrigger id="h-period" className="w-28"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="7">7 days</SelectItem>
                <SelectItem value="30">30 days</SelectItem>
                <SelectItem value="90">90 days</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
      </div>

      <TabStrip />

      {/* Stat cards */}
      <div className="grid grid-cols-1 gap-3.5 sm:grid-cols-3">
        {statCards.map((c) => (
          <div key={c.label} className="rounded-[14px] border border-line bg-paper p-5 shadow-[var(--shadow)]">
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-ink-2">
              {c.label}{c.ref ? <span className="font-normal normal-case tracking-normal text-ink-3"> · {c.ref}</span> : null}
            </p>
            <div className="mt-1.5 font-serif text-[30px] font-medium leading-none tabular-nums text-ink">
              {c.value}
            </div>
          </div>
        ))}
      </div>

      {loadError && <p className="text-danger text-sm">Failed to load: {loadError}</p>}

      <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Unit</TableHead>
              <TableHead>Lead</TableHead>
              <TableHead>Agent</TableHead>
              <TableHead>Expires in</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {holds.map((h) => {
              const secs = remaining(h)
              // Visual expiry threshold (§5.7): <4h hot, <12h warm, else sold, expired dead.
              const tone = secs <= 0 ? 'bg-dead-bg text-dead'
                : secs < 14400 ? 'bg-hot-bg text-hot'
                : secs < 43200 ? 'bg-warm-bg text-warm'
                : 'bg-sold-bg text-sold'
              return (
                <TableRow key={h.hold_id}>
                  <TableCell className="font-medium tabular-nums">{h.unit_no}</TableCell>
                  <TableCell>{h.lead_name ?? '—'}</TableCell>
                  <TableCell className="text-ink-2">{h.agent_name ?? '—'}</TableCell>
                  <TableCell>
                    <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold tabular-nums', tone)}>
                      {fmtCountdown(secs)}
                    </span>
                  </TableCell>
                  <TableCell className="text-right space-x-2">
                    <Button size="sm" onClick={() => setConfirming(h)} disabled={releasing}>Confirm</Button>
                    <Button size="sm" variant="outline" onClick={() => forceRelease(h)} disabled={releasing}>
                      Release
                    </Button>
                  </TableCell>
                </TableRow>
              )
            })}
            {holds.length === 0 && (
              <TableRow>
                <TableCell colSpan={5} className="text-center text-muted-foreground py-8">
                  {loading ? 'Loading…' : 'No active holds.'}
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <ConfirmDialog
        hold={confirming}
        onClose={() => setConfirming(null)}
        onDone={() => { setConfirming(null); load() }}
      />
    </div>
  )
}
