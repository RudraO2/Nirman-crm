"use client"
import {
  useEffect, useMemo, useState, useTransition,
} from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import {
  DndContext, DragOverlay, closestCenter, useDraggable, useDroppable,
  type DragEndEvent, type DragStartEvent,
} from '@dnd-kit/core'
import { CSS } from '@dnd-kit/utilities'
import { createClient } from '@/lib/supabase/client'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import {
  Popover, PopoverContent, PopoverTrigger,
} from '@/components/ui/popover'
import {
  Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList,
} from '@/components/ui/command'
import { Check, ChevronsUpDown, AlertTriangle, GripVertical } from 'lucide-react'
import { cn } from '@/lib/utils'
import { StatusPill } from '@/components/leads/status-pill'
import type { LeadRow, EmployeeRow } from '@/components/leads/leads-table'

// ─── Types ──────────────────────────────────────────────────────────────────

type Mode = 'distribute' | 'manual'
type Step = 'configure' | 'preview' | 'dnd'

interface ActiveLeadCount { user_id: string; active_count: number }

// allocation: employee_id → lead_id[]
type Allocation = Record<string, string[]>

// ─── Round-robin helper ──────────────────────────────────────────────────────

function roundRobin(leadIds: string[], employeeIds: string[]): Allocation {
  const alloc: Allocation = Object.fromEntries(employeeIds.map((id) => [id, []]))
  leadIds.forEach((lid, i) => {
    alloc[employeeIds[i % employeeIds.length]].push(lid)
  })
  return alloc
}

// ─── Draggable lead card ─────────────────────────────────────────────────────

function DraggableLeadCard({
  lead, isDragOverlay = false,
}: {
  lead: LeadRow
  isDragOverlay?: boolean
}) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: lead.id,
    data: { lead },
  })
  const style = {
    transform: CSS.Translate.toString(transform),
    opacity: isDragging && !isDragOverlay ? 0.4 : 1,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...listeners}
      {...attributes}
      className={cn(
        'flex items-center gap-2 rounded-md border bg-card px-3 py-2 text-sm select-none',
        'cursor-grab active:cursor-grabbing shadow-sm',
        isDragOverlay && 'shadow-lg ring-2 ring-primary/30 rotate-1',
      )}
    >
      <GripVertical className="size-3.5 shrink-0 text-muted-foreground" />
      <span className="font-medium truncate max-w-[120px]">
        {lead.name ?? <span className="italic text-muted-foreground">Unnamed</span>}
      </span>
      <span className="font-mono text-[10px] text-muted-foreground shrink-0">
        •••{lead.phone_last4 ?? '----'}
      </span>
      <StatusPill status={lead.status} />
    </div>
  )
}

// ─── Droppable employee bucket ───────────────────────────────────────────────

function EmployeeBucket({
  employee, leads, activeCount, isOver,
}: {
  employee: EmployeeRow
  leads: LeadRow[]
  activeCount: number
  isOver: boolean
}) {
  const { setNodeRef } = useDroppable({ id: employee.id, data: { type: 'bucket' } })
  const afterAssign = activeCount + leads.length
  const overThreshold = afterAssign > 80

  return (
    <div
      ref={setNodeRef}
      className={cn(
        'flex flex-col gap-2 rounded-lg border-2 p-3 min-h-[120px] transition-colors',
        isOver ? 'border-primary bg-primary/5' : 'border-dashed border-muted-foreground/30',
      )}
    >
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold truncate">{employee.username}</span>
        <div className="flex items-center gap-1.5 shrink-0">
          {overThreshold && (
            <Badge
              variant="outline"
              className="text-[10px] border-amber-400 text-amber-600 bg-amber-50 dark:bg-amber-900/20"
            >
              <AlertTriangle className="size-3 mr-1" />
              {afterAssign} active
            </Badge>
          )}
          <Badge variant="secondary" className="text-[10px]">
            +{leads.length}
          </Badge>
        </div>
      </div>
      {leads.length === 0 ? (
        <p className="text-xs text-muted-foreground/60 text-center mt-2">Drop leads here</p>
      ) : (
        <div className="flex flex-col gap-1.5">
          {leads.map((l) => (
            <DraggableLeadCard key={l.id} lead={l} />
          ))}
        </div>
      )}
    </div>
  )
}

// ─── Droppable unassigned pool ────────────────────────────────────────────────

