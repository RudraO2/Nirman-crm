"use client"
import { useState, useEffect, useCallback, useRef } from 'react'
import { Search } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import {
  Command,
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from '@/components/ui/command'
import { StatusPill } from '@/components/leads/status-pill'
import { AssignDialog } from '@/components/leads/assign-dialog'

interface SearchResult {
  id: string
  name: string | null
  phone_last4: string | null
  status: string
  assigned_to_user_id: string | null
  assignee_username: string | null
}

interface Employee { id: string; username: string }

export function GlobalSearch() {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<SearchResult[]>([])
  const [employees, setEmployees] = useState<Employee[]>([])
  const [loading, setLoading] = useState(false)
  const [assignTarget, setAssignTarget] = useState<SearchResult | null>(null)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  // ⌘K / Ctrl+K toggle
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault()
        setOpen((v) => !v)
      }
    }
    document.addEventListener('keydown', onKeyDown)
    return () => document.removeEventListener('keydown', onKeyDown)
  }, [])

  // Fetch employees once per overlay open (cached after first load)
  useEffect(() => {
    if (!open || employees.length > 0) return
    createClient()
      .rpc('list_employees_for_assignment')
      .then(({ data }) => { if (data) setEmployees(data as Employee[]) })
  }, [open, employees.length])

  // Reset query + results on close
  useEffect(() => {
    if (!open) {
      setQuery('')
      setResults([])
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [open])

  const runSearch = useCallback((q: string) => {
    if (debounceRef.current) clearTimeout(debounceRef.current)
    const trimmed = q.trim()
    if (!trimmed) { setResults([]); setLoading(false); return }
    setLoading(true)
    debounceRef.current = setTimeout(async () => {
      try {
        const { data } = await createClient().rpc('search_leads_global', { p_q: trimmed })
        setResults((data ?? []) as SearchResult[])
      } finally {
        setLoading(false)
      }
    }, 300)
  }, [])

  function handleAssign(r: SearchResult) {
    setOpen(false)
    setAssignTarget(r)
  }

  const resultLabel = results.length === 50
    ? '50+ results'
    : `${results.length} result${results.length === 1 ? '' : 's'}`

  return (
    <>
      {/* Header trigger button */}
      <Button
        variant="outline"
        size="sm"
        className="h-8 gap-2 px-3 text-muted-foreground"
        onClick={() => setOpen(true)}
        aria-label="Search leads (⌘K)"
      >
        <Search className="size-3.5 shrink-0" />
        <span className="hidden sm:inline text-sm">Search</span>
        <kbd className="hidden sm:inline-flex h-5 select-none items-center rounded border bg-muted px-1.5 font-mono text-[10px] opacity-70">
          ⌘K
        </kbd>
      </Button>

      {/* Search overlay */}
      <CommandDialog
        open={open}
        onOpenChange={setOpen}
        title="Search leads"
        description="Search all leads by name or phone number"
      >
        <Command shouldFilter={false}>
          <CommandInput
            placeholder="Name or phone…"
            value={query}
            onValueChange={(v) => { setQuery(v); runSearch(v) }}
          />
          <CommandList>
            {loading && (
              <div className="py-6 text-center text-sm text-muted-foreground">
                Searching…
              </div>
            )}
            {!loading && query.trim() && results.length === 0 && (
              <CommandEmpty>No leads found.</CommandEmpty>
            )}
            {!loading && results.length > 0 && (
              <CommandGroup heading={resultLabel}>
                {results.map((r) => (
                  <CommandItem
                    key={r.id}
                    value={r.id}
                    className="flex items-center gap-3 py-2"
                    onSelect={() => {}}
                  >
                    <StatusPill status={r.status} />
                    <span className="flex-1 min-w-0 truncate font-medium">
                      {r.name ?? (
                        <em className="text-muted-foreground not-italic">Unnamed</em>
                      )}
                    </span>
                    <span className="shrink-0 font-mono text-xs text-muted-foreground">
                      •••{r.phone_last4 ?? '----'}
                    </span>
                    <span className="shrink-0 text-xs text-muted-foreground">
                      {r.assignee_username ?? (
                        <em className="not-italic">Unassigned</em>
                      )}
                    </span>
                    <Button
                      size="sm"
                      variant="outline"
                      className="h-6 shrink-0 px-2 text-xs"
                      onClick={(e) => { e.stopPropagation(); handleAssign(r) }}
                    >
                      Assign
                    </Button>
                  </CommandItem>
                ))}
              </CommandGroup>
            )}
          </CommandList>
        </Command>
      </CommandDialog>

      {/* AssignDialog rendered outside the overlay to avoid nested-modal focus trap */}
      {assignTarget && (
        <AssignDialog
          key={assignTarget.id}
          leadId={assignTarget.id}
          leadName={assignTarget.name}
          phoneLast4={assignTarget.phone_last4}
          currentAssigneeId={assignTarget.assigned_to_user_id}
          currentDeadline={null}
          employees={employees}
          initialOpen
          onClose={() => setAssignTarget(null)}
        />
      )}
    </>
  )
}
