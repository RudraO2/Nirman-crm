"use client"
import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import {
  Popover, PopoverContent, PopoverTrigger,
} from '@/components/ui/popover'
import {
  Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList,
} from '@/components/ui/command'
import { Check, ChevronsUpDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { EmployeeRow } from '@/components/leads/leads-table'
import type { FutureLeadRow } from '@/app/(app)/future-pool/future-pool-view'

interface ReactivateDialogProps {
  open: boolean
  leads: FutureLeadRow[]
  employees: EmployeeRow[]
  onClose: () => void
  onSuccess: () => void
}

export function ReactivateDialog({
  open, leads, employees, onClose, onSuccess,
}: ReactivateDialogProps) {
  const router = useRouter()
  const [assignees, setAssignees] = useState<Record<string, string>>({})
  const [popOpenId, setPopOpenId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  const allAssigned = leads.length > 0 && leads.every((l) => Boolean(assignees[l.id]))

  function handleOpenChange(v: boolean) {
    if (!v) {
      setAssignees({})
      setPopOpenId(null)
      setError(null)
      onClose()
    }
  }

  function setAssignee(leadId: string, employeeId: string) {
    setAssignees((prev) => ({ ...prev, [leadId]: employeeId }))
    setPopOpenId(null)
  }

  function handleConfirm() {
    setError(null)
    const payload = leads.map((l) => ({
      lead_id: l.id,
      employee_id: assignees[l.id],
    }))

    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('reactivate_future_leads', {
        p_leads: payload,
      })
      if (rpcErr) {
        const msg = rpcErr.message ?? ''
        if (msg.includes('permission_denied')) {
          setError('Permission denied.')
        } else if (msg.includes('lead_not_found_or_not_future')) {
          setError('One or more leads are no longer in Future status. Refresh and retry.')
        } else if (msg.includes('target_not_assignable')) {
          setError('One or more selected employees cannot receive assignments.')
        } else {
          setError(msg || 'Reactivation failed.')
        }
        return
      }
      const n = leads.length
      toast.success(`${n} lead${n !== 1 ? 's' : ''} reactivated and assigned`)
      handleOpenChange(false)
      onSuccess()
      router.refresh()
    })
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">
            Reactivate &amp; Assign — {leads.length} lead{leads.length !== 1 ? 's' : ''}
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-3 py-1 max-h-[60vh] overflow-y-auto">
          {leads.map((lead) => {
            const selectedEmp = employees.find((e) => e.id === assignees[lead.id])
            const isOpen = popOpenId === lead.id
            return (
              <div key={lead.id} className="flex items-center gap-3 rounded-lg border px-3 py-2">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium truncate">
                    {lead.name ?? <span className="italic text-muted-foreground">Unnamed</span>}
                  </p>
                  {lead.interest_type && (
                    <p className="text-xs text-muted-foreground">{lead.interest_type}</p>
                  )}
                </div>
                <Popover open={isOpen} onOpenChange={(v) => setPopOpenId(v ? lead.id : null)}>
                  <PopoverTrigger asChild>
                    <Button
                      variant="outline"
                      role="combobox"
                      size="sm"
                      className="w-40 justify-between font-normal shrink-0"
                    >
                      <span className="truncate">
                        {selectedEmp?.username ?? 'Pick employee…'}
                      </span>
                      <ChevronsUpDown className="ml-1 size-3.5 shrink-0 opacity-50" />
                    </Button>
                  </PopoverTrigger>
                  <PopoverContent className="w-48 p-0" align="end">
                    <Command>
                      <CommandInput placeholder="Search…" />
                      <CommandList>
                        <CommandEmpty>No employee found.</CommandEmpty>
                        <CommandGroup>
                          {employees.map((emp) => (
                            <CommandItem
                              key={emp.id}
                              value={emp.username}
                              onSelect={() => setAssignee(lead.id, emp.id)}
                            >
                              <Check
                                className={cn(
                                  'mr-2 size-4',
                                  assignees[lead.id] === emp.id ? 'opacity-100' : 'opacity-0',
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
            )
          })}
        </div>

        {error && <p className="text-destructive text-sm">{error}</p>}

        <DialogFooter>
          <Button variant="ghost" onClick={() => handleOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button onClick={handleConfirm} disabled={pending || !allAssigned}>
            {pending ? 'Reactivating…' : 'Reactivate & Assign'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
