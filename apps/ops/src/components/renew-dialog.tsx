'use client'

import { useState, useMemo, useEffect } from 'react'
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
import { inr } from '@/lib/format'
import { verifyStepUp } from '@/lib/step-up'
import { PAYMENT_METHODS, type Plan, type PaymentMethod } from '@/lib/types'

const selectCls =
  'h-8 w-full rounded-[8px] border border-input bg-background px-2.5 text-sm text-foreground outline-none focus:border-ring focus:ring-3 focus:ring-ring/40'

/**
 * Record-payment / renew dialog. Collects plan + amount + method + note, then
 * enforces the typed-confirmation safety rail (design §10): the operator must
 * retype BOTH the exact tenant name AND the exact amount (paste disabled), plus
 * a fresh authenticator code (9.7 step-up — audit parity with Suspend/Provision)
 * before Record fires. Calls ops_renew_tenant (delegates to the 9.1 seam) via
 * the parent.
 *
 * `initialInterval` lets a "+1 mo" / "+3 mo" quick chip preselect the plan whose
 * interval_months matches (renew_tenant extends by the plan's interval).
 */
export function RenewDialog({
  open,
  onOpenChange,
  tenantName,
  plans,
  initialInterval,
  busy = false,
  onConfirm,
}: {
  open: boolean
  onOpenChange: (o: boolean) => void
  tenantName: string
  plans: Plan[]
  initialInterval: number | null
  busy?: boolean
  onConfirm: (args: { planId: string; amountInr: number; method: PaymentMethod; note: string }) => void
}) {
  const defaultPlan = useMemo(() => {
    if (initialInterval != null) {
      const m = plans.find((p) => p.interval_months === initialInterval)
      if (m) return m
    }
    return plans[0]
  }, [plans, initialInterval])

  const [planId, setPlanId] = useState(defaultPlan?.id ?? '')
  const [amount, setAmount] = useState<string>(defaultPlan ? String(defaultPlan.price_inr) : '')
  const [method, setMethod] = useState<PaymentMethod>('upi')
  const [note, setNote] = useState('')
  const [typedName, setTypedName] = useState('')
  const [typedAmount, setTypedAmount] = useState('')
  // Audit medium: Record Payment moves money/extends access but demanded no fresh
  // TOTP, unlike Suspend/Provision. Same step-up rail as ConfirmModal.
  const [code, setCode] = useState('')
  const [mfaError, setMfaError] = useState<string | null>(null)
  const [verifying, setVerifying] = useState(false)

  // Re-seed when the dialog (re)opens with a different quick-chip interval.
  useEffect(() => {
    if (open) {
      setPlanId(defaultPlan?.id ?? '')
      setAmount(defaultPlan ? String(defaultPlan.price_inr) : '')
      setMethod('upi')
      setNote('')
      setTypedName('')
      setTypedAmount('')
      setCode('')
      setMfaError(null)
      setVerifying(false)
    }
  }, [open, defaultPlan])

  const selectedPlan = plans.find((p) => p.id === planId)
  const amountNum = Number(amount)
  const amountValid = Number.isInteger(amountNum) && amountNum >= 0 && amount.trim() !== ''
  const nameMatches = typedName.trim() === tenantName.trim()
  const amountMatches = amountValid && typedAmount.trim() === String(amountNum)
  const canSubmit =
    !!planId && amountValid && nameMatches && amountMatches && code.length === 6 && !busy && !verifying

  async function handleConfirm() {
    setVerifying(true)
    setMfaError(null)
    const r = await verifyStepUp(code)
    setVerifying(false)
    if (!r.ok) {
      setMfaError(r.error ?? 'Verification failed.')
      return
    }
    onConfirm({ planId, amountInr: amountNum, method, note })
  }

  const noPlans = plans.length === 0

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Record payment · {tenantName}</DialogTitle>
          <DialogDescription>
            Extends the prepaid window by the plan interval and reactivates the tenant.
            Writes a ledger row and an audit entry.
          </DialogDescription>
        </DialogHeader>

        {noPlans ? (
          <p className="rounded-[8px] border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
            No active plans available. Seed a plan before recording a payment.
          </p>
        ) : (
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label htmlFor="plan" className="text-xs text-muted-foreground">Plan</Label>
                <select
                  id="plan"
                  className={selectCls}
                  value={planId}
                  onChange={(e) => {
                    setPlanId(e.target.value)
                    const p = plans.find((pl) => pl.id === e.target.value)
                    if (p) setAmount(String(p.price_inr))
                  }}
                >
                  {plans.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name} · {p.interval_months}mo
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="method" className="text-xs text-muted-foreground">Method</Label>
                <select
                  id="method"
                  className={selectCls}
                  value={method}
                  onChange={(e) => setMethod(e.target.value as PaymentMethod)}
                >
                  {PAYMENT_METHODS.map((m) => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
              </div>
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="amount" className="text-xs text-muted-foreground">
                Amount (₹){selectedPlan ? ` · plan price ${inr(selectedPlan.price_inr)}` : ''}
              </Label>
              <Input
                id="amount"
                inputMode="numeric"
                value={amount}
                onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, ''))}
                aria-invalid={amount.length > 0 && !amountValid}
              />
            </div>

            <div className="space-y-1.5">
              <Label htmlFor="note" className="text-xs text-muted-foreground">
                Note <span className="opacity-60">(optional)</span>
              </Label>
              <Textarea id="note" value={note} onChange={(e) => setNote(e.target.value)} rows={2} />
            </div>

            {/* Safety rail: retype name + amount */}
            <div className="rounded-[9px] border border-border bg-background/60 p-3 space-y-2.5">
              <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
                Confirm to record
              </p>
              <div className="space-y-1.5">
                <Label htmlFor="c-name" className="text-xs text-muted-foreground">
                  Retype tenant name <span className="font-mono text-foreground">{tenantName}</span>
                </Label>
                <Input
                  id="c-name"
                  value={typedName}
                  autoComplete="off"
                  onChange={(e) => setTypedName(e.target.value)}
                  onPaste={(e) => e.preventDefault()}
                  onDrop={(e) => e.preventDefault()}
                  aria-invalid={typedName.length > 0 && !nameMatches}
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="c-amount" className="text-xs text-muted-foreground">
                  Retype amount <span className="font-mono text-foreground">{amountValid ? amountNum : '—'}</span>
                </Label>
                <Input
                  id="c-amount"
                  inputMode="numeric"
                  value={typedAmount}
                  autoComplete="off"
                  onChange={(e) => setTypedAmount(e.target.value.replace(/[^0-9]/g, ''))}
                  onPaste={(e) => e.preventDefault()}
                  onDrop={(e) => e.preventDefault()}
                  aria-invalid={typedAmount.length > 0 && !amountMatches}
                />
              </div>
              <div className="space-y-1.5">
                <Label htmlFor="c-mfa" className="text-xs text-muted-foreground">
                  Authenticator code <span className="opacity-60">(required)</span>
                </Label>
                <Input
                  id="c-mfa"
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
            </div>
          </div>
        )}

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={busy || verifying}>
            Cancel
          </Button>
          <Button disabled={noPlans || !canSubmit} onClick={handleConfirm}>
            {verifying ? 'Verifying…' : busy ? 'Recording…' : `Record ${amountValid ? inr(amountNum) : 'payment'}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
