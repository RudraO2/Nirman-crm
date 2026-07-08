"use client"
import { useCallback, useEffect, useMemo, useState, useTransition } from 'react'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from '@/components/ui/dialog'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { TabStrip } from '@/components/tab-strip'
import type { InventoryProjectRow } from './page'

// ── Types ───────────────────────────────────────────────────────────────────
type UnitStatus = 'available' | 'hold' | 'sold' | 'blocked'

interface Unit {
  unit_id: string
  tower_id: string | null
  tower_name: string | null
  unit_no: string
  floor: number | null
  configuration: string | null
  carpet_area_sqft: number | null
  status: UnitStatus
  list_price_paise: number | null
  cost_paise: number | null
  status_version: number
}

interface Tower {
  id: string
  name: string
  sort_order: number
}

const NO_TOWER = '__none__'

// ── Money helpers (DB stores paise) ──────────────────────────────────────────
function formatINR(paise: number | null): string {
  if (paise == null) return '—'
  const rupees = paise / 100
  if (rupees >= 1e7) return `₹${(rupees / 1e7).toFixed(2)} Cr`
  if (rupees >= 1e5) return `₹${(rupees / 1e5).toFixed(2)} L`
  return `₹${rupees.toLocaleString('en-IN')}`
}
// rupees string from user → paise (or null)
function rupeesToPaise(v: string): number | null {
  const n = Number(v.replace(/,/g, '').trim())
  if (!v.trim() || Number.isNaN(n)) return null
  return Math.round(n * 100)
}

// ── Tile colors — §3 unit palette (mockup .u-available/.u-hold/.u-sold/.u-blocked) ──
const TILE: Record<UnitStatus, { bg: string; fg: string; label: string; border: string }> = {
  available: { bg: 'var(--sold-bg)',   fg: 'var(--sold)',        label: 'Available', border: '#BFDCC9' },
  hold:      { bg: 'var(--warm-bg)',   fg: 'var(--warm)',        label: 'On hold',   border: '#EBD9AF' },
  sold:      { bg: 'var(--evergreen)', fg: 'var(--brass-bright)', label: 'Sold',     border: 'transparent' },
  blocked:   { bg: 'var(--mist)',      fg: 'var(--ink-3)',       label: 'Blocked',   border: 'var(--line)' },
}
const STATUSES: UnitStatus[] = ['available', 'hold', 'sold', 'blocked']

