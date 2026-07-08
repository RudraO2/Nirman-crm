"use client"
import { useCallback, useRef, useState, useTransition } from 'react'
import { toast } from 'sonner'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog'
import { TabStrip } from '@/components/tab-strip'
import type { TemplateRow } from './page'

const MAX_TEMPLATES = 3

// Story 11.2 — the single token catalog. Must stay identical to
// WhatsAppTemplate.tokenCatalog in apps/mobile (lead_model.dart), which does
// the send-time substitution.
const TOKENS = [
  'name', 'phone', 'project', 'property_type',
  'ticket_size', 'budget', 'status', 'followup_date',
  'agent_name',
] as const

const SAMPLE: Record<(typeof TOKENS)[number], string> = {
  name: 'Ramesh Kumar',
  phone: '98765 43210',
  project: 'Nirman Heights',
  property_type: '2 BHK',
  ticket_size: '50L–75L',
  budget: '₹60L–₹70L',
  status: 'warm',
  followup_date: 'Tue 14 Jul, 5:00 pm',
  agent_name: 'Sangeeta', // the sending employee — filled from their login at send time
}

// Same substitution rule as the mobile send: known tokens fill, empty → '—',
// unknown {{tokens}} are stripped.
function renderPreview(body: string): string {
  let out = body
  for (const t of TOKENS) out = out.replaceAll(`{{${t}}}`, SAMPLE[t])
  return out.replace(/\{\{[a-zA-Z_]+\}\}/g, '').trim()
}

function limitMessage(msg: string): string {
  return msg.includes('template_limit_exceeded')
    ? 'You can have at most 3 templates — delete one to add another.'
    : msg
}

