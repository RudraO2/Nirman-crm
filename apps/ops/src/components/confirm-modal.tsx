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
import { verifyStepUp } from '@/lib/step-up'

/**
 * Typed-confirmation modal (design §10 safety rail). The operator must retype
 * the exact tenant name before the action can fire — the confirm button stays
 * disabled until it matches. Used for Suspend / Reactivate.
 *
 * Story 9.7: when `requireMfa` is set (destructive actions), a fresh 6-digit TOTP
 * code is also required and verified (step-up) before `onConfirm` fires.
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
  requireMfa = false,
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
  requireMfa?: boolean
  onConfirm: (note: string) => void
}) {
  const [typed, setTyped] = useState('')
  const [note, setNote] = useState('')
  const [code, setCode] = useState('')
  const [mfaError, setMfaError] = useState<string | null>(null)
  const [verifying, setVerifying] = useState(false)

  const matches = typed.trim() === tenantName.trim()
  const codeReady = !requireMfa || code.length === 6

  function reset() {
    setTyped('')
    setNote('')
    setCode('')
    setMfaError(null)
    setVerifying(false)
  }

  async function handleConfirm() {
    if (requireMfa) {
      setVerifying(true)
      setMfaError(null)
      const r = await verifyStepUp(code)
      setVerifying(false)
      if (!r.ok) {
        setMfaError(r.error ?? 'Verification failed.')
        return
      }
    }
    onConfirm(note)
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
              // Typing, not pasting, is the friction that makes this rail work
              // (audit medium: copy-pasting the name shown above defeated it).
              onPaste={(e) => e.preventDefault()}
              onDrop={(e) => e.preventDefault()}
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
          {requireMfa && (
            <div className="space-y-1.5">
              <Label htmlFor="confirm-mfa" className="text-xs text-muted-foreground">
                Authenticator code <span className="opacity-60">(required)</span>
              </Label>
              <Input
                id="confirm-mfa"
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={6}
                placeholder="••••••"
                value={code}
                onChange={(e) => {
                  setCode(e.target.value.replace(/\D/g, '').slice(0, 6))
                  setMfaError(null)
                }}
                className="text-center font-mono tracking-[0.4em]"
                aria-invalid={!!mfaError}
              />
              {mfaError && <p className="text-xs text-destructive">{mfaError}</p>}
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={busy || verifying}>
            Cancel
          </Button>
          <Button
            variant={destructive ? 'destructive-solid' : 'default'}
            disabled={!matches || !codeReady || busy || verifying}
            onClick={handleConfirm}
          >
            {verifying ? 'Verifying…' : busy ? 'Working…' : confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
