"use client"
import { useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { TabStrip } from '@/components/tab-strip'
import type { HierUser, Agency } from './page'

type Tier = 'super_admin' | 'builder_head' | 'team_leader' | 'front_line_rep' | 'partner_agency' | 'receptionist'

const NONE = '__none__'
const TIERS: Tier[] = ['super_admin', 'builder_head', 'team_leader', 'front_line_rep', 'partner_agency', 'receptionist']
const TIER_LABEL: Record<Tier, string> = {
  super_admin: 'Super Admin', builder_head: 'Builder Head', team_leader: 'Team Leader',
  front_line_rep: 'Front-line Rep', partner_agency: 'Partner / Agency', receptionist: 'Reception',
}
const RANK: Record<Tier, number> = {
  super_admin: 4, builder_head: 3, team_leader: 2, front_line_rep: 1, partner_agency: 0, receptionist: 0,
}
const LADDER: Tier[] = ['super_admin', 'builder_head', 'team_leader', 'front_line_rep']
const isLadder = (t: Tier) => LADDER.includes(t)

// §3 tier-pill palette (mockup .t-super / .t-head / .t-lead / .t-rep / .t-agency / .t-recep)
const TIER_PILL: Record<Tier, { bg: string; fg: string; outline?: boolean }> = {
  super_admin:    { bg: 'var(--evergreen)',  fg: 'var(--brass-bright)' },
  builder_head:   { bg: 'var(--brass)',      fg: '#fff' },
  team_leader:    { bg: 'var(--brass-soft)', fg: '#6E5423' },
  front_line_rep: { bg: 'var(--paper)',      fg: 'var(--ink-2)', outline: true },
  partner_agency: { bg: 'var(--cold-bg)',    fg: 'var(--cold)' },
  receptionist:   { bg: 'var(--mist)',       fg: 'var(--ink-3)' },
}

function TierPill({ tier }: { tier: Tier | null }) {
  if (!tier) return <span className="text-ink-3 text-sm">—</span>
  const p = TIER_PILL[tier]
  return (
    <span className="inline-block rounded-full px-[11px] py-[3px] text-[11px] font-semibold"
      style={{ background: p.bg, color: p.fg, border: p.outline ? '1px solid var(--line-2)' : undefined }}>
      {TIER_LABEL[tier]}
    </span>
  )
}

// ── Edit-hierarchy dialog ─────────────────────────────────────────────────────
function EditDialog({
  user, users, agencies, onClose, onSaved,
}: {
  user: HierUser | null
  users: HierUser[]
  agencies: Agency[]
  onClose: () => void
  onSaved: () => void
}) {
  const [tier, setTier] = useState<Tier>((user?.role_tier as Tier) ?? 'front_line_rep')
  const [reportsTo, setReportsTo] = useState<string>(user?.reports_to_user_id ?? NONE)
  const [agencyId, setAgencyId] = useState<string>(user?.agency_id ?? NONE)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  // reset local state when a new user opens
  const [lastId, setLastId] = useState<string | null>(null)
  if (user && user.id !== lastId) {
    setLastId(user.id)
    setTier((user.role_tier as Tier) ?? 'front_line_rep')
    setReportsTo(user.reports_to_user_id ?? NONE)
    setAgencyId(user.agency_id ?? NONE)
    setError(null)
  }

  const ladder = isLadder(tier)
  const isPartner = tier === 'partner_agency'

  // valid managers: internal ladder users, strictly higher rank, not self
  const managerOptions = useMemo(() => {
    if (!user) return []
    return users.filter((u) =>
      u.id !== user.id &&
      u.role_tier && isLadder(u.role_tier as Tier) &&
      RANK[u.role_tier as Tier] > RANK[tier],
    )
  }, [users, user, tier])

  if (!user) return null

  function save() {
    if (!user) return
    setError(null)
    if (isPartner && agencyId === NONE) { setError('Partner / Agency tier needs an agency.'); return }
    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('set_user_hierarchy', {
        p_user_id: user.id,
        p_role_tier: tier,
        p_reports_to: ladder && reportsTo !== NONE ? reportsTo : null,
        p_agency_id: isPartner ? agencyId : null,
      })
      if (rpcErr) { setError(rpcErr.message); return }
      toast.success(`${user.email_or_username} → ${TIER_LABEL[tier]}`)
      onSaved()
    })
  }

  return (
    <Dialog open={!!user} onOpenChange={(v) => { if (!v) onClose() }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">{user.email_or_username}</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="h-tier">Tier</Label>
            <Select value={tier} onValueChange={(v) => setTier(v as Tier)}>
              <SelectTrigger id="h-tier" className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {TIERS.map((t) => <SelectItem key={t} value={t}>{TIER_LABEL[t]}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          {ladder && (
            <div className="space-y-2">
              <Label htmlFor="h-reports">Reports to</Label>
              <Select value={reportsTo} onValueChange={setReportsTo}>
                <SelectTrigger id="h-reports" className="w-full">
                  <SelectValue placeholder="— None (top of tree) —" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={NONE}>— None (top of tree) —</SelectItem>
                  {managerOptions.map((m) => (
                    <SelectItem key={m.id} value={m.id}>
                      {m.email_or_username} · {TIER_LABEL[m.role_tier as Tier]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {managerOptions.length === 0 && (
                <p className="text-xs text-muted-foreground">No higher-tier users to report to yet.</p>
              )}
            </div>
          )}

          {isPartner && (
            <div className="space-y-2">
              <Label htmlFor="h-agency">Agency *</Label>
              <Select value={agencyId} onValueChange={setAgencyId}>
                <SelectTrigger id="h-agency" className="w-full">
                  <SelectValue placeholder="Select agency" />
                </SelectTrigger>
                <SelectContent>
                  {agencies.length === 0
                    ? <SelectItem value={NONE} disabled>No agencies — create one first</SelectItem>
                    : agencies.map((a) => <SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          )}

          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={pending}>Cancel</Button>
          <Button onClick={save} disabled={pending}>{pending ? 'Saving…' : 'Save'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Create-agency inline ──────────────────────────────────────────────────────
function AgencyManager({ tenantId, agencies, onChanged }: { tenantId: string; agencies: Agency[]; onChanged: () => void }) {
  const [name, setName] = useState('')
  const [pending, startTransition] = useTransition()

  function add() {
    if (!name.trim()) return
    startTransition(async () => {
      const supabase = createClient()
      const { error } = await supabase.from('agencies').insert({ name: name.trim(), tenant_id: tenantId })
      if (error) { toast.error(error.message); return }
      toast.success(`Agency "${name.trim()}" added`)
      setName(''); onChanged()
    })
  }

  return (
    <div className="rounded-[14px] border border-line bg-paper p-4 space-y-3 shadow-[var(--shadow)]">
      <div className="flex items-center justify-between gap-3">
        <h2 className="text-base font-semibold">Partner agencies</h2>
        <div className="flex items-end gap-2">
          <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="New agency name" className="w-56" />
          <Button size="sm" disabled={pending || !name.trim()} onClick={add}>Add</Button>
        </div>
      </div>
      <div className="flex flex-wrap gap-2">
        {agencies.length === 0
          ? <span className="text-sm text-ink-3">No agencies yet.</span>
          : agencies.map((a) => (
              <span key={a.id} className="inline-block rounded-full border border-line-2 px-3 py-1 text-sm">{a.name}</span>
            ))}
      </div>
    </div>
  )
}

// ── Main ─────────────────────────────────────────────────────────────────────
export function HierarchyClient({
  currentUserId, tenantId, users, agencies,
}: {
  currentUserId: string
  tenantId: string
  users: HierUser[]
  agencies: Agency[]
}) {
  const router = useRouter()
  const [editing, setEditing] = useState<HierUser | null>(null)

  const nameOf = (id: string | null) =>
    id ? (users.find((u) => u.id === id)?.email_or_username ?? '—') : '—'
  const agencyName = (id: string | null) =>
    id ? (agencies.find((a) => a.id === id)?.name ?? '—') : '—'

  function refresh() { setEditing(null); router.refresh() }

  return (
    <div className="space-y-5">
      <div className="space-y-2">
        <p className="eyebrow">People</p>
        <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
          Organization
        </h1>
        <p className="text-[13.5px] text-ink-2">Roles, reporting hierarchy &amp; partner agencies</p>
      </div>

      <TabStrip />

      <AgencyManager tenantId={tenantId} agencies={agencies} onChanged={() => router.refresh()} />

      <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>User</TableHead>
              <TableHead>Tier</TableHead>
              <TableHead>Reports to</TableHead>
              <TableHead>Agency</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {users.map((u) => (
              <TableRow key={u.id}>
                <TableCell className="font-medium">
                  {u.email_or_username}
                  {u.id === currentUserId && <span className="ml-2 text-xs text-muted-foreground">(you)</span>}
                </TableCell>
                <TableCell><TierPill tier={u.role_tier as Tier | null} /></TableCell>
                <TableCell className="text-muted-foreground">{nameOf(u.reports_to_user_id)}</TableCell>
                <TableCell className="text-muted-foreground">{u.is_external ? agencyName(u.agency_id) : '—'}</TableCell>
                <TableCell className="text-right">
                  <Button size="sm" variant="outline" onClick={() => setEditing(u)}>Edit</Button>
                </TableCell>
              </TableRow>
            ))}
            {users.length === 0 && (
              <TableRow>
                <TableCell colSpan={5} className="text-center text-muted-foreground py-8">No users.</TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <EditDialog
        user={editing}
        users={users}
        agencies={agencies}
        onClose={() => setEditing(null)}
        onSaved={refresh}
      />
    </div>
  )
}
