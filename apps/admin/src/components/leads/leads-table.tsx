"use client"
import { useState } from 'react'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { AssignDialog } from '@/components/leads/assign-dialog'
import { StatusPill } from '@/components/leads/status-pill'
import { BulkAssignDialog } from '@/components/leads/bulk-assign-dialog'

export interface LeadRow {
  id: string
  name: string | null
  phone_last4: string | null
  status: string
  assigned_to_user_id: string | null
  assignee_username: string | null
  assignment_deadline: string | null
  created_at: string
  total_count: number
}

export interface EmployeeRow { id: string; username: string }

function fmtDate(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  // Locked locale + IST so SSR + client render identical text (no hydration mismatch).
  // Tenant ops in India; matches DESIGN.md timezone default (Asia/Kolkata).
  return d.toLocaleString('en-IN', {
    timeZone: 'Asia/Kolkata',
    year: 'numeric', month: 'short', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  })
}

interface LeadsTableProps {
  leads: LeadRow[]
  employees: EmployeeRow[]
}

export function LeadsTable({ leads, employees }: LeadsTableProps) {
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())

  const allSelected = leads.length > 0 && leads.every((l) => selectedIds.has(l.id))
  const someSelected = leads.some((l) => selectedIds.has(l.id))

  function toggleAll() {
    if (allSelected) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(leads.map((l) => l.id)))
    }
  }

  function toggleRow(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  const selectedLeads = leads.filter((l) => selectedIds.has(l.id))

  return (
    <div className="space-y-3">
      {selectedIds.size >= 2 && (
        <div className="flex items-center gap-3 rounded-[12px] bg-evergreen px-4 py-2.5 text-ivory shadow-[var(--shadow-lg)]">
          <span className="text-sm font-semibold">
            {selectedIds.size} leads selected
          </span>
          <BulkAssignDialog
            selectedLeads={selectedLeads}
            employees={employees}
            onSuccess={() => setSelectedIds(new Set())}
          />
          <Button
            variant="ghost"
            size="sm"
            className="ml-auto text-ivory/70 hover:text-ivory hover:bg-white/10"
            onClick={() => setSelectedIds(new Set())}
          >
            Clear selection
          </Button>
        </div>
      )}

      <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-10">
                <input
                  type="checkbox"
                  checked={allSelected}
                  ref={(el) => { if (el) el.indeterminate = someSelected && !allSelected }}
                  onChange={toggleAll}
                  className="size-4 rounded border-input cursor-pointer"
                  aria-label="Select all leads"
                />
              </TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Phone</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Assigned to</TableHead>
              <TableHead>Deadline</TableHead>
              <TableHead>Created</TableHead>
              <TableHead className="text-right">Action</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {leads.map((l) => (
              <TableRow
                key={l.id}
                className="hover:bg-muted/40"
                data-selected={selectedIds.has(l.id)}
              >
                <TableCell>
                  <input
                    type="checkbox"
                    checked={selectedIds.has(l.id)}
                    onChange={() => toggleRow(l.id)}
                    className="size-4 rounded border-input cursor-pointer"
                    aria-label={`Select lead ${l.name ?? l.id}`}
                  />
                </TableCell>
                <TableCell className="font-medium">
                  {l.name ?? <span className="text-ink-3 italic">Unnamed</span>}
                </TableCell>
                <TableCell className="font-mono text-xs text-ink-3">
                  •••{l.phone_last4 ?? '----'}
                </TableCell>
                <TableCell><StatusPill status={l.status} /></TableCell>
                <TableCell>
                  {l.assignee_username ?? (
                    <span className="text-ink-3 italic">Unassigned</span>
                  )}
                </TableCell>
                <TableCell className="text-sm tabular-nums text-ink-2">
                  {fmtDate(l.assignment_deadline)}
                </TableCell>
                <TableCell className="text-sm tabular-nums text-ink-2">
                  {fmtDate(l.created_at)}
                </TableCell>
                <TableCell className="text-right">
                  <AssignDialog
                    leadId={l.id}
                    leadName={l.name}
                    phoneLast4={l.phone_last4}
                    currentAssigneeId={l.assigned_to_user_id}
                    currentDeadline={l.assignment_deadline}
                    employees={employees}
                  />
                </TableCell>
              </TableRow>
            ))}
            {leads.length === 0 && (
              <TableRow>
                <TableCell colSpan={8} className="text-center text-muted-foreground py-8">
                  No leads match these filters.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
