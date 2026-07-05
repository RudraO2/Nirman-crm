'use client'

import { useState, useTransition, useRef, useEffect, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { parseExcelAction, checkPhoneHashesAction, importLeadsAction } from '@/app/(app)/import/actions'
import type { ParseResult, ImportResult, CrmField } from '@/app/(app)/import/types'

type Step = 'upload' | 'map' | 'preview' | 'assign' | 'done'

const CRM_FIELDS: (CrmField | 'Ignore')[] = [
  'Name', 'Phone', 'Project', 'PropertyType', 'Location',
  'Budget', 'TicketSize', 'Source', 'Remarks', 'Ignore',
]

const STEPS: { key: Step; label: string }[] = [
  { key: 'upload', label: 'Upload' },
  { key: 'map', label: 'Map' },
  { key: 'preview', label: 'Preview' },
  { key: 'assign', label: 'Assign' },
  { key: 'done', label: 'Done' },
]

interface Props {
  employees: { id: string; name: string }[]
}

export function ImportWizard({ employees }: Props) {
  const [step, setStep] = useState<Step>('upload')
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const [parseResult, setParseResult] = useState<ParseResult | null>(null)
  const [mappings, setMappings] = useState<Record<string, string | null>>({})
  const [crossDbDupes, setCrossDbDupes] = useState<number>(0)
  const [crossDbLoading, setCrossDbLoading] = useState(false)
  const [selectedEmployees, setSelectedEmployees] = useState<string[]>([])
  const [importResult, setImportResult] = useState<ImportResult | null>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [dragging, setDragging] = useState(false)

  const handleFile = useCallback((file: File) => {
    setError(null)
    startTransition(async () => {
      try {
        const formData = new FormData()
        formData.append('file', file)
        const result = await parseExcelAction(formData)
        setParseResult(result)
        setMappings(result.mappings)
        const hasUnmatched = Object.values(result.mappings).some((m) => m === null)
        setStep(hasUnmatched ? 'map' : 'preview')
      } catch (e) {
        setError((e as Error).message)
      }
    })
  }, [])

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault()
      setDragging(false)
      const file = e.dataTransfer.files[0]
      if (file) handleFile(file)
    },
    [handleFile]
  )

  useEffect(() => {
    if (step !== 'preview' || !parseResult) return
    setCrossDbLoading(true)
    const phoneHeader = parseResult.columns.find((c) => mappings[c] === 'Phone')
    const phones = phoneHeader ? parseResult.rows.map((r) => r[phoneHeader]).filter(Boolean) : []
    checkPhoneHashesAction(phones)
      .then((matched) => setCrossDbDupes(matched.length))
      .catch(() => setCrossDbDupes(0))
      .finally(() => setCrossDbLoading(false))
  }, [step, parseResult])

  function reset() {
    setStep('upload')
    setParseResult(null)
    setMappings({})
    setCrossDbDupes(0)
    setSelectedEmployees([])
    setImportResult(null)
    setError(null)
    if (fileInputRef.current) fileInputRef.current.value = ''
  }

  function handleImport() {
    if (!parseResult || selectedEmployees.length === 0) return
    setError(null)
    startTransition(async () => {
      try {
        const activeMappings: Record<string, string> = {}
        for (const [col, val] of Object.entries(mappings)) {
          if (val && val !== 'Ignore') activeMappings[col] = val
        }
        const result = await importLeadsAction(parseResult.rows, activeMappings, selectedEmployees)
        setImportResult(result)
        setStep('done')
      } catch (e) {
        setError((e as Error).message)
      }
    })
  }

  const stepIndex = STEPS.findIndex((s) => s.key === step)

  return (
    <div className="space-y-6">
      {/* Step indicator */}
      <div className="flex items-center gap-0">
        {STEPS.map((s, i) => (
          <div key={s.key} className="flex items-center">
            <div className="flex items-center gap-1.5">
              <div
                className={[
                  'flex h-[26px] w-[26px] items-center justify-center rounded-full text-xs font-bold',
                  i < stepIndex
                    ? 'bg-sold text-white'
                    : i === stepIndex
                    ? 'bg-evergreen text-ivory'
                    : 'border-2 border-line-2 bg-paper text-ink-3',
                ].join(' ')}
              >
                {i < stepIndex ? '✓' : i + 1}
              </div>
              <span
                className={[
                  'text-[12.5px] font-semibold',
                  i <= stepIndex ? 'text-ink' : 'text-ink-3',
                ].join(' ')}
              >
                {s.label}
              </span>
            </div>
            {i < STEPS.length - 1 && (
              <div className="mx-2.5 h-0.5 w-8 min-w-5 flex-1 bg-line" />
            )}
          </div>
        ))}
      </div>

      {error && <p className="text-danger text-sm">{error}</p>}

      {/* Upload step */}
      {step === 'upload' && (
        <div
          onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
          onDragLeave={() => setDragging(false)}
          onDrop={handleDrop}
          className={[
            'rounded-[16px] border-2 border-dashed bg-paper p-10 text-center transition-colors',
            dragging ? 'border-brass bg-brass-soft/30' : 'border-line-2',
            isPending ? 'pointer-events-none opacity-60' : 'cursor-pointer',
          ].join(' ')}
          onClick={() => fileInputRef.current?.click()}
        >
          <input
            ref={fileInputRef}
            type="file"
            accept=".xlsx,.xls"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0]
              if (file) handleFile(file)
            }}
          />
          <div className="space-y-2">
            <div className="text-4xl text-brass">↑</div>
            <p className="text-[15px] font-semibold">
              {isPending ? 'Parsing file…' : 'Drop an Excel file here or click to browse'}
            </p>
            <p className="text-xs text-ink-2">Accepts .xlsx and .xls files</p>
          </div>
        </div>
      )}

      {/* Map step */}
      {step === 'map' && parseResult && (
        <div className="space-y-4">
          <p className="text-sm text-ink-2">
            Review detected column mappings. Manually map any unmatched columns or mark them as Ignore.
          </p>
          <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Excel Column</TableHead>
                  <TableHead>Detected As</TableHead>
                  <TableHead>Map To</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {parseResult.columns.map((col) => {
                  const current = mappings[col]
                  const isAutoMapped = parseResult.mappings[col] !== null
                  return (
                    <TableRow key={col} className={isAutoMapped ? '' : 'bg-warm-bg/50'}>
                      <TableCell className="font-mono text-sm">{col}</TableCell>
                      <TableCell className="text-sm text-ink-2">
                        {isAutoMapped ? (
                          <span className="rounded-sm bg-mist px-1.5 py-0.5 text-xs">
                            {parseResult.mappings[col]}
                          </span>
                        ) : (
                          <span className="text-ink-3">—</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {isAutoMapped ? (
                          <span className="text-sm text-ink-2">{current}</span>
                        ) : (
                          <select
                            className="rounded-[9px] border border-line-2 bg-paper px-2 py-1 text-sm"
                            value={current ?? ''}
                            onChange={(e) =>
                              setMappings((prev) => ({
                                ...prev,
                                [col]: e.target.value || null,
                              }))
                            }
                          >
                            <option value="">— Select field —</option>
                            {CRM_FIELDS.map((f) => (
                              <option key={f} value={f}>
                                {f}
                              </option>
                            ))}
                          </select>
                        )}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </div>
          <div className="flex justify-end">
            <Button onClick={() => setStep('preview')}>Continue to Preview</Button>
          </div>
        </div>
      )}

      {/* Preview step */}
      {step === 'preview' && parseResult && (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
            {[
              { label: 'Total rows', value: parseResult.totalRows },
              {
                label: 'Rows to import',
                value:
                  parseResult.totalRows -
                  parseResult.intraFileDupes -
                  parseResult.missingPhoneCount,
              },
              { label: 'Intra-file duplicates', value: parseResult.intraFileDupes },
              {
                label: 'Cross-db duplicates',
                value: crossDbLoading ? '…' : crossDbDupes,
              },
              { label: 'Missing phone (rejected)', value: parseResult.missingPhoneCount },
            ].map((stat) => (
              <div key={stat.label} className="rounded-[14px] border border-line bg-paper p-4 shadow-[var(--shadow)]">
                <p className="text-xs text-ink-2">{stat.label}</p>
                <p className="mt-1 font-serif text-2xl font-medium tabular-nums text-ink">{stat.value}</p>
              </div>
            ))}
          </div>

          <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)]">
            <Table>
              <TableHeader>
                <TableRow>
                  {Object.entries(mappings)
                    .filter(([, v]) => v && v !== 'Ignore')
                    .map(([col, field]) => (
                      <TableHead key={col}>{field}</TableHead>
                    ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {parseResult.preview.map((row, i) => (
                  <TableRow key={i}>
                    {Object.entries(mappings)
                      .filter(([, v]) => v && v !== 'Ignore')
                      .map(([col]) => (
                        <TableCell key={col} className="text-sm">
                          {row[col] ?? '—'}
                        </TableCell>
                      ))}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>

          <div className="flex justify-end">
            <Button onClick={() => setStep('assign')}>Select Employees</Button>
          </div>
        </div>
      )}

      {/* Assign step */}
      {step === 'assign' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-base font-medium">Assign to Employees</h2>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                onClick={() => setSelectedEmployees(employees.map((e) => e.id))}
              >
                Select All
              </Button>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setSelectedEmployees([])}
              >
                Deselect All
              </Button>
            </div>
          </div>

          <div className="rounded-[14px] border border-line bg-paper shadow-[var(--shadow)] divide-y divide-line">
            {employees.map((emp) => {
              const checked = selectedEmployees.includes(emp.id)
              return (
                <label
                  key={emp.id}
                  className="flex cursor-pointer items-center gap-3 px-4 py-3 hover:bg-mist/50"
                >
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={(e) =>
                      setSelectedEmployees((prev) =>
                        e.target.checked ? [...prev, emp.id] : prev.filter((id) => id !== emp.id)
                      )
                    }
                    className="h-4 w-4 rounded border-border"
                  />
                  <span className="text-sm">{emp.name}</span>
                </label>
              )
            })}
            {employees.length === 0 && (
              <p className="px-4 py-3 text-sm text-muted-foreground">No active employees found.</p>
            )}
          </div>

          <div className="relative flex justify-end">
            {isPending && (
              <div className="absolute inset-0 flex items-center justify-center rounded-md bg-background/60">
                <span className="text-sm text-muted-foreground">Importing…</span>
              </div>
            )}
            <Button
              disabled={selectedEmployees.length === 0 || isPending}
              onClick={handleImport}
            >
              Distribute Equally &amp; Import
            </Button>
          </div>
        </div>
      )}

      {/* Done step */}
      {step === 'done' && importResult && (
        <div className="space-y-4">
          <div className="rounded-[14px] border border-line bg-paper p-6 space-y-4 shadow-[var(--shadow)]">
            <h2 className="font-serif text-lg font-medium">Import Complete</h2>
            <div className="grid grid-cols-3 gap-4">
              {[
                { label: 'Imported', value: importResult.imported },
                { label: 'Duplicates skipped', value: importResult.duplicates_skipped },
                { label: 'Errors', value: importResult.errors },
              ].map((stat) => (
                <div key={stat.label} className="rounded-[12px] border border-line bg-ivory p-4">
                  <p className="text-xs text-ink-2">{stat.label}</p>
                  <p className="mt-1 font-serif text-2xl font-medium tabular-nums text-ink">{stat.value}</p>
                </div>
              ))}
            </div>
            <p className="text-xs text-ink-3 font-mono">Batch: {importResult.batch_id}</p>
          </div>
          <div className="flex justify-end">
            <Button variant="outline" onClick={reset}>
              Import Another File
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