function UnassignedPool({ leads, isOver }: { leads: LeadRow[]; isOver: boolean }) {
  const { setNodeRef } = useDroppable({ id: '__unassigned__', data: { type: 'pool' } })

  return (
    <div
      ref={setNodeRef}
      className={cn(
        'flex flex-col gap-2 rounded-lg border-2 p-3 min-h-[120px] transition-colors',
        isOver ? 'border-primary bg-primary/5' : 'border-dashed border-muted-foreground/30',
      )}
    >
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold">Unassigned pool</span>
        <Badge variant="outline" className="text-[10px]">{leads.length}</Badge>
      </div>
      {leads.length === 0 ? (
        <p className="text-xs text-green-600 text-center mt-2 font-medium">All leads allocated ✓</p>
      ) : (
        <div className="flex flex-col gap-1.5">
          {leads.map((l) => (
            <DraggableLeadCard key={l.id} lead={l} />
          ))}
        </div>
      )}
    </div>
  )
}

// ─── Main dialog ─────────────────────────────────────────────────────────────

interface BulkAssignDialogProps {
  selectedLeads: LeadRow[]
  employees: EmployeeRow[]
  onSuccess: () => void
}

function nowLocalIso(): string {
  const d = new Date()
  d.setSeconds(0, 0)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16)
}