// ── Generate Grid dialog ─────────────────────────────────────────────────────
function GenerateGridDialog({
  projectId, towers, defaultHoldHours, onDone,
}: {
  projectId: string
  towers: Tower[]
  defaultHoldHours: number | null
  onDone: () => void
}) {
  const [open, setOpen] = useState(false)
  const [towerId, setTowerId] = useState<string>(NO_TOWER)
  const [floors, setFloors] = useState('5')
  const [perFloor, setPerFloor] = useState('4')
  const [config, setConfig] = useState('2BHK')
  const [holdHours, setHoldHours] = useState(String(defaultHoldHours ?? 24))
  const [carpet, setCarpet] = useState('')
  const [listPrice, setListPrice] = useState('')
  const [cost, setCost] = useState('')
  // Flexible numbering (0085)
  const [startFloor, setStartFloor] = useState('1')
  const [unitStart, setUnitStart] = useState('1')
  const [prefix, setPrefix] = useState('')
  const [pad, setPad] = useState('0')
  const [skip, setSkip] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  function reset() {
    setTowerId(NO_TOWER); setFloors('5'); setPerFloor('4'); setConfig('2BHK')
    setHoldHours(String(defaultHoldHours ?? 24)); setCarpet(''); setListPrice(''); setCost('')
    setStartFloor('1'); setUnitStart('1'); setPrefix(''); setPad('0'); setSkip('')
    setError(null)
  }

  function handleSubmit() {
    setError(null)
    const nFloors = parseInt(floors, 10)
    const nPer = parseInt(perFloor, 10)
    const nHold = parseInt(holdHours, 10)
    const nStartFloor = parseInt(startFloor, 10)
    const nUnitStart = parseInt(unitStart, 10)
    const nPad = parseInt(pad, 10) || 0
    if (!nFloors || nFloors < 1) { setError('Floors must be ≥ 1.'); return }
    if (!nPer || nPer < 1) { setError('Units per floor must be ≥ 1.'); return }
    if (!nHold || nHold < 1) { setError('Hold timer (hours) is required and must be ≥ 1.'); return }
    if (Number.isNaN(nStartFloor)) { setError('Start floor must be a number.'); return }
    if (Number.isNaN(nUnitStart) || nUnitStart < 0) { setError('First unit position must be ≥ 0.'); return }
    // skip floors: comma-separated ints
    const skipFloors = skip.split(',').map((s) => parseInt(s.trim(), 10)).filter((n) => !Number.isNaN(n))

    // config_map keyed by actual position (unitStart … unitStart+nPer-1)
    const configMap: Record<string, string> = {}
    if (config.trim()) {
      for (let p = nUnitStart; p < nUnitStart + nPer; p++) configMap[String(p)] = config.trim()
    }

    startTransition(async () => {
      const supabase = createClient()
      const { data, error: rpcErr } = await supabase.rpc('generate_unit_grid', {
        p_project_id: projectId,
        p_tower_id: towerId === NO_TOWER ? null : towerId,
        p_floors: nFloors,
        p_units_per_floor: nPer,
        p_config_map: configMap,
        p_hold_timer_hours: nHold,
        p_carpet_area_sqft: carpet.trim() ? Number(carpet) : null,
        p_list_price_paise: rupeesToPaise(listPrice),
        p_cost_paise: rupeesToPaise(cost),
        p_start_floor: nStartFloor,
        p_unit_start: nUnitStart,
        p_prefix: prefix.trim(),
        p_pad_width: nPad,
        p_skip_floors: skipFloors,
      })
      if (rpcErr) { setError(rpcErr.message); return }
      const created = (data as { created?: number })?.created ?? 0
      const skipped = (data as { skipped_existing?: number })?.skipped_existing ?? 0
      toast.success(`Created ${created} unit${created !== 1 ? 's' : ''}${skipped ? ` · ${skipped} already existed` : ''}`)
      setOpen(false); reset(); onDone()
    })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { setOpen(v); if (!v) reset() }}>
      <DialogTrigger asChild>
        <Button size="sm">Generate units</Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">Generate unit grid</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="g-tower">Tower</Label>
            <Select value={towerId} onValueChange={setTowerId}>
              <SelectTrigger id="g-tower" className="w-full">
                <SelectValue placeholder="— No tower —" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NO_TOWER}>— No tower —</SelectItem>
                {towers.map((t) => <SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="g-floors">Floors *</Label>
              <Input id="g-floors" type="number" min={1} value={floors} onChange={(e) => setFloors(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="g-per">Units / floor *</Label>
              <Input id="g-per" type="number" min={1} value={perFloor} onChange={(e) => setPerFloor(e.target.value)} />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="g-config">Configuration</Label>
              <Input id="g-config" value={config} onChange={(e) => setConfig(e.target.value)} placeholder="2BHK" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="g-hold">Hold timer (hrs) *</Label>
              <Input id="g-hold" type="number" min={1} value={holdHours} onChange={(e) => setHoldHours(e.target.value)} />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-2">
              <Label htmlFor="g-carpet">Carpet (sqft)</Label>
              <Input id="g-carpet" type="number" value={carpet} onChange={(e) => setCarpet(e.target.value)} placeholder="—" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="g-price">List price (₹)</Label>
              <Input id="g-price" value={listPrice} onChange={(e) => setListPrice(e.target.value)} placeholder="—" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="g-cost">Cost (₹)</Label>
              <Input id="g-cost" value={cost} onChange={(e) => setCost(e.target.value)} placeholder="—" />
            </div>
          </div>
          <details className="rounded-[10px] border border-line bg-mist/40 px-3 py-2">
            <summary className="cursor-pointer text-sm font-medium text-ink-2">Advanced numbering</summary>
            <div className="mt-3 space-y-3">
              <div className="grid grid-cols-3 gap-3">
                <div className="space-y-2">
                  <Label htmlFor="g-startfloor">Start floor</Label>
                  <Input id="g-startfloor" type="number" value={startFloor} onChange={(e) => setStartFloor(e.target.value)} placeholder="1" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="g-unitstart">First unit no.</Label>
                  <Input id="g-unitstart" type="number" min={0} value={unitStart} onChange={(e) => setUnitStart(e.target.value)} placeholder="1" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="g-pad">Pad digits</Label>
                  <Input id="g-pad" type="number" min={0} max={12} value={pad} onChange={(e) => setPad(e.target.value)} placeholder="0" />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-2">
                  <Label htmlFor="g-prefix">Prefix</Label>
                  <Input id="g-prefix" value={prefix} onChange={(e) => setPrefix(e.target.value)} placeholder="e.g. A-" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="g-skip">Skip floors</Label>
                  <Input id="g-skip" value={skip} onChange={(e) => setSkip(e.target.value)} placeholder="e.g. 13" />
                </div>
              </div>
              <p className="text-xs text-muted-foreground">
                Start floor 0 = ground. First unit no. offsets the position (e.g. 1 → 101, 5 → 105).
                Pad digits zero-fills the number (pad 4 → 0101). Prefix prepends (A- → A-101).
                Skip floors omits those floor numbers (comma-separated, e.g. 13).
              </p>
            </div>
          </details>
          <p className="text-xs text-muted-foreground">
            Unit no. = prefix + (floor×100 + position). Re-running skips units that already exist.
          </p>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)} disabled={pending}>Cancel</Button>
          <Button onClick={handleSubmit} disabled={pending}>{pending ? 'Generating…' : 'Generate'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Add Tower dialog ─────────────────────────────────────────────────────────
function AddTowerDialog({ projectId, onDone }: { projectId: string; onDone: () => void }) {
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  function handleSubmit() {
    setError(null)
    if (!name.trim()) { setError('Tower name required.'); return }
    startTransition(async () => {
      const supabase = createClient()
      const { error: insErr } = await supabase.from('towers').insert({ project_id: projectId, name: name.trim() })
      if (insErr) { setError(insErr.message); return }
      toast.success(`Tower "${name.trim()}" added`)
      setOpen(false); setName(''); onDone()
    })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { setOpen(v); if (!v) { setName(''); setError(null) } }}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">Add tower</Button>
      </DialogTrigger>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">Add tower</DialogTitle>
        </DialogHeader>
        <div className="space-y-2 py-2">
          <Label htmlFor="t-name">Name *</Label>
          <Input id="t-name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Tower A" />
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)} disabled={pending}>Cancel</Button>
          <Button onClick={handleSubmit} disabled={pending || !name.trim()}>{pending ? 'Adding…' : 'Add'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Add single unit dialog (0086 add_unit) ───────────────────────────────────
function AddUnitDialog({ projectId, towers, onDone }: { projectId: string; towers: Tower[]; onDone: () => void }) {
  const [open, setOpen] = useState(false)
  const [towerId, setTowerId] = useState<string>(NO_TOWER)
  const [unitNo, setUnitNo] = useState('')
  const [floor, setFloor] = useState('')
  const [config, setConfig] = useState('')
  const [carpet, setCarpet] = useState('')
  const [listPrice, setListPrice] = useState('')
  const [cost, setCost] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  function reset() {
    setTowerId(NO_TOWER); setUnitNo(''); setFloor(''); setConfig('')
    setCarpet(''); setListPrice(''); setCost(''); setError(null)
  }

  function handleSubmit() {
    setError(null)
    if (!unitNo.trim()) { setError('Unit number is required.'); return }
    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('add_unit', {
        p_project_id: projectId,
        p_tower_id: towerId === NO_TOWER ? null : towerId,
        p_unit_no: unitNo.trim(),
        p_floor: floor.trim() ? parseInt(floor, 10) : null,
        p_configuration: config.trim() || null,
        p_carpet_area_sqft: carpet.trim() ? Number(carpet) : null,
        p_list_price_paise: rupeesToPaise(listPrice),
        p_cost_paise: rupeesToPaise(cost),
      })
      if (rpcErr) { setError(rpcErr.message); return }
      toast.success(`Unit ${unitNo.trim()} added`)
      setOpen(false); reset(); onDone()
    })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { setOpen(v); if (!v) reset() }}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">Add unit</Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">Add a single unit</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="au-tower">Tower</Label>
            <Select value={towerId} onValueChange={setTowerId}>
              <SelectTrigger id="au-tower" className="w-full">
                <SelectValue placeholder="— No tower —" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NO_TOWER}>— No tower —</SelectItem>
                {towers.map((t) => <SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="au-no">Unit no. *</Label>
              <Input id="au-no" value={unitNo} onChange={(e) => setUnitNo(e.target.value)} placeholder="e.g. G-01" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="au-floor">Floor</Label>
              <Input id="au-floor" type="number" value={floor} onChange={(e) => setFloor(e.target.value)} placeholder="—" />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-2">
              <Label htmlFor="au-config">Config</Label>
              <Input id="au-config" value={config} onChange={(e) => setConfig(e.target.value)} placeholder="2BHK" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="au-carpet">Carpet</Label>
              <Input id="au-carpet" type="number" value={carpet} onChange={(e) => setCarpet(e.target.value)} placeholder="—" />
            </div>
            <div className="space-y-2">
              <Label htmlFor="au-price">Price (₹)</Label>
              <Input id="au-price" value={listPrice} onChange={(e) => setListPrice(e.target.value)} placeholder="—" />
            </div>
          </div>
          <div className="space-y-2">
            <Label htmlFor="au-cost">Cost / margin (₹)</Label>
            <Input id="au-cost" value={cost} onChange={(e) => setCost(e.target.value)} placeholder="—" />
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)} disabled={pending}>Cancel</Button>
          <Button onClick={handleSubmit} disabled={pending || !unitNo.trim()}>{pending ? 'Adding…' : 'Add unit'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Unit detail dialog (reprice + state transitions) ─────────────────────────
function UnitDialog({ unit, onClose, onChanged }: { unit: Unit | null; onClose: () => void; onChanged: () => void }) {
  const [listPrice, setListPrice] = useState('')
  const [cost, setCost] = useState('')
  const [config, setConfig] = useState('')
  const [carpet, setCarpet] = useState('')
  const [renameNo, setRenameNo] = useState('')
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  useEffect(() => {
    if (unit) {
      setListPrice(unit.list_price_paise != null ? String(unit.list_price_paise / 100) : '')
      setCost(unit.cost_paise != null ? String(unit.cost_paise / 100) : '')
      setConfig(unit.configuration ?? '')
      setCarpet(unit.carpet_area_sqft != null ? String(unit.carpet_area_sqft) : '')
      setRenameNo(unit.unit_no)
      setConfirmDelete(false)
      setError(null)
    }
  }, [unit])

  if (!unit) return null
  const locked = unit.status === 'hold' || unit.status === 'sold'

  function reprice() {
    if (!unit) return
    setError(null)
    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('update_unit_listing', {
        p_unit_id: unit.unit_id,
        p_list_price_paise: rupeesToPaise(listPrice),
        p_cost_paise: rupeesToPaise(cost),
        p_configuration: config.trim() || null,
        p_carpet_area_sqft: carpet.trim() ? Number(carpet) : null,
      })
      if (rpcErr) { setError(rpcErr.message); return }
      toast.success(`Unit ${unit.unit_no} updated`)
      onChanged()
    })
  }

  function rename() {
    if (!unit) return
    setError(null)
    const next = renameNo.trim()
    if (!next) { setError('Unit number is required.'); return }
    if (next === unit.unit_no) return
    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('rename_unit', {
        p_unit_id: unit.unit_id,
        p_new_unit_no: next,
      })
      if (rpcErr) { setError(rpcErr.message); return }
      toast.success(`Renamed to ${next}`)
      onChanged()
    })
  }

  function del() {
    if (!unit) return
    setError(null)
    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('delete_unit', { p_unit_id: unit.unit_id })
      if (rpcErr) { setError(rpcErr.message); return }
      toast.success(`Unit ${unit.unit_no} deleted`)
      onChanged()
    })
  }

  function transition(action: 'withdraw' | 'restock' | 'force_release') {
    if (!unit) return
    setError(null)
    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('change_unit_inventory_state', {
        p_unit_id: unit.unit_id,
        p_action: action,
        p_expected_version: unit.status_version,
      })
      if (rpcErr) { setError(rpcErr.message); return }
      const verb = action === 'withdraw' ? 'withdrawn' : action === 'restock' ? 'restocked' : 'released'
      toast.success(`Unit ${unit.unit_no} ${verb}`)
      onChanged()
    })
  }

  return (
    <Dialog open={!!unit} onOpenChange={(v) => { if (!v) onClose() }}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">
            Unit {unit.unit_no}
            {unit.tower_name ? ` · ${unit.tower_name}` : ''}
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="flex items-center gap-2 text-sm">
            <span
              className="rounded-full px-3 py-1 text-xs font-medium"
              style={{ background: TILE[unit.status].bg, color: TILE[unit.status].fg }}
            >
              {TILE[unit.status].label}
            </span>
            {unit.floor != null && <span className="text-muted-foreground">Floor {unit.floor}</span>}
          </div>

          {locked ? (
            <p className="text-sm text-muted-foreground">
              This unit is {unit.status}. It cannot be repriced or edited until released.
            </p>
          ) : (
            <div className="space-y-3">
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label htmlFor="u-price">List price (₹)</Label>
                  <Input id="u-price" value={listPrice} onChange={(e) => setListPrice(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="u-cost">Cost / margin (₹)</Label>
                  <Input id="u-cost" value={cost} onChange={(e) => setCost(e.target.value)} />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1.5">
                  <Label htmlFor="u-config">Configuration</Label>
                  <Input id="u-config" value={config} onChange={(e) => setConfig(e.target.value)} />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="u-carpet">Carpet (sqft)</Label>
                  <Input id="u-carpet" value={carpet} onChange={(e) => setCarpet(e.target.value)} />
                </div>
              </div>
              <div className="space-y-1.5 border-t border-line pt-3">
                <Label htmlFor="u-rename">Unit number</Label>
                <div className="flex gap-2">
                  <Input id="u-rename" value={renameNo} onChange={(e) => setRenameNo(e.target.value)} />
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={rename}
                    disabled={pending || !renameNo.trim() || renameNo.trim() === unit.unit_no}
                  >
                    Rename
                  </Button>
                </div>
              </div>
            </div>
          )}

          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter className="flex-wrap gap-2 sm:justify-between">
          <div className="flex gap-2">
            {unit.status === 'available' && (
              <Button variant="outline" size="sm" onClick={() => transition('withdraw')} disabled={pending}>
                Withdraw
              </Button>
            )}
            {unit.status === 'blocked' && (
              <Button variant="outline" size="sm" onClick={() => transition('restock')} disabled={pending}>
                Restock
              </Button>
            )}
            {locked && (
              <Button variant="destructive" size="sm" onClick={() => transition('force_release')} disabled={pending}>
                Force release
              </Button>
            )}
            {!locked && (
              confirmDelete ? (
                <Button variant="destructive" size="sm" onClick={del} disabled={pending}>
                  {pending ? 'Deleting…' : 'Confirm delete'}
                </Button>
              ) : (
                <Button variant="outline" size="sm" onClick={() => setConfirmDelete(true)} disabled={pending}>
                  Delete
                </Button>
              )
            )}
          </div>
          {!locked && (
            <Button size="sm" onClick={reprice} disabled={pending}>
              {pending ? 'Saving…' : 'Save changes'}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Unit tile ────────────────────────────────────────────────────────────────
function UnitTile({ unit, onClick }: { unit: Unit; onClick: () => void }) {
  const t = TILE[unit.status]
  return (
    <button
      onClick={onClick}
      title={`${unit.unit_no} · ${t.label}${unit.configuration ? ` · ${unit.configuration}` : ''}`}
      className="flex h-16 w-20 flex-col items-center justify-center rounded-[10px] border text-center transition-transform hover:-translate-y-0.5 focus:outline-none focus-visible:ring-2"
      style={{ background: t.bg, color: t.fg, borderColor: t.border }}
    >
      <span className="text-[13px] font-bold tabular-nums">{unit.unit_no}</span>
      {unit.configuration && <span className="text-[10px] opacity-85">{unit.configuration}</span>}
    </button>
  )
}

// ── Main ─────────────────────────────────────────────────────────────────────
export function InventoryClient({ projects }: { projects: InventoryProjectRow[] }) {
  const [projectId, setProjectId] = useState<string>(projects[0]?.id ?? '')
  const [units, setUnits] = useState<Unit[]>([])
  const [towers, setTowers] = useState<Tower[]>([])
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [selected, setSelected] = useState<Unit | null>(null)

  const project = projects.find((p) => p.id === projectId)

  const load = useCallback(async () => {
    if (!projectId) return
    setLoading(true); setLoadError(null)
    const supabase = createClient()
    const [unitsRes, towersRes] = await Promise.all([
      supabase.rpc('get_project_units', { p_project_id: projectId }),
      supabase.from('towers').select('id, name, sort_order').eq('project_id', projectId).order('sort_order'),
    ])
    if (unitsRes.error) { setLoadError(unitsRes.error.message); setLoading(false); return }
    setUnits((unitsRes.data ?? []) as Unit[])
    setTowers((towersRes.data ?? []) as Tower[])
    setLoading(false)
  }, [projectId])

  useEffect(() => { load() }, [load])

  // counts by status
  const counts = useMemo(() => {
    const c: Record<UnitStatus, number> = { available: 0, hold: 0, sold: 0, blocked: 0 }
    for (const u of units) c[u.status]++
    return c
  }, [units])

  // group units: tower → floor → units
  const grouped = useMemo(() => {
    const byTower = new Map<string, { name: string; floors: Map<number, Unit[]> }>()
    for (const u of units) {
      const key = u.tower_id ?? NO_TOWER
      const name = u.tower_name ?? 'No tower'
      if (!byTower.has(key)) byTower.set(key, { name, floors: new Map() })
      const fl = u.floor ?? -1
      const floors = byTower.get(key)!.floors
      if (!floors.has(fl)) floors.set(fl, [])
      floors.get(fl)!.push(u)
    }
    return byTower
  }, [units])

  function onChanged() { setSelected(null); load() }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <p className="eyebrow">Builder Ops</p>
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            Inventory
          </h1>
        </div>
        <div className="flex items-end gap-2">
          <div className="space-y-1.5">
            <Label htmlFor="proj-select" className="text-xs">Project</Label>
            <Select value={projectId} onValueChange={setProjectId}>
              <SelectTrigger id="proj-select" className="w-56">
                <SelectValue placeholder="Select a project" />
              </SelectTrigger>
              <SelectContent>
                {projects.map((p) => <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          {projectId && <AddTowerDialog projectId={projectId} onDone={load} />}
          {projectId && <AddUnitDialog projectId={projectId} towers={towers} onDone={load} />}
          {projectId && (
            <GenerateGridDialog
              projectId={projectId}
              towers={towers}
              defaultHoldHours={project?.hold_timer_hours ?? null}
              onDone={load}
            />
          )}
        </div>
      </div>

      <TabStrip />

      {/* Stats + legend */}
      <div className="flex flex-wrap gap-2.5">
        {STATUSES.map((s) => (
          <div
            key={s}
            className="flex items-center gap-2 rounded-[10px] border border-line bg-paper px-3 py-2 shadow-[var(--shadow)]"
          >
            <span
              className="size-3 rounded-sm"
              style={{ background: TILE[s].bg, border: `1px solid ${TILE[s].border}` }}
            />
            <span className="text-sm text-ink-2">{TILE[s].label}</span>
            <span className="text-sm font-semibold tabular-nums">{counts[s]}</span>
          </div>
        ))}
        <div className="flex items-center gap-2 rounded-[10px] border border-line bg-paper px-3 py-2 shadow-[var(--shadow)]">
          <span className="text-sm text-ink-3">Total</span>
          <span className="text-sm font-semibold tabular-nums">{units.length}</span>
        </div>
      </div>

      {loadError && <p className="text-danger text-sm">Failed to load units: {loadError}</p>}
      {loading && <p className="text-ink-2 text-sm">Loading…</p>}

      {!loading && units.length === 0 && !loadError && (
        <div className="rounded-[14px] border border-dashed border-line-2 p-10 text-center text-ink-2">
          No units yet for this project. Use <span className="font-medium text-ink">Generate units</span> to create the grid.
        </div>
      )}

      {/* Grid */}
      {[...grouped.entries()].map(([towerKey, { name, floors }]) => (
        <div key={towerKey} className="rounded-[14px] border border-line bg-paper p-5 shadow-[var(--shadow)] space-y-4">
          <h2 className="font-serif text-lg font-medium text-ink">{name}</h2>
          <div className="space-y-4">
            {[...floors.entries()]
              .sort((a, b) => b[0] - a[0]) // top floor first
              .map(([floor, fUnits]) => (
                <div key={floor} className="space-y-2.5">
                  <p className="eyebrow">
                    {floor === -1 ? 'Unassigned floor' : `Floor ${floor}`}
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {fUnits.map((u) => (
                      <UnitTile key={u.unit_id} unit={u} onClick={() => setSelected(u)} />
                    ))}
                  </div>
                </div>
              ))}
          </div>
        </div>
      ))}

      <UnitDialog unit={selected} onClose={() => setSelected(null)} onChanged={onChanged} />
    </div>
  )
}
