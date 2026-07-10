'use client'

import { useState } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'

/**
 * Typed-confirmation modal (design §10 safety rail). The operator must retype
 * the exact tenant name before the action can fire — the confirm button stays
 * disabled until it matches. Used for Suspend / Reactivate.
 */
export function ConfirmModal({
  open,
  onOpenChange,
  title,
  description,
  tenantName,
  noteLabel,
  confirmLabel,
  destructive = false,
  busy = false,
  onConfirm,
}: {
  open: boolean
  onOpenChange: (o: boolean) => void
  title: string
  description: string
  tenantName: string
  noteLabel: string
  confirmLabel: string
  destructive?: boolean
  busy?: boolean
  onConfirm: (note: string) => void
}) {
  const [typed, setTyped] = useState('')
  const [note, setNote] = useState('')

  const matches = typed.trim() === tenantName.trim()

  function reset() {
    setTyped('')
    setNote('')
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(o) => {
        onOpenChange(o)
        if (!o) reset()
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>{description}</DialogDescription>
        </DialogHeader>

        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="confirm-name" className="text-xs text-muted-foreground">
              Retype the tenant name{' '}
              <span className="font-mono text-foreground">{tenantName}</span> to confirm
            </Label>
            <Input
              id="confirm-name"
              value={typed}
              onChange={(e) => setTyped(e.target.value)}
              autoComplete="off"
              placeholder={tenantName}
              aria-invalid={typed.length > 0 && !matches}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="confirm-note" className="text-xs text-muted-foreground">
              {noteLabel} <span className="opacity-60">(optional)</span>
            </Label>
            <Textarea
              id="confirm-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={busy}>
            Cancel
          </Button>
          <Button
            variant={destructive ? 'destructive-solid' : 'default'}
            disabled={!matches || busy}
            onClick={() => onConfirm(note)}
          >
            {busy ? 'Working…' : confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