export function BulkAssignDialog({
  selectedLeads, employees, onSuccess,
}: BulkAssignDialogProps) {
  const router = useRouter()
  const [open, setOpen] = useState(false)

  // ── Step 1 state ──────────────────────────────────────────────────────────
  const [step, setStep] = useState<Step>('configure')
  const [selectedEmployeeIds, setSelectedEmployeeIds] = useState<string[]>([])
  const [empPopOpen, setEmpPopOpen] = useState(false)
  const [deadline, setDeadline] = useState('')
  const [mode, setMode] = useState<Mode>('distribute')
  const [configError, setConfigError] = useState<string | null>(null)

  // ── Step 2 state ──────────────────────────────────────────────────────────
  const [activeCounts, setActiveCounts] = useState<ActiveLeadCount[]>([])
  const [allocation, setAllocation] = useState<Allocation>({})
  const [activeLeadId, setActiveLeadId] = useState<string | null>(null)
  const [overId, setOverId] = useState<string | null>(null)
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  // Reset on close
  useEffect(() => {
    if (!open) {
      setStep('configure')
      setSelectedEmployeeIds([])
      setDeadline('')
      setMode('distribute')
      setConfigError(null)
      setActiveCounts([])
      setAllocation({})
      setActiveLeadId(null)
      setSubmitError(null)
    }
  }, [open])

  // ── Derived ───────────────────────────────────────────────────────────────

  const selectedEmployees = useMemo(
    () => employees.filter((e) => selectedEmployeeIds.includes(e.id)),
    [employees, selectedEmployeeIds],
  )

  const leadById = useMemo(
    () => Object.fromEntries(selectedLeads.map((l) => [l.id, l])),
    [selectedLeads],
  )

  const activeCountMap = useMemo(
    () => Object.fromEntries(activeCounts.map((r) => [r.user_id, Number(r.active_count)])),
    [activeCounts],
  )

  const unassignedLeads = useMemo(() => {
    const assignedSet = new Set(
      Object.values(allocation).flat()
    )
    return selectedLeads.filter((l) => !assignedSet.has(l.id))
  }, [allocation, selectedLeads])

  const hasUnallocated = unassignedLeads.length > 0

  // ── Handlers ──────────────────────────────────────────────────────────────

  function toggleEmployee(empId: string) {
    setSelectedEmployeeIds((prev) =>
      prev.includes(empId) ? prev.filter((id) => id !== empId) : [...prev, empId]
    )
  }

  async function handleAdvance() {
    setConfigError(null)
    if (selectedEmployeeIds.length === 0) {
      setConfigError('Pick at least one employee.')
      return
    }
    if (deadline) {
      const dt = new Date(deadline)
      if (Number.isNaN(dt.getTime())) { setConfigError('Invalid deadline.'); return }
      if (dt.getTime() <= Date.now()) { setConfigError('Deadline must be in the future.'); return }
    }

    // Fetch current active counts for warning banner
    const supabase = createClient()
    const { data } = await supabase.rpc('get_employee_active_lead_counts', {
      p_user_ids: selectedEmployeeIds,
    })
    setActiveCounts((data ?? []) as ActiveLeadCount[])

    // Build initial round-robin allocation
    const initialAlloc = roundRobin(
      selectedLeads.map((l) => l.id),
      selectedEmployeeIds,
    )
    setAllocation(initialAlloc)

    setStep(mode === 'distribute' ? 'preview' : 'dnd')
  }

  function handleResetRoundRobin() {
    setAllocation(roundRobin(selectedLeads.map((l) => l.id), selectedEmployeeIds))
  }

  async function handleConfirm() {
    setSubmitError(null)
    const entries = Object.entries(allocation)

    const parsedDeadline = deadline
      ? new Date(deadline).toISOString()
      : null

    const pAssignments = entries.flatMap(([empId, leadIds]) =>
      leadIds.map((lid) => ({ lead_id: lid, target_user_id: empId }))
    )

    if (pAssignments.length === 0) {
      setSubmitError('No leads allocated.')
      return
    }

    startTransition(async () => {
      const supabase = createClient()
      const { data: rpcData, error: rpcErr } = await supabase.rpc('bulk_assign_leads', {
        p_assignments: pAssignments,
        p_deadline: parsedDeadline,
      })
      if (rpcErr) {
        const msg = rpcErr.message ?? ''
        if (msg.includes('permission_denied')) {
          setSubmitError('You do not have permission to assign leads.')
        } else if (msg.includes('lead_not_found') || msg.includes('target_not_assignable')) {
          setSubmitError('Some leads or employees are no longer valid. Refresh and retry.')
        } else {
          setSubmitError(msg || 'Bulk assignment failed.')
        }
        return
      }

      // Fire-and-forget bulk push notifications — one per employee
      const perEmp = (rpcData as { per_employee: Record<string, number> })?.per_employee ?? {}
      const notifAssignments = Object.entries(perEmp).map(([uid, count]) => ({
        user_id: uid,
        count,
      }))
      if (notifAssignments.length > 0) {
        supabase.functions
          .invoke('send-bulk-assignment-notification', {
            body: { assignments: notifAssignments },
          })
          .catch(() => {/* best-effort */})
      }

      const total = pAssignments.length
      const empCount = selectedEmployees.length
      toast.success(
        `${total} lead${total !== 1 ? 's' : ''} assigned to ${empCount} employee${empCount !== 1 ? 's' : ''}`,
      )
      setOpen(false)
      onSuccess()
      router.refresh()
    })
  }

  // ── DnD handlers ─────────────────────────────────────────────────────────

  function handleDragStart({ active }: DragStartEvent) {
    setActiveLeadId(active.id as string)
  }

  function handleDragEnd({ active, over }: DragEndEvent) {
    setActiveLeadId(null)
    setOverId(null)
    if (!over) return

    const leadId = active.id as string
    const targetId = over.id as string // employee id or '__unassigned__'

    setAllocation((prev) => {
      // Remove from wherever it currently lives
      const next: Allocation = {}
      for (const [empId, leads] of Object.entries(prev)) {
        next[empId] = leads.filter((id) => id !== leadId)
      }
      // Add to target bucket
      if (targetId === '__unassigned__') {
        // leave out of allocation — unassigned pool
      } else {
        next[targetId] = [...(next[targetId] ?? []), leadId]
      }
      return next
    })
  }

  // ── Warning banner logic ──────────────────────────────────────────────────

  const warnings = useMemo(() => {
    if (step !== 'preview' && step !== 'dnd') return []
    return selectedEmployees
      .filter((e) => {
        const existing = activeCountMap[e.id] ?? 0
        const adding = (allocation[e.id] ?? []).length
        return existing + adding > 80
      })
      .map((e) => {
        const existing = activeCountMap[e.id] ?? 0
        const adding = (allocation[e.id] ?? []).length
        return { name: e.username, total: existing + adding }
      })
  }, [step, selectedEmployees, activeCountMap, allocation])

  // ── Active drag lead ──────────────────────────────────────────────────────
  const activeLead = activeLeadId ? leadById[activeLeadId] : null

  // ─────────────────────────────────────────────────────────────────────────
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">
          Bulk Assign ({selectedLeads.length})
        </Button>
      </DialogTrigger>

      <DialogContent className={cn(
        'max-w-xl',
        step === 'dnd' && 'max-w-4xl',
      )}>
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">
            Bulk Assign — {selectedLeads.length} leads
          </DialogTitle>
        </DialogHeader>

        {/* ── Step 1: Configure ─────────────────────────────────────── */}
        {step === 'configure' && (
          <div className="space-y-5 py-2">
            {/* Employee multi-select */}
            <div className="space-y-2">
              <Label>Employees</Label>
              <Popover open={empPopOpen} onOpenChange={setEmpPopOpen}>
                <PopoverTrigger asChild>
                  <Button
                    variant="outline"
                    role="combobox"
                    aria-expanded={empPopOpen}
                    className="w-full justify-between font-normal"
                  >
                    {selectedEmployeeIds.length === 0
                      ? 'Pick employees…'
                      : `${selectedEmployeeIds.length} employee${selectedEmployeeIds.length > 1 ? 's' : ''} selected`}
                    <ChevronsUpDown className="ml-2 size-4 shrink-0 opacity-50" />
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-[var(--radix-popover-trigger-width)] p-0">
                  <Command>
                    <CommandInput placeholder="Search employees…" />
                    <CommandList>
                      <CommandEmpty>No employee found.</CommandEmpty>
                      <CommandGroup>
                        {employees.map((emp) => (
                          <CommandItem
                            key={emp.id}
                            value={emp.username}
                            onSelect={() => toggleEmployee(emp.id)}
                          >
                            <Check
                              className={cn(
                                'mr-2 size-4',
                                selectedEmployeeIds.includes(emp.id) ? 'opacity-100' : 'opacity-0',
                              )}
                            />
                            {emp.username}
                          </CommandItem>
                        ))}
                      </CommandGroup>
                    </CommandList>
                  </Command>
                </PopoverContent>
              </Popover>
              {selectedEmployeeIds.length > 0 && (
                <div className="flex flex-wrap gap-1">
                  {selectedEmployees.map((e) => (
                    <Badge
                      key={e.id}
                      variant="secondary"
                      className="cursor-pointer"
                      onClick={() => toggleEmployee(e.id)}
                    >
                      {e.username} ×
                    </Badge>
                  ))}
                </div>
              )}
            </div>

            {/* Deadline */}
            <div className="space-y-2">
              <Label htmlFor="bulk-deadline">Deadline (optional)</Label>
              <div className="flex gap-2">
                <Input
                  id="bulk-deadline"
                  type="datetime-local"
                  value={deadline}
                  min={nowLocalIso()}
                  onChange={(e) => setDeadline(e.target.value)}
                />
                {deadline && (
                  <Button type="button" variant="ghost" size="sm" onClick={() => setDeadline('')}>
                    Clear
                  </Button>
                )}
              </div>
            </div>

            {/* Mode toggle */}
            <div className="space-y-2">
              <Label>Distribution mode</Label>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => setMode('distribute')}
                  className={cn(
                    'rounded-lg border px-4 py-3 text-left transition-colors',
                    mode === 'distribute'
                      ? 'border-primary bg-primary/5'
                      : 'border-input hover:bg-muted/50',
                  )}
                >
                  <p className="text-sm font-medium">Distribute Equally</p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Round-robin across selected employees
                  </p>
                </button>
                <button
                  type="button"
                  onClick={() => setMode('manual')}
                  className={cn(
                    'rounded-lg border px-4 py-3 text-left transition-colors',
                    mode === 'manual'
                      ? 'border-primary bg-primary/5'
                      : 'border-input hover:bg-muted/50',
                  )}
                >
                  <p className="text-sm font-medium">Manual Allocation</p>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    Drag leads into employee buckets
                  </p>
                </button>
              </div>
            </div>

            {configError && (
              <p className="text-destructive text-sm">{configError}</p>
            )}
          </div>
        )}

        {/* ── Step 2a: Distribute preview ───────────────────────────── */}
        {step === 'preview' && (
          <div className="space-y-4 py-2">
            <p className="text-sm text-muted-foreground">
              {selectedLeads.length} leads → {selectedEmployees.length} employees (round-robin)
            </p>

            {warnings.length > 0 && (
              <div className="rounded-lg border border-amber-300 bg-amber-50 dark:bg-amber-900/20 px-4 py-3 space-y-1">
                <div className="flex items-center gap-2 text-amber-700 dark:text-amber-400 font-medium text-sm">
                  <AlertTriangle className="size-4 shrink-0" />
                  Workload warning
                </div>
                {warnings.map((w) => (
                  <p key={w.name} className="text-sm text-amber-700 dark:text-amber-300 pl-6">
                    {w.name} will have {w.total} active leads after assignment (limit: 80)
                  </p>
                ))}
              </div>
            )}

            <div className="rounded-lg border overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-muted/50">
                  <tr>
                    <th className="px-4 py-2 text-left font-medium">Employee</th>
                    <th className="px-4 py-2 text-left font-medium">New leads</th>
                    <th className="px-4 py-2 text-left font-medium">Lead names</th>
                  </tr>
                </thead>
                <tbody>
                  {selectedEmployees.map((e) => {
                    const empLeads = (allocation[e.id] ?? []).map((id) => leadById[id]).filter(Boolean)
                    const preview = empLeads.slice(0, 3).map((l) => l.name ?? 'Unnamed').join(', ')
                    const extra = empLeads.length - 3
                    return (
                      <tr key={e.id} className="border-t">
                        <td className="px-4 py-2 font-medium">{e.username}</td>
                        <td className="px-4 py-2">
                          <Badge variant="secondary">{empLeads.length}</Badge>
                        </td>
                        <td className="px-4 py-2 text-muted-foreground text-xs">
                          {preview}{extra > 0 ? ` +${extra} more` : ''}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>

            {submitError && <p className="text-destructive text-sm">{submitError}</p>}
          </div>
        )}

        {/* ── Step 2b: Manual DnD ───────────────────────────────────── */}
        {step === 'dnd' && (
          <div className="space-y-4 py-2">
            {warnings.length > 0 && (
              <div className="rounded-lg border border-amber-300 bg-amber-50 dark:bg-amber-900/20 px-4 py-3 space-y-1">
                <div className="flex items-center gap-2 text-amber-700 dark:text-amber-400 font-medium text-sm">
                  <AlertTriangle className="size-4 shrink-0" />
                  Workload warning
                </div>
                {warnings.map((w) => (
                  <p key={w.name} className="text-sm text-amber-700 dark:text-amber-300 pl-6">
                    {w.name} will have {w.total} active leads (limit: 80)
                  </p>
                ))}
              </div>
            )}

            <div className="flex items-center justify-between">
              <p className="text-sm text-muted-foreground">
                Drag leads into employee buckets. All must be allocated to confirm.
              </p>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={handleResetRoundRobin}
              >
                Distribute Equally
              </Button>
            </div>

            <DndContext
              collisionDetection={closestCenter}
              onDragStart={handleDragStart}
              onDragEnd={handleDragEnd}
              onDragOver={({ over }) => setOverId(over ? String(over.id) : null)}
            >
              <div className="grid gap-3" style={{
                gridTemplateColumns: `repeat(${Math.min(selectedEmployees.length + 1, 4)}, 1fr)`,
              }}>
                <UnassignedPool leads={unassignedLeads} isOver={overId === '__unassigned__'} />
                {selectedEmployees.map((e) => (
                  <EmployeeBucket
                    key={e.id}
                    employee={e}
                    leads={(allocation[e.id] ?? []).map((id) => leadById[id]).filter(Boolean)}
                    activeCount={activeCountMap[e.id] ?? 0}
                    isOver={overId === e.id}
                  />
                ))}
              </div>

              <DragOverlay>
                {activeLead ? <DraggableLeadCard lead={activeLead} isDragOverlay /> : null}
              </DragOverlay>
            </DndContext>

            {submitError && <p className="text-destructive text-sm">{submitError}</p>}
          </div>
        )}

        {/* ── Footer ────────────────────────────────────────────────── */}
        <DialogFooter>
          {step === 'configure' && (
            <>
              <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={handleAdvance}>
                {mode === 'distribute' ? 'Preview Distribution' : 'Open Allocation Canvas'}
              </Button>
            </>
          )}
          {(step === 'preview' || step === 'dnd') && (
            <>
              <Button variant="ghost" onClick={() => setStep('configure')} disabled={pending}>
                Back
              </Button>
              <Button
                onClick={handleConfirm}
                disabled={pending || (step === 'dnd' && hasUnallocated)}
              >
                {pending
                  ? 'Assigning…'
                  : `Confirm Assignment (${selectedLeads.length - unassignedLeads.length})`}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
