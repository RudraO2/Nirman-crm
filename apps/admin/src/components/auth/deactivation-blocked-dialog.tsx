"use client"
import { useEffect, useState, useTransition } from 'react'
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
import { Check, ChevronsUpDown, Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import { StatusPill } from '@/components/leads/status-pill'

interface Lead {
  id: string
  name: string | null
  phone_last4: string | null
  status: string
}

interface Employee {
  id: string
  username: string
}

interface DeactivationBlockedDialogProps {
  employeeId: string
  employeeName: string
  open: boolean
  onOpenChange: (v: boolean) => void
  onSuccess: () => void
}

export function DeactivationBlockedDialog({
  employeeId, employeeName, open, onOpenChange, onSuccess,
}: DeactivationBlockedDialogProps) {
  const [leads, setLeads] = useState<Lead[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [fetchingLeads, setFetchingLeads] = useState(false)
  const [assignments, setAssignments] = useState<Record<string, string>>({})
  const [openPop, setOpenPop] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  useEffect(() => {
    if (!open) {
      setAssignments({})
      setError(null)
      return
    }
    setFetchingLeads(true)
    setError(null)
    const supabase = createClient()

    Promise.all([
      supabase.rpc('list_assignable_leads', {
        p_employee: employeeId,
        p_limit: 200,
      }),
      supabase.rpc('list_employees_for_assignment'),
    ]).then(([leadsRes, empsRes]) => {
      if (leadsRes.error) {
        setError(leadsRes.error.message ?? 'Failed to load leads.')
      } else {
        setLeads(
          ((leadsRes.data ?? []) as Lead[]).filter(
            (l) => !['dead', 'sold', 'future'].includes(l.status)
          )
        )
      }
      if (!empsRes.error) {
        setEmployees(
          ((empsRes.data ?? []) as { id: string; username: string }[]).filter(
            (e) => e.id !== employeeId
          )
        )
      }
      setFetchingLeads(false)
    })
  }, [open, employeeId])

  const allAssigned =
    leads.length > 0 && leads.every((l) => Boolean(assignments[l.id]))

  function handleConfirm() {
    setError(null)
    startTransition(async () => {
      const supabase = createClient()
      for (const lead of leads) {
        const targetId = assignments[lead.id]
        if (!targetId) {
          setError(`No assignee selected for "${lead.name ?? 'lead'}".`)
          return
        }
        const { error: rpcErr } = await supabase.rpc('assign_lead', {
          p_lead_id: lead.id,
          p_target_user_id: targetId,
        })
        if (rpcErr) {
          const msg = rpcErr.message ?? ''
          if (msg.includes('permission_denied'))
            setError('Permission denied reassigning a lead.')
          else if (msg.includes('target_not_assignable'))
            setError('Selected employee cannot receive assignments.')
          else
            setError(msg || `Failed to reassign "${lead.name ?? 'lead'}".`)
          return
        }
      }

      const { data, error: fnError } = await supabase.functions.invoke('manage-employee', {
        body: { action: 'deactivate', targetUserId: employeeId },
      })
      if (fnError || data?.error) {
        setError(data?.error?.message ?? fnError?.message ?? 'Deactivation failed.')
        return
      }

      onSuccess()
    })
  }

  const selectedUsername = (leadId: string) =>
    employees.find((e) => e.id === assignments[leadId])?.username ?? null

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[80vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">
            Reassign leads before deactivating {employeeName}
          </DialogTitle>
          <p className="text-sm text-muted-foreground pt-1">
            This employee has {leads.length > 0 ? leads.length : '…'} active lead
            {leads.length !== 1 ? 's' : ''} that must be reassigned before deactivation.
          </p>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto min-h-0 py-2">
          {fetchingLeads ? (
            <div className="flex items-center justify-center py-10 gap-2 text-muted-foreground text-sm">
              <Loader2 className="size-4 animate-spin" />
              Loading leads…
            </div>
          ) : leads.length === 0 && !error ? (
            <p className="text-sm text-muted-foreground py-4 text-center">No active leads found.</p>
          ) : (
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-muted-foreground text-xs">
                  <th className="text-left pb-2 font-medium pl-1">Lead</th>
                  <th className="text-left pb-2 font-medium">Status</th>
                  <th className="text-left pb-2 font-medium">Assign to</th>
                </tr>
              </thead>
              <tbody>
                {leads.map((lead) => (
                  <tr key={lead.id} className="border-b last:border-0">
                    <td className="py-2 pl-1">
                      <span className="font-medium">{lead.name ?? 'Unnamed'}</span>
                      {lead.phone_last4 && (
                        <span className="ml-2 font-mono text-xs text-muted-foreground">
                          •••{lead.phone_last4}
                        </span>
                      )}
                    </td>
                    <td className="py-2 pr-4">
                      <StatusPill status={lead.status} />
                    </td>
                    <td className="py-2 min-w-[180px]">
                      <Popover
                        open={openPop === lead.id}
                        onOpenChange={(v) => setOpenPop(v ? lead.id : null)}
                      >
                        <PopoverTrigger asChild>
                          <Button
                            variant="outline"
                            role="combobox"
                            aria-expanded={openPop === lead.id}
                            className="w-full justify-between font-normal text-sm h-8"
                          >
                            {selectedUsername(lead.id) ?? 'Pick employee…'}
                            <ChevronsUpDown className="ml-2 size-3.5 shrink-0 opacity-50" />
                          </Button>
                        </PopoverTrigger>
                        <PopoverContent className="w-[220px] p-0">
                          <Command>
                            <CommandInput placeholder="Search…" />
                            <CommandList>
                              <CommandEmpty>No employee found.</CommandEmpty>
                              <CommandGroup>
                                {employees.map((emp) => (
                                  <CommandItem
                                    key={emp.id}
                                    value={emp.username}
                                    onSelect={() => {
                                      setAssignments((prev) => ({ ...prev, [lead.id]: emp.id }))
                                      setOpenPop(null)
                                    }}
                                  >
                                    <Check
                                      className={cn(
                                        'mr-2 size-4',
                                        assignments[lead.id] === emp.id ? 'opacity-100' : 'opacity-0'
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
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {error && <p className="text-destructive text-sm px-1">{error}</p>}

        <DialogFooter className="pt-2">
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button
            variant="destructive"
            onClick={handleConfirm}
            disabled={pending || fetchingLeads || !allAssigned}
          >
            {pending ? (
              <><Loader2 className="mr-2 size-4 animate-spin" /> Reassigning…</>
            ) : (
              'Reassign & Deactivate'
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
