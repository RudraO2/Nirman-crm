"use client"
import { useCallback, useEffect, useMemo, useState, useTransition } from 'react'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { Label } from '@/components/ui/label'
import { TabStrip } from '@/components/tab-strip'
import type { OrgUser } from './page'

type AmStatus = 'requested' | 'acknowledged' | 'in_progress' | 'done' | 'rejected'

interface Amendment {
  amendment_id: string
  unit_id: string
  unit_no: string
  configuration: string | null
  lead_id: string
  description: string
  status: AmStatus
  created_at: string
  updated_at: string
}

const ALL = '__all__'
const STATUS_ORDER: AmStatus[] = ['requested', 'acknowledged', 'in_progress', 'done', 'rejected']

// status pill colors → §3 palette
const PILL: Record<AmStatus, { bg: string; fg: string; label: string }> = {
  requested:    { bg: 'var(--warm-bg)',   fg: 'var(--warm)',  label: 'Requested' },
  acknowledged: { bg: 'var(--cold-bg)',   fg: 'var(--cold)',  label: 'Acknowledged' },
  in_progress:  { bg: 'var(--brass-soft)', fg: '#6E5423',     label: 'In progress' },
  done:         { bg: 'var(--sold-bg)',   fg: 'var(--sold)',  label: 'Done' },
  rejected:     { bg: 'var(--mist)',      fg: 'var(--ink-3)', label: 'Rejected' },
}

// valid forward transitions (mirrors set_amendment_status lifecycle)
const NEXT: Record<AmStatus, { to: AmStatus; label: string; destructive?: boolean }[]> = {
  requested:    [{ to: 'acknowledged', label: 'Acknowledge' }, { to: 'rejected', label: 'Reject', destructive: true }],
  acknowledged: [{ to: 'in_progress', label: 'Start' }, { to: 'rejected', label: 'Reject', destructive: true }],
  in_progress:  [{ to: 'done', label: 'Mark done' }, { to: 'rejected', label: 'Reject', destructive: true }],
  done:         [],
  rejected:     [],
}

function StatusPill({ status }: { status: AmStatus }) {
  const p = PILL[status]
  return (
    <span
      className="inline-block rounded-full px-3 py-1 text-xs font-medium"
      style={{
        background: p.bg, color: p.fg,
        border: status === 'rejected' ? '1px dashed var(--line)' : undefined,
      }}
    >
      {p.label}
    </span>
  )
}

