"use client"
import { useEffect, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Popover, PopoverContent, PopoverTrigger,
} from '@/components/ui/popover'
import {
  Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList,
} from '@/components/ui/command'
import { Check, ChevronsUpDown } from 'lucide-react'
import { cn } from '@/lib/utils'

interface Employee { id: string; username: string }

interface AssignDialogProps {
  leadId: string
  leadName: string | null
  phoneLast4: string | null
  currentAssigneeId: string | null
  currentDeadline: string | null
  employees: Employee[]
}

function nowLocalIso(): string {
  const d = new Date()
  d.setSeconds(0, 0)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16)
}

export function AssignDialog({
  leadId, leadName, phoneLast4, currentAssigneeId, currentDeadline, employees,
}: AssignDialogProps) {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  // P4: only pre-select the current assignee if they're still in the assignable employees list.
  // Legacy admin-owned leads have currentAssigneeId set but the user isn't an employee — pre-selecting
  // would let the user click Confirm and hit a server-side target_not_assignable error.
  const isPreselectable = (id: string | null) =>
    id !== null && employees.some((e) => e.id === id)
  const [employeeId, setEmployeeId] = useState<string | null>(
    isPreselectable(currentAssigneeId) ? currentAssigneeId : null
  )
  const [popOpen, setPopOpen] = useState(false)
  const [deadline, setDeadline] = useState<string>(
    currentDeadline ? new Date(currentDeadline).toISOString().slice(0, 16) : ''
  )
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  useEffect(() => {
    if (!open) {
      setEmployeeId(isPreselectable(currentAssigneeId) ? currentAssigneeId : null)
      setDeadline(currentDeadline ? new Date(currentDeadline).toISOString().slice(0, 16) : '')
      setError(null)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, currentAssigneeId, currentDeadline])

  const selectedUsername = employees.find((e) => e.id === employeeId)?.username ?? null

  async function handleConfirm() {
    setError(null)
    if (!employeeId) { setError('Pick an employee.'); return }
    let deadlineIso: string | null = null
    if (deadline) {
      const dt = new Date(deadline)
      if (Number.isNaN(dt.getTime())) { setError('Invalid deadline.'); return }
      if (dt.getTime() <= Date.now()) { setError('Deadline must be in the future.'); return }
      deadlineIso = dt.toISOString()
    }

    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('assign_lead', {
        p_lead_id: leadId,
        p_target_user_id: employeeId,
        p_deadline: deadlineIso,
      })
      if (rpcErr) {
        const msg = rpcErr.message ?? ''
        if (msg.includes('permission_denied')) setError('You do not have permission to assign leads.')
        else if (msg.includes('lead_not_found')) setError('Lead no longer exists.')
        else if (msg.includes('target_not_assignable')) setError('Selected user cannot receive assignments.')
        else setError(msg || 'Assignment failed.')
        return
      }

      // Fire-and-forget push fan-out — UI does not block on this
      supabase.functions
        .invoke('send-assignment-notification', {
          body: { lead_id: leadId, assignee_user_id: employeeId },
        })
        .catch(() => {/* push is best-effort */})

      toast.success(`Assigned to ${selectedUsername ?? 'employee'}`)
      setOpen(false)
      router.refresh()
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">Assign</Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">
            Assign &ldquo;{leadName ?? 'Unnamed lead'}&rdquo;
            {phoneLast4 && (
              <span className="ml-2 font-mono text-xs text-muted-foreground">•••{phoneLast4}</span>
            )}
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label>Employee</Label>
            <Popover open={popOpen} onOpenChange={setPopOpen}>
              <PopoverTrigger asChild>
                <Button
                  variant="outline"
                  role="combobox"
                  aria-expanded={popOpen}
                  className="w-full justify-between font-normal"
                >
                  {selectedUsername ?? 'Pick an employee…'}
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
                          onSelect={() => { setEmployeeId(emp.id); setPopOpen(false) }}
                        >
                          <Check
                            className={cn(
                              'mr-2 size-4',
                              employeeId === emp.id ? 'opacity-100' : 'opacity-0'
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
          </div>

          <div className="space-y-2">
            <Label htmlFor="deadline">Deadline (optional)</Label>
            <div className="flex gap-2">
              <Input
                id="deadline"
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

          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)} disabled={pending}>Cancel</Button>
          <Button onClick={handleConfirm} disabled={pending || !employeeId}>
            {pending ? 'Assigning…' : 'Confirm'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
