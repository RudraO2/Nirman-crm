"use client"
import { useState } from 'react'
import Link from 'next/link'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { ReactivateDialog } from '@/components/leads/reactivate-dialog'
import type { LeadRow, EmployeeRow } from '@/components/leads/leads-table'

export interface FutureLeadRow extends LeadRow {
  interest_type: string | null
}

function daysSince(iso: string): number {
  return Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)
}

interface FuturePoolViewProps {
  leads: FutureLeadRow[]
  employees: EmployeeRow[]
  interestTypeFilter: string
  projectMatch: string
  matchCount: number
}

export function FuturePoolView({
  leads, employees, interestTypeFilter, projectMatch, matchCount,
}: FuturePoolViewProps) {
  const [bannerDismissed, setBannerDismissed] = useState(false)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [dialogOpen, setDialogOpen] = useState(false)
  const [dialogLeads, setDialogLeads] = useState<FutureLeadRow[]>([])

  const filteredLeads = interestTypeFilter
    ? leads.filter((l) => l.interest_type === interestTypeFilter)
    : leads

  const distinctTypes = Array.from(
    new Set(leads.map((l) => l.interest_type).filter(Boolean) as string[])
  ).sort()

  const allSelected = filteredLeads.length > 0 && filteredLeads.every((l) => selectedIds.has(l.id))
  const someSelected = filteredLeads.some((l) => selectedIds.has(l.id))
  const selectedLeads = filteredLeads.filter((l) => selectedIds.has(l.id))

  function toggleAll() {
    if (allSelected) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(filteredLeads.map((l) => l.id)))
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

  function filterHref(type: string): string {
    const params = new URLSearchParams()
    if (type) params.set('interestType', type)
    if (projectMatch) params.set('projectMatch', projectMatch)
    if (matchCount > 0) params.set('matchCount', String(matchCount))
    const qs = params.toString()
    return qs ? `/future-pool?${qs}` : '/future-pool'
  }

  function openDialogWith(targetLeads: FutureLeadRow[]) {
    if (targetLeads.length === 0) return
    setDialogLeads(targetLeads)
    setDialogOpen(true)
  }

  function handleDialogSuccess() {
    setSelectedIds(new Set())
    setBannerDismissed(true)
  }

  const showBanner = Boolean(projectMatch) && matchCount > 0 && !bannerDismissed

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Future Pool</h1>
          <p className="text-sm text-muted-foreground">
            {filteredLeads.length} future lead{filteredLeads.length !== 1 ? 's' : ''}
            {interestTypeFilter ? ` · ${interestTypeFilter}` : ''}
          </p>
        </div>
      </div>

      {/* Project-match banner */}
      {showBanner && (
        <div className="flex items-center justify-between rounded-lg border border-blue-300 bg-blue-50 dark:bg-blue-900/20 px-4 py-3">
          <p className="text-sm font-medium text-blue-800 dark:text-blue-200">
            {matchCount} Future Lead{matchCount !== 1 ? 's' : ''} match this new Project. Review and reactivate?
          </p>
          <div className="flex items-center gap-2 shrink-0 ml-4">
            <Button
              size="sm"
              onClick={() => openDialogWith(filteredLeads)}
            >
              Review
            </Button>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => setBannerDismissed(true)}
              aria-label="Dismiss"
            >
              ✕
            </Button>
          </div>
        </div>
      )}

      {/* Filter chips */}
      {distinctTypes.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs text-muted-foreground">Filter:</span>
          <Link href={filterHref('')}>
            <Badge
              variant={!interestTypeFilter ? 'default' : 'outline'}
              className="cursor-pointer"
            >
              All
            </Badge>
          </Link>
          {distinctTypes.map((t) => (
            <Link key={t} href={filterHref(t)}>
              <Badge
                variant={interestTypeFilter === t ? 'default' : 'outline'}
                className="cursor-pointer"
              >
                {t}
              </Badge>
            </Link>
          ))}
        </div>
      )}

      {/* Bulk action bar */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 rounded-lg border border-primary/20 bg-primary/5 px-4 py-2">
          <span className="text-sm font-medium text-primary">
            {selectedIds.size} lead{selectedIds.size !== 1 ? 's' : ''} selected
          </span>
          <Button size="sm" onClick={() => openDialogWith(selectedLeads)}>
            Reactivate selected
          </Button>
          <Button
            variant="ghost"
            size="sm"
            className="ml-auto text-muted-foreground"
            onClick={() => setSelectedIds(new Set())}
          >
            Clear
          </Button>
        </div>
      )}

      {/* Table */}
      <div className="rounded-lg border">
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
                  aria-label="Select all"
                />
              </TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Employee</TableHead>
              <TableHead>Interest Type</TableHead>
              <TableHead>Days in Future</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filteredLeads.map((lead) => (
              <TableRow key={lead.id} className="hover:bg-muted/40">
                <TableCell>
                  <input
                    type="checkbox"
                    checked={selectedIds.has(lead.id)}
                    onChange={() => toggleRow(lead.id)}
                    className="size-4 rounded border-input cursor-pointer"
                    aria-label={`Select ${lead.name ?? lead.id}`}
                  />
                </TableCell>
                <TableCell className="font-medium">
                  {lead.name ?? <span className="italic text-muted-foreground">Unnamed</span>}
                </TableCell>
                <TableCell>
                  {lead.assignee_username ?? (
                    <span className="italic text-muted-foreground">Unassigned</span>
                  )}
                </TableCell>
                <TableCell>
                  {lead.interest_type ? (
                    <Badge variant="secondary">{lead.interest_type}</Badge>
                  ) : (
                    <span className="text-muted-foreground">—</span>
                  )}
                </TableCell>
                <TableCell className="text-muted-foreground">
                  {daysSince(lead.created_at)}d
                </TableCell>
              </TableRow>
            ))}
            {filteredLeads.length === 0 && (
              <TableRow>
                <TableCell colSpan={5} className="text-center text-muted-foreground py-8">
                  {interestTypeFilter
                    ? `No future leads with interest type "${interestTypeFilter}".`
                    : 'No future leads.'}
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <ReactivateDialog
        open={dialogOpen}
        leads={dialogLeads}
        employees={employees}
        onClose={() => setDialogOpen(false)}
        onSuccess={handleDialogSuccess}
      />
    </div>
  )
}