export function AmendmentsClient({
  currentUserId, users, initialTeamIds,
}: {
  currentUserId: string
  users: OrgUser[]
  initialTeamIds: string[]
}) {
  const [teamIds, setTeamIds] = useState<string[]>(initialTeamIds)
  const [statusFilter, setStatusFilter] = useState<string>(ALL)
  const [amendments, setAmendments] = useState<Amendment[]>([])
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [addUserId, setAddUserId] = useState<string>('')
  const [pending, startTransition] = useTransition()

  const isMember = teamIds.includes(currentUserId)
  const userName = useCallback((id: string) => users.find((u) => u.id === id)?.email_or_username ?? id, [users])

  const load = useCallback(async () => {
    if (!isMember) { setAmendments([]); return }
    setLoading(true); setLoadError(null)
    const supabase = createClient()
    const { data, error } = await supabase.rpc('get_amendments_for_execution', {
      p_status: statusFilter === ALL ? null : statusFilter,
    })
    if (error) { setLoadError(error.message); setLoading(false); return }
    setAmendments((data ?? []) as Amendment[])
    setLoading(false)
  }, [isMember, statusFilter])

  useEffect(() => { load() }, [load])

  function setStatus(a: Amendment, to: AmStatus) {
    startTransition(async () => {
      const supabase = createClient()
      const { error } = await supabase.rpc('set_amendment_status', {
        p_amendment_id: a.amendment_id,
        p_new_status: to,
      })
      if (error) { toast.error(error.message); return }
      toast.success(`Unit ${a.unit_no} → ${PILL[to].label}`)
      load()
    })
  }

  function addMember(userId: string) {
    startTransition(async () => {
      const supabase = createClient()
      const { error } = await supabase.rpc('add_execution_member', { p_user_id: userId })
      if (error) { toast.error(error.message); return }
      setTeamIds((prev) => prev.includes(userId) ? prev : [...prev, userId])
      setAddUserId('')
      toast.success(`${userName(userId)} added to execution team`)
    })
  }

  function removeMember(userId: string) {
    startTransition(async () => {
      const supabase = createClient()
      const { error } = await supabase.rpc('remove_execution_member', { p_user_id: userId })
      if (error) { toast.error(error.message); return }
      setTeamIds((prev) => prev.filter((id) => id !== userId))
      toast.success(`${userName(userId)} removed`)
    })
  }

  const nonMembers = useMemo(() => users.filter((u) => !teamIds.includes(u.id)), [users, teamIds])

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <p className="eyebrow">Builder Ops</p>
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            Amendments
          </h1>
          <p className="text-[13.5px] text-ink-2">Client modification requests · execution queue</p>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="a-status" className="text-xs">Status</Label>
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger id="a-status" className="w-44"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All statuses</SelectItem>
              {STATUS_ORDER.map((s) => <SelectItem key={s} value={s}>{PILL[s].label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
      </div>

      <TabStrip />

      {/* Execution team committee — brass-tinted banner (§5.7) */}
      <div className="rounded-[14px] border border-brass-soft bg-brass-soft/40 p-4 space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold">Execution team</h2>
          <div className="flex items-end gap-2">
            <Select value={addUserId} onValueChange={setAddUserId}>
              <SelectTrigger className="w-56"><SelectValue placeholder="Add member…" /></SelectTrigger>
              <SelectContent>
                {nonMembers.length === 0
                  ? <SelectItem value="__none" disabled>Everyone is a member</SelectItem>
                  : nonMembers.map((u) => <SelectItem key={u.id} value={u.id}>{u.email_or_username}</SelectItem>)}
              </SelectContent>
            </Select>
            <Button size="sm" disabled={!addUserId || pending} onClick={() => addMember(addUserId)}>Add</Button>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {teamIds.length === 0 && <span className="text-sm text-ink-2">No members yet.</span>}
          {teamIds.map((id) => (
            <span key={id} className="inline-flex items-center gap-2 rounded-full border border-line-2 bg-paper px-3 py-1 text-sm">
              {userName(id)}{id === currentUserId && <span className="text-xs text-ink-3">(you)</span>}
              <button
                onClick={() => removeMember(id)}
                disabled={pending}
                className="text-ink-3 hover:text-danger"
                aria-label="Remove"
              >×</button>
            </span>
          ))}
        </div>
      </div>

      {!isMember ? (
        <div className="rounded-[14px] border border-dashed border-line-2 p-10 text-center space-y-3">
          <p className="text-ink-2">
            The amendment queue is visible to execution-team members only. Add yourself to view and manage it.
          </p>
          <Button size="sm" disabled={pending || !currentUserId} onClick={() => addMember(currentUserId)}>
            Add me to the execution team
          </Button>
        </div>
      ) : (
        <>
          {loadError && <p className="text-danger text-sm">Failed to load: {loadError}</p>}
          <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Unit</TableHead>
                  <TableHead>Config</TableHead>
                  <TableHead>Request</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {amendments.map((a) => (
                  <TableRow key={a.amendment_id}>
                    <TableCell className="font-medium tabular-nums">{a.unit_no}</TableCell>
                    <TableCell className="text-muted-foreground">{a.configuration ?? '—'}</TableCell>
                    <TableCell className="max-w-md">{a.description}</TableCell>
                    <TableCell><StatusPill status={a.status} /></TableCell>
                    <TableCell className="text-right space-x-2 whitespace-nowrap">
                      {NEXT[a.status].length === 0
                        ? <span className="text-xs text-muted-foreground">—</span>
                        : NEXT[a.status].map((n) => (
                            <Button
                              key={n.to}
                              size="sm"
                              variant={n.destructive ? 'outline' : 'default'}
                              disabled={pending}
                              onClick={() => setStatus(a, n.to)}
                            >
                              {n.label}
                            </Button>
                          ))}
                    </TableCell>
                  </TableRow>
                ))}
                {amendments.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={5} className="text-center text-muted-foreground py-8">
                      {loading ? 'Loading…' : 'No amendments.'}
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </>
      )}
    </div>
  )
}
