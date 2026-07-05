"use client"
import { useCallback, useEffect, useState, useTransition } from 'react'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from '@/components/ui/dialog'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { TabStrip } from '@/components/tab-strip'
import type { UpdProjectRow } from './page'

type UpdType = 'construction' | 'pricing' | 'inventory' | 'announcement'

interface DevUpdate {
  id: string
  project_id: string | null
  update_type: UpdType
  body: string
  shareable_to_partners: boolean
  posted_by: string | null
  posted_by_name: string | null
  created_at: string
}

const ALL = '__all__'
const TENANT_WIDE = '__tenant__'
const TYPES: UpdType[] = ['construction', 'pricing', 'inventory', 'announcement']
const TYPE_LABEL: Record<UpdType, string> = {
  construction: 'Construction', pricing: 'Pricing', inventory: 'Inventory', announcement: 'Announcement',
}

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleString('en-IN', {
    timeZone: 'Asia/Kolkata', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
  })
}

// ── Post dialog ──────────────────────────────────────────────────────────────
function PostDialog({ projects, onDone }: { projects: UpdProjectRow[]; onDone: () => void }) {
  const [open, setOpen] = useState(false)
  const [type, setType] = useState<UpdType>('announcement')
  const [body, setBody] = useState('')
  const [projectId, setProjectId] = useState<string>(TENANT_WIDE)
  const [shareable, setShareable] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()

  function reset() {
    setType('announcement'); setBody(''); setProjectId(TENANT_WIDE); setShareable(false); setError(null)
  }

  function submit() {
    setError(null)
    if (!body.trim()) { setError('Message is required.'); return }
    if (shareable && projectId === TENANT_WIDE) {
      setError('Partner-shareable updates must target a project.'); return
    }
    startTransition(async () => {
      const supabase = createClient()
      const { error: rpcErr } = await supabase.rpc('post_developer_update', {
        p_update_type: type,
        p_body: body.trim(),
        p_project_id: projectId === TENANT_WIDE ? null : projectId,
        p_shareable_to_partners: shareable,
      })
      if (rpcErr) { setError(rpcErr.message); return }
      toast.success('Update posted')
      setOpen(false); reset(); onDone()
    })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { setOpen(v); if (!v) reset() }}>
      <DialogTrigger asChild>
        <Button size="sm">Post update</Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">Post developer update</DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-2">
              <Label htmlFor="u-type">Type</Label>
              <Select value={type} onValueChange={(v) => setType(v as UpdType)}>
                <SelectTrigger id="u-type" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {TYPES.map((t) => <SelectItem key={t} value={t}>{TYPE_LABEL[t]}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label htmlFor="u-project">Project</Label>
              <Select value={projectId} onValueChange={setProjectId}>
                <SelectTrigger id="u-project" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value={TENANT_WIDE}>Tenant-wide</SelectItem>
                  {projects.map((p) => <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-2">
            <Label htmlFor="u-body">Message</Label>
            <Textarea id="u-body" rows={4} value={body} onChange={(e) => setBody(e.target.value)}
              placeholder="What's the update?" />
          </div>
          <label className="flex items-center gap-3 cursor-pointer">
            <input type="checkbox" checked={shareable} onChange={(e) => setShareable(e.target.checked)}
              className="size-4 rounded border-input cursor-pointer" />
            <span className="text-sm">Share with partner agencies (project-shared only)</span>
          </label>
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)} disabled={pending}>Cancel</Button>
          <Button onClick={submit} disabled={pending || !body.trim()}>{pending ? 'Posting…' : 'Post'}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Main ─────────────────────────────────────────────────────────────────────
export function DeveloperUpdatesClient({ projects }: { projects: UpdProjectRow[] }) {
  const [projectFilter, setProjectFilter] = useState<string>(ALL)
  const [updates, setUpdates] = useState<DevUpdate[]>([])
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)

  const projectName = useCallback(
    (id: string | null) => id ? (projects.find((p) => p.id === id)?.name ?? '—') : 'Tenant-wide',
    [projects],
  )

  const load = useCallback(async () => {
    setLoading(true); setLoadError(null)
    const supabase = createClient()
    const { data, error } = await supabase.rpc('get_developer_updates', {
      p_project_id: projectFilter === ALL ? null : projectFilter,
      p_limit: 50,
      p_offset: 0,
    })
    if (error) { setLoadError(error.message); setLoading(false); return }
    setUpdates((data ?? []) as DevUpdate[])
    setLoading(false)
  }, [projectFilter])

  useEffect(() => { load() }, [load])

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <p className="eyebrow">Builder Ops</p>
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            Developer Updates
          </h1>
          <p className="text-[13.5px] text-ink-2">Broadcasts to the sales team &amp; partner agencies</p>
        </div>
        <div className="flex items-end gap-2">
          <div className="space-y-1.5">
            <Label htmlFor="f-project" className="text-xs">Project</Label>
            <Select value={projectFilter} onValueChange={setProjectFilter}>
              <SelectTrigger id="f-project" className="w-48"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value={ALL}>All</SelectItem>
                {projects.map((p) => <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <PostDialog projects={projects} onDone={load} />
        </div>
      </div>

      <TabStrip />

      {loadError && <p className="text-danger text-sm">Failed to load: {loadError}</p>}

      {!loading && updates.length === 0 && !loadError && (
        <div className="rounded-[14px] border border-dashed border-line-2 p-10 text-center text-ink-2">
          No updates yet. Post the first one.
        </div>
      )}

      <div className="space-y-3">
        {updates.map((u) => (
          <div key={u.id} className="rounded-[14px] border border-line bg-paper p-4 shadow-[var(--shadow)]">
            <div className="flex flex-wrap items-center gap-2">
              <span className="rounded-full bg-brass-soft px-3 py-1 text-xs font-semibold" style={{ color: '#6E5423' }}>
                {TYPE_LABEL[u.update_type]}
              </span>
              <span className="text-sm text-ink-2">{projectName(u.project_id)}</span>
              {u.shareable_to_partners && (
                <span className="rounded-full bg-cold-bg px-2.5 py-0.5 text-xs font-semibold text-cold">
                  Partners
                </span>
              )}
              <span className="ml-auto text-xs text-ink-3 tabular-nums">{fmtDate(u.created_at)}</span>
            </div>
            <p className="mt-3 whitespace-pre-wrap text-sm">{u.body}</p>
            {u.posted_by_name && (
              <p className="mt-2 text-xs text-ink-3">— {u.posted_by_name}</p>
            )}
          </div>
        ))}
      </div>
    </div>
  )
}
