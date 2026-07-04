"use client"
import { useEffect, useState, useTransition } from 'react'
import { useRouter, useSearchParams, usePathname } from 'next/navigation'
import { Input } from '@/components/ui/input'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { Button } from '@/components/ui/button'

interface Employee { id: string; username: string }

interface LeadsToolbarProps {
  employees: Employee[]
  initialQ: string
  initialStatus: string
  initialEmployee: string
  initialArchived: boolean
}

const STATUSES = ['hot', 'warm', 'cold', 'dead', 'sold', 'future']

export function LeadsToolbar({
  employees, initialQ, initialStatus, initialEmployee, initialArchived,
}: LeadsToolbarProps) {
  const router = useRouter()
  const pathname = usePathname()
  const sp = useSearchParams()

  const [q, setQ] = useState(initialQ)
  const [status, setStatus] = useState(initialStatus || 'any')
  const [employee, setEmployee] = useState(initialEmployee || 'any')
  const [archived, setArchived] = useState(initialArchived)
  const [, startTransition] = useTransition()

  // Debounce q → URL. Skip the first effect run when q matches initialQ so we don't
  // bounce the URL on mount.
  useEffect(() => {
    if (q === initialQ) return
    const t = setTimeout(() => updateUrl({ q }), 300)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q])

  function updateUrl(patch: Record<string, string | boolean>) {
    const params = new URLSearchParams(sp.toString())
    const next = {
      q,
      status: status === 'any' ? '' : status,
      employee: employee === 'any' ? '' : employee,
      archived: archived ? '1' : '',
      ...patch,
    } as Record<string, string | boolean>
    Object.entries(next).forEach(([k, v]) => {
      if (v === '' || v === false) params.delete(k)
      else params.set(k, String(v))
    })
    params.delete('page')
    startTransition(() => {
      router.replace(`${pathname}?${params.toString()}`)
    })
  }

  return (
    <div className="flex flex-wrap items-center gap-3 rounded-[14px] border border-line bg-paper p-3 shadow-[var(--shadow)]">
      <Input
        type="search"
        placeholder="Search name or phone…"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        className="max-w-xs"
      />
      <Select
        value={status}
        onValueChange={(v) => { setStatus(v); updateUrl({ status: v === 'any' ? '' : v }) }}
      >
        <SelectTrigger className="w-[140px]"><SelectValue placeholder="Status" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="any">Any status</SelectItem>
          {STATUSES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}
        </SelectContent>
      </Select>
      <Select
        value={employee}
        onValueChange={(v) => { setEmployee(v); updateUrl({ employee: v === 'any' ? '' : v }) }}
      >
        <SelectTrigger className="w-[200px]"><SelectValue placeholder="Employee" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="any">Any employee</SelectItem>
          <SelectItem value="__unassigned__">Unassigned</SelectItem>
          {employees.map((e) => (
            <SelectItem key={e.id} value={e.id}>{e.username}</SelectItem>
          ))}
        </SelectContent>
      </Select>
      {/* Archived is now expressed by the Archived tab (§2); the URL param and
          server logic are unchanged — the checkbox is just retired here. */}
      {(q || status !== 'any' || employee !== 'any' || archived) && (
        <Button
          variant="ghost"
          size="sm"
          onClick={() => {
            setQ(''); setStatus('any'); setEmployee('any'); setArchived(false)
            router.replace(pathname)
          }}
        >
          Clear filters
        </Button>
      )}
    </div>
  )
}