// ── Create / edit dialog ─────────────────────────────────────────────────────
function EditDialog({ template, tenantId, open, onClose, onDone }: {
  template: TemplateRow | null // null = create
  tenantId: string
  open: boolean
  onClose: () => void
  onDone: () => void
}) {
  const [name, setName] = useState(template?.name ?? '')
  const [body, setBody] = useState(template?.body ?? '')
  const [nameErr, setNameErr] = useState<string | null>(null)
  const [bodyErr, setBodyErr] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [pending, startTransition] = useTransition()
  const bodyRef = useRef<HTMLTextAreaElement>(null)

  // Inserts {{token}} at the cursor (not appended) and restores focus there.
  function insertToken(token: string) {
    const el = bodyRef.current
    const chip = `{{${token}}}`
    if (!el) { setBody((b) => b + chip); return }
    const start = el.selectionStart ?? body.length
    const end = el.selectionEnd ?? start
    const next = body.slice(0, start) + chip + body.slice(end)
    setBody(next)
    requestAnimationFrame(() => {
      el.focus()
      el.selectionStart = el.selectionEnd = start + chip.length
    })
  }

  function submit() {
    setError(null)
    const nameOk = !!name.trim()
    const bodyOk = !!body.trim()
    setNameErr(nameOk ? null : 'Name is required.')
    setBodyErr(bodyOk ? null : 'Body is required.')
    if (!nameOk || !bodyOk) return
    startTransition(async () => {
      const supabase = createClient()
      const values = { name: name.trim(), body: body.trim() }
      const { data, error: dbErr } = template
        ? await supabase.from('whatsapp_templates').update(values).eq('id', template.id).select('id').single()
        : await supabase.from('whatsapp_templates').insert({ ...values, tenant_id: tenantId }).select('id').single()
      if (dbErr) { setError(limitMessage(dbErr.message)); return }
      console.info(JSON.stringify({
        event: 'whatsapp_template_write',
        action: template ? 'update' : 'create',
        template_id: data?.id ?? template?.id ?? null,
      }))
      toast.success(template ? 'Template updated' : 'Template created')
      onClose(); onDone()
    })
  }

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) onClose() }}>
      <DialogContent className="max-w-xl">
        <DialogHeader>
          <DialogTitle className="text-base font-semibold">
            {template ? 'Edit template' : 'New template'}
          </DialogTitle>
        </DialogHeader>
        <div className="space-y-4 py-2">
          <div className="space-y-2">
            <Label htmlFor="t-name">Name</Label>
            <Input id="t-name" value={name} onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Site visit invite" />
            {nameErr && <p className="text-destructive text-sm">{nameErr}</p>}
          </div>
          <div className="space-y-2">
            <Label htmlFor="t-body">Message</Label>
            <div className="flex flex-wrap gap-1.5">
              {TOKENS.map((t) => (
                <button key={t} type="button" onClick={() => insertToken(t)}
                  className="rounded-full border border-line bg-mist px-2.5 py-1 font-mono text-[11.5px] text-ink-2 transition-colors hover:border-brass hover:text-brass">
                  {`{{${t}}}`}
                </button>
              ))}
            </div>
            <Textarea id="t-body" ref={bodyRef} rows={5} value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="Hi {{name}}, following up on {{project}}…" />
            {bodyErr && <p className="text-destructive text-sm">{bodyErr}</p>}
          </div>
          {body.trim() && (
            <div className="space-y-1.5">
              <p className="text-xs font-semibold text-ink-2">Preview with a sample lead</p>
              <div className="rounded-[10px] border border-line bg-mist/60 p-3 text-sm whitespace-pre-wrap">
                {renderPreview(body)}
              </div>
            </div>
          )}
          {error && <p className="text-destructive text-sm">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={pending}>Cancel</Button>
          <Button onClick={submit} disabled={pending}>
            {pending ? 'Saving…' : template ? 'Save changes' : 'Create'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

// ── Main ─────────────────────────────────────────────────────────────────────
export function TemplatesClient({ initial, tenantId }: { initial: TemplateRow[]; tenantId: string }) {
  const [templates, setTemplates] = useState<TemplateRow[]>(initial)
  const [editing, setEditing] = useState<TemplateRow | null>(null)
  const [creating, setCreating] = useState(false)
  const [deleting, setDeleting] = useState<TemplateRow | null>(null)
  const [pending, startTransition] = useTransition()

  const reload = useCallback(async () => {
    const supabase = createClient()
    const { data, error } = await supabase
      .from('whatsapp_templates')
      .select('id, name, body, updated_at')
      .order('created_at', { ascending: true })
    if (error) { toast.error(`Failed to load: ${error.message}`); return }
    setTemplates((data ?? []) as TemplateRow[])
  }, [])

  function confirmDelete() {
    const target = deleting
    if (!target) return
    startTransition(async () => {
      const supabase = createClient()
      const { error } = await supabase.from('whatsapp_templates').delete().eq('id', target.id)
      if (error) { toast.error(error.message); return }
      console.info(JSON.stringify({
        event: 'whatsapp_template_write', action: 'delete', template_id: target.id,
      }))
      toast.success('Template deleted')
      setDeleting(null); reload()
    })
  }

  const atLimit = templates.length >= MAX_TEMPLATES

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="space-y-2">
          <p className="eyebrow">Team</p>
          <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
            WhatsApp Templates
          </h1>
          <p className="text-[13.5px] text-ink-2">
            Up to 3 message templates your team sends from the mobile app · {'{{variables}}'} fill from the lead
          </p>
        </div>
        <div className="flex items-center gap-3">
          {atLimit && <p className="text-xs text-ink-3">Limit of {MAX_TEMPLATES} reached</p>}
          <Button size="sm" disabled={atLimit} onClick={() => setCreating(true)}>New template</Button>
        </div>
      </div>

      <TabStrip />

      {templates.length === 0 && (
        <div className="rounded-[14px] border border-dashed border-line-2 p-10 text-center text-ink-2">
          No templates yet. Create up to {MAX_TEMPLATES} — your team picks one when sending a WhatsApp from a lead.
        </div>
      )}

      <div className="space-y-3">
        {templates.map((t) => (
          <div key={t.id} className="rounded-[14px] border border-line bg-paper p-4 shadow-[var(--shadow)]">
            <div className="flex items-center gap-2">
              <p className="text-sm font-semibold">{t.name}</p>
              <div className="ml-auto flex gap-1.5">
                <Button variant="ghost" size="sm" onClick={() => setEditing(t)}>Edit</Button>
                <Button variant="ghost" size="sm" className="text-destructive hover:text-destructive"
                  onClick={() => setDeleting(t)}>Delete</Button>
              </div>
            </div>
            <p className="mt-2 whitespace-pre-wrap text-sm text-ink-2">{t.body}</p>
          </div>
        ))}
      </div>

      {(creating || editing) && (
        <EditDialog
          key={editing?.id ?? 'new'}
          template={editing}
          tenantId={tenantId}
          open
          onClose={() => { setCreating(false); setEditing(null) }}
          onDone={reload}
        />
      )}

      <Dialog open={!!deleting} onOpenChange={(v) => { if (!v) setDeleting(null) }}>
        <DialogContent className="max-w-sm">
          <DialogHeader>
            <DialogTitle className="text-base font-semibold">Delete template?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-ink-2">
            “{deleting?.name}” will disappear from the mobile template picker immediately.
          </p>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setDeleting(null)} disabled={pending}>Cancel</Button>
            <Button variant="destructive" onClick={confirmDelete} disabled={pending}>
              {pending ? 'Deleting…' : 'Delete'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
