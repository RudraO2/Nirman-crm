'use client'

import { useState, useEffect, useRef } from 'react'
import { Button } from '@/components/ui/button'
import { getExportCountAction } from '@/app/(app)/export/actions'

type Employee = { id: string; username: string }
type Project  = { id: string; name: string }

interface Props {
  employees: Employee[]
  projects:  Project[]
}

const STATUS_OPTIONS = ['warm', 'cold', 'hot', 'dead', 'sold', 'future'] as const

const selectCls =
  'w-full rounded-[9px] border border-line-2 bg-paper px-3 py-2 text-sm text-ink ' +
  'ring-offset-background transition-colors ' +
  'focus:outline-none focus:ring-2 focus:ring-brass focus:ring-offset-2 ' +
  'disabled:cursor-not-allowed disabled:opacity-50'

export function ExportFilters({ employees, projects }: Props) {
  const [status,       setStatus]       = useState('')
  const [employeeId,   setEmployeeId]   = useState('')
  const [projectId,    setProjectId]    = useState('')
  const [propertyType, setPropertyType] = useState('')
  const [dateFrom,     setDateFrom]     = useState('')
  const [dateTo,       setDateTo]       = useState('')
  const [count,        setCount]        = useState<number | null>(null)
  const [loading,      setLoading]      = useState(true)

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    if (timerRef.current) clearTimeout(timerRef.current)
    let cancelled = false

    timerRef.current = setTimeout(async () => {
      setLoading(true)
      try {
        const n = await getExportCountAction({
          status:        status       || null,
          employeeId:    employeeId   || null,
          projectId:     projectId    || null,
          propertyType:  propertyType || null,
          dateFrom:      dateFrom     || null,
          dateTo:        dateTo       || null,
        })
        if (!cancelled) setCount(n)
      } catch {
        if (!cancelled) setCount(null)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }, 400)

    return () => {
      cancelled = true
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [status, employeeId, projectId, propertyType, dateFrom, dateTo])

  function buildHref(): string {
    const params = new URLSearchParams()
    if (status)       params.set('status',       status)
    if (employeeId)   params.set('employeeId',   employeeId)
    if (projectId)    params.set('projectId',    projectId)
    if (propertyType) params.set('propertyType', propertyType)
    if (dateFrom)     params.set('dateFrom',     dateFrom)
    if (dateTo)       params.set('dateTo',       dateTo)
    const qs = params.toString()
    return `/export/download${qs ? `?${qs}` : ''}`
  }

  const canExport = !loading && count !== null && count > 0

  return (
    <div className="space-y-6">
      {/* ── Filters card ── */}
      <div className="rounded-[14px] border border-line bg-paper p-6 space-y-5 shadow-[var(--shadow)]">
        <h2 className="text-base font-semibold leading-none">Filter Leads</h2>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-x-6 gap-y-4">
          {/* Status */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-muted-foreground">Status</label>
            <select
              className={selectCls}
              value={status}
              onChange={(e) => setStatus(e.target.value)}
            >
              <option value="">All statuses</option>
              {STATUS_OPTIONS.map((s) => (
                <option key={s} value={s}>
                  {s.charAt(0).toUpperCase() + s.slice(1)}
                </option>
              ))}
            </select>
          </div>

          {/* Employee */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-muted-foreground">Employee</label>
            <select
              className={selectCls}
              value={employeeId}
              onChange={(e) => setEmployeeId(e.target.value)}
            >
              <option value="">All employees</option>
              {employees.map((emp) => (
                <option key={emp.id} value={emp.id}>
                  {emp.username}
                </option>
              ))}
            </select>
          </div>

          {/* Project */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-muted-foreground">Project</label>
            <select
              className={selectCls}
              value={projectId}
              onChange={(e) => setProjectId(e.target.value)}
            >
              <option value="">All projects</option>
              {projects.map((proj) => (
                <option key={proj.id} value={proj.id}>
                  {proj.name}
                </option>
              ))}
            </select>
          </div>

          {/* Property Type */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-muted-foreground">Property Type</label>
            <input
              className={selectCls}
              type="text"
              placeholder="e.g. Apartment"
              value={propertyType}
              onChange={(e) => setPropertyType(e.target.value)}
            />
          </div>

          {/* Date From */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-muted-foreground">Created From</label>
            <input
              className={selectCls}
              type="date"
              value={dateFrom}
              onChange={(e) => setDateFrom(e.target.value)}
            />
          </div>

          {/* Date To */}
          <div className="space-y-1.5">
            <label className="text-xs font-medium text-muted-foreground">Created To</label>
            <input
              className={selectCls}
              type="date"
              value={dateTo}
              onChange={(e) => setDateTo(e.target.value)}
            />
          </div>
        </div>
      </div>

      {/* ── Action bar ── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div className="flex items-center gap-2.5 rounded-[10px] bg-mist px-4 py-2.5 text-sm text-ink-2">
          {loading ? (
            <span className="animate-pulse">Computing…</span>
          ) : count === null ? (
            <span className="text-danger">Could not load count</span>
          ) : (
            <>
              <span className="font-serif text-2xl font-medium tabular-nums text-ink">
                {count.toLocaleString()}
              </span>
              lead{count !== 1 ? 's' : ''} will be exported
            </>
          )}
        </div>

        <div className="flex items-center gap-4">
          <a
            href="/export/history"
            className="text-sm text-ink-2 underline underline-offset-4 hover:text-ink transition-colors"
          >
            View Export History
          </a>
          <Button
            size="default"
            disabled={!canExport}
            onClick={() => {
              if (canExport) window.location.href = buildHref()
            }}
          >
            Download Excel
          </Button>
        </div>
      </div>
    </div>
  )
}
