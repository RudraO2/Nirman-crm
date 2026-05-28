"use client"
import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import type { ProjectRow } from './page'

const PROPERTY_TYPES = ['Flat', 'Plot', 'Villa', 'Commercial', 'Studio', 'Penthouse']
// Radix Select forbids empty-string item values. Use a sentinel and translate to null on save.
const NONE_VALUE = '__none__'

// ── New Project Form ──────────────────────────────────────────────────────────

function NewProjectForm() {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [propertyType, setPropertyType] = useState<string>(NONE_VALUE)
  const [isActive, setIsActive] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  const propertyTypeDb = propertyType === NONE_VALUE ? null : propertyType

  function reset() {
    setName('')
    setPropertyType(NONE_VALUE)
    setIsActive(true)
    setError(null)
  }

  function handleOpenChange(v: boolean) {
    setOpen(v)
    if (!v) reset()
  }

  function handleSubmit() {
    setError(null)
    if (!name.trim()) { setError('Name is required.'); return }

    startTransition(async () => {
      const supabase = createClient()

      const { data: inserted, error: insertErr } = await supabase
        .from('projects')
        .insert({
          name: name.trim(),
          property_type: propertyTypeDb,
          is_active: isActive,
        })
        .select('id')
        .single()

      if (insertErr) {
        setError(insertErr.message || 'Failed to create project.')
        return
      }

      const projectId = inserted?.id ?? ''
      toast.success(`Project "${name.trim()}" created`)
      setOpen(false)
      reset()
      router.refresh()

      if (propertyTypeDb) {
        const { data: countData, error: countErr } = await supabase
          .rpc('get_future_pool_match_count', { p_property_type: propertyTypeDb })

        if (!countErr && typeof countData === 'number' && countData > 0) {
          router.push(
            `/future-pool?projectMatch=${encodeURIComponent(projectId)}&matchCount=${countData}&interestType=${encodeURIComponent(propertyTypeDb)}`
          )
          return
        }
      }

      router.push('/projects')
    })
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogTrigger asChild>
        <Button size="sm">New Project</Button>
      </DialogTrigger>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">New Project</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="proj-name">Name *</Label>
            <Input
              id="proj-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Prestige Sunrise"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="proj-type">Property Type</Label>
            <Select value={propertyType} onValueChange={setPropertyType}>
              <SelectTrigger id="proj-type" className="w-full">
                <SelectValue placeholder="— None —" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NONE_VALUE}>— None —</SelectItem>
                {PROPERTY_TYPES.map((t) => (
                  <SelectItem key={t} value={t}>{t}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div className="flex items-center gap-3">
            <input
              id="proj-active"
              type="checkbox"
              checked={isActive}
              onChange={(e) => setIsActive(e.target.checked)}
              className="size-4 rounded border-input cursor-pointer"
            />
            <Label htmlFor="proj-active" className="cursor-pointer">Active</Label>
          </div>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => handleOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button onClick={handleSubmit} disabled={pending || !name.trim()}>
            {pending ? 'Creating…' : 'Create'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Inline Row Editor ─────────────────────────────────────────────────────────

interface RowEditorProps {
  project: ProjectRow
  onSaved: () => void
  onCancel: () => void
}

function RowEditor({ project, onSaved, onCancel }: RowEditorProps) {
  const [name, setName] = useState(project.name)
  const [propertyType, setPropertyType] = useState(project.property_type ?? NONE_VALUE)
  const [isActive, setIsActive] = useState(project.is_active)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  function handleSave() {
    setError(null)
    if (!name.trim()) { setError('Name required.'); return }

    startTransition(async () => {
      const supabase = createClient()
      const { error: updErr } = await supabase
        .from('projects')
        .update({
          name: name.trim(),
          property_type: propertyType === NONE_VALUE ? null : propertyType,
          is_active: isActive,
        })
        .eq('id', project.id)

      if (updErr) {
        setError(updErr.message || 'Update failed.')
        return
      }
      toast.success('Project updated')
      onSaved()
    })
  }

  return (
    <>
      <TableCell>
        <Input
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="h-7 text-sm"
        />
      </TableCell>
      <TableCell>
        <Select value={propertyType} onValueChange={setPropertyType}>
          <SelectTrigger className="h-7 text-sm w-36">
            <SelectValue placeholder="— None —" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="">— None —</SelectItem>
            {PROPERTY_TYPES.map((t) => (
              <SelectItem key={t} value={t}>{t}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </TableCell>
      <TableCell>
        <input
          type="checkbox"
          checked={isActive}
          onChange={(e) => setIsActive(e.target.checked)}
          className="size-4 rounded border-input cursor-pointer"
        />
      </TableCell>
      <TableCell />
      <TableCell className="text-right space-x-2">
        {error && <span className="text-destructive text-xs mr-2">{error}</span>}
        <Button size="sm" variant="ghost" onClick={onCancel} disabled={pending}>Cancel</Button>
        <Button size="sm" onClick={handleSave} disabled={pending || !name.trim()}>
          {pending ? 'Saving…' : 'Save'}
        </Button>
      </TableCell>
    </>
  )
}

// ── Main Client ───────────────────────────────────────────────────────────────

interface ProjectsClientProps {
  initialProjects: ProjectRow[]
}

export function ProjectsClient({ initialProjects }: ProjectsClientProps) {
  const router = useRouter()
  const [editingId, setEditingId] = useState<string | null>(null)

  function handleSaved() {
    setEditingId(null)
    router.refresh()
  }

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Projects</h1>
          <p className="text-sm text-muted-foreground">
            {initialProjects.length} project{initialProjects.length !== 1 ? 's' : ''}
          </p>
        </div>
        <NewProjectForm />
      </div>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Property Type</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {initialProjects.map((p) =>
              editingId === p.id ? (
                <TableRow key={p.id}>
                  <RowEditor
                    project={p}
                    onSaved={handleSaved}
                    onCancel={() => setEditingId(null)}
                  />
                </TableRow>
              ) : (
                <TableRow key={p.id} className={p.is_active ? '' : 'opacity-60'}>
                  <TableCell className="font-medium">{p.name}</TableCell>
                  <TableCell>
                    {p.property_type ? (
                      <Badge variant="secondary">{p.property_type}</Badge>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </TableCell>
                  <TableCell>
                    <span className={p.is_active ? 'text-green-600' : 'text-muted-foreground'}>
                      {p.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </TableCell>
                  <TableCell className="text-muted-foreground text-sm">
                    {new Date(p.created_at).toLocaleDateString('en-IN', { timeZone: 'Asia/Kolkata' })}
                  </TableCell>
                  <TableCell className="text-right">
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setEditingId(p.id)}
                    >
                      Edit
                    </Button>
                  </TableCell>
                </TableRow>
              )
            )}
            {initialProjects.length === 0 && (
              <TableRow>
                <TableCell colSpan={5} className="text-center text-muted-foreground py-8">
                  No projects yet. Create one above.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
