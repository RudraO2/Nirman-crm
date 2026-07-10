'use client'

import { useState, useEffect, useCallback, useMemo } from 'react'
import { Sheet, SheetContent, SheetTitle, SheetDescription } from '@/components/ui/sheet'
import { Button } from '@/components/ui/button'
import { StatusPill } from '@/components/status-pill'
import { ConfirmModal } from '@/components/confirm-modal'
import { RenewDialog } from '@/components/renew-dialog'
import { createClient } from '@/lib/supabase/client'
import { relativeDays, fmtDate, fmtDateTime, inr, rpcErrorMessage } from '@/lib/format'
import type { OpsTenant, Plan, TenantPayment, PaymentMethod } from '@/lib/types'
import { CreditCard, Ban, RotateCcw, TriangleAlert } from 'lucide-react'
import { toast } from 'sonner'

export function TenantDetailSheet({
  tenant,
  plans,
  open,
  onOpenChange,
  onMutated,
}: {
  tenant: OpsTenant | null
  plans: Plan[]
  open: boolean
  onOpenChange: (o: boolean) => void
  onMutated: () => Promise<void> | void
}) {
  // Hold the last non-null tenant so content stays put during the close animation.
  const [active, setActive] = useState<OpsTenant | null>(tenant)
  useEffect(() => {
    if (tenant) setActive(tenant)
  }, [tenant])

  const [ledger, setLedger] = useState<TenantPayment[] | null>(null)
  const [ledgerErr, setLedgerErr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [renewOpen, setRenewOpen] = useState(false)
  const [renewInterval, setRenewInterval] = useState<number | null>(null)
  const [suspendOpen, setSuspendOpen] = useState(false)
  const [reactivateOpen, setReactivateOpen] = useState(false)

  const tenantId = active?.tenant_id ?? null
  const planIntervals = useMemo(() => new Set(plans.map((p) => p.interval_months)), [plans])

  const loadLedger = useCallback(async (id: string) => {
    setLedger(null)
    setLedgerErr(null)
    const supabase = createClient()
    const { data, error } = await supabase.rpc('ops_list_tenant_payments', { p_tenant_id: id })
    if (error) setLedgerErr(rpcErrorMessage(error))
    else setLedger((data ?? []) as TenantPayment[])
  }, [])

  useEffect(() => {
    if (open && tenantId) loadLedger(tenantId)
  }, [open, tenantId, loadLedger])

  async function afterMutation() {
    await onMutated()
    if (tenantId) await loadLedger(tenantId)
  }

  async function doRenew(args: {
    planId: string
    amountInr: number
    method: PaymentMethod
    note: string
  }) {
    if (!tenantId) return
    setBusy(true)
    const supabase = createClient()
    const { error } = await supabase.rpc('ops_renew_tenant', {
      p_tenant_id: tenantId,
      p_plan_id: args.planId,
      p_amount_inr: args.amountInr,
      p_method: args.method,
      p_note: args.note || null,
    })
    setBusy(false)
    if (error) {
      toast.error(rpcErrorMessage(error))
      return
    }
    toast.success(`Payment of ${inr(args.amountInr)} recorded — tenant active.`)
    setRenewOpen(false)
    await afterMutation()
  }

  async function doSuspend(reason: string) {
    if (!tenantId) return
    setBusy(true)
    const supabase = createClient()
    const { error } = await supabase.rpc('ops_suspend_tenant', {
      p_tenant_id: tenantId,
      p_reason: reason || null,
    })
    setBusy(false)
    if (error) {
      toast.error(rpcErrorMessage(error))
      return
    }
    toast.success('Tenant suspended.')
    setSuspendOpen(false)
    await afterMutation()
  }

  async function doReactivate(note: string) {
    if (!tenantId) return
    setBusy(true)
    const supabase = createClient()
    const { error } = await supabase.rpc('ops_reactivate_tenant', {
      p_tenant_id: tenantId,
      p_note: note || null,
    })
    setBusy(false)
    if (error) {
      toast.error(rpcErrorMessage(error))
      return
    }
    toast.success('Tenant reactivated.')
    setReactivateOpen(false)
    await afterMutation()
  }

  const t = active
  const isSuspended = t?.status === 'suspended'
  const isCancelled = t?.status === 'cancelled'
  const isLapsed = t?.status === 'active' && t.days_remaining != null && t.days_remaining < 0

  function openRenew(interval: number | null) {
    setRenewInterval(interval)
    setRenewOpen(true)
  }

  return (
    <>
      <Sheet open={open} onOpenChange={onOpenChange}>
        <SheetContent>
          {t && (
            <div className="flex h-full flex-col">
              {/* Header */}
              <div className="border-b border-border px-5 py-4 pr-12">
                <SheetTitle>{t.name}</SheetTitle>
                <div className="mt-1.5 flex items-center gap-2">
                  <StatusPill status={t.status} days={t.days_remaining} />
                  <SheetDescription className="font-mono">{t.tenant_id.slice(0, 8)}</SheetDescription>
                </div>
              </div>

              <div className="flex-1 overflow-y-auto px-5 py-4">
                {/* Lapsed steer */}
                {(isSuspended || isLapsed) && (
                  <div className="mb-4 flex items-start gap-2 rounded-[9px] border border-st-grace/30 bg-st-grace-bg px-3 py-2.5">
                    <TriangleAlert className="mt-0.5 size-3.5 flex-shrink-0 text-st-grace" />
                    <p className="text-xs text-foreground/80">
                      {isSuspended
                        ? 'Suspended. Record a payment to restore access and extend the window — a bare reactivate on a lapsed tenant is undone by the hourly sweep.'
                        : 'Past paid-until (grace). Record a payment before the next hourly sweep suspends this tenant.'}
                    </p>
                  </div>
                )}

                {/* Billing block */}
                <section className="rounded-[11px] border border-border bg-background/50 p-4">
                  <p className="eyebrow mb-3">Billing</p>
                  <dl className="grid grid-cols-2 gap-y-2.5 text-sm">
                    <dt className="text-muted-foreground">Plan</dt>
                    <dd className="text-right font-medium">{t.plan_name ?? '—'}</dd>
                    <dt className="text-muted-foreground">Paid until</dt>
                    <dd className="text-right font-mono tabular-nums">{fmtDate(t.paid_until)}</dd>
                    <dt className="text-muted-foreground">Window</dt>
                    <dd className="text-right font-mono tabular-nums">{relativeDays(t.days_remaining)}</dd>
                  </dl>

                  <div className="mt-4 flex flex-wrap gap-2">
                    <Button size="sm" onClick={() => openRenew(null)}>
                      <CreditCard /> Record payment
                    </Button>
                    {/* Only offer a quick chip when a plan of that interval
                        actually exists — otherwise the chip would silently
                        record a different-length window than it promises. */}
                    {planIntervals.has(1) && (
                      <Button size="sm" variant="outline" onClick={() => openRenew(1)}>+1 mo</Button>
                    )}
                    {planIntervals.has(3) && (
                      <Button size="sm" variant="outline" onClick={() => openRenew(3)}>+3 mo</Button>
                    )}
                  </div>
                </section>

                {/* Lifecycle actions */}
                <section className="mt-4 flex flex-wrap gap-2">
                  {isSuspended || isCancelled ? (
                    <Button size="sm" variant="outline" onClick={() => setReactivateOpen(true)}>
                      <RotateCcw /> Reactivate
                    </Button>
                  ) : (
                    <Button size="sm" variant="destructive" onClick={() => setSuspendOpen(true)}>
                      <Ban /> Suspend
                    </Button>
                  )}
                </section>

                {/* Payment ledger */}
                <section className="mt-6">
                  <p className="eyebrow mb-2">Payment ledger</p>
                  {ledgerErr ? (
                    <p className="rounded-[8px] border border-destructive/40 bg-destructive/10 px-3 py-2 text-xs text-destructive">
                      {ledgerErr}
                    </p>
                  ) : ledger === null ? (
                    <p className="py-3 text-xs text-muted-foreground">Loading…</p>
                  ) : ledger.length === 0 ? (
                    <p className="rounded-[8px] border border-dashed border-border px-3 py-4 text-center text-xs text-muted-foreground">
                      No payments recorded yet.
                    </p>
                  ) : (
                    <ul className="divide-y divide-border overflow-hidden rounded-[9px] border border-border">
                      {ledger.map((p) => (
                        <li key={p.id} className="px-3 py-2.5">
                          <div className="flex items-center justify-between">
                            <span className="font-mono text-sm font-medium tabular-nums">{inr(p.amount_inr)}</span>
                            <span className="rounded bg-muted px-1.5 py-0.5 font-mono text-[10px] uppercase text-muted-foreground">
                              {p.method}
                            </span>
                          </div>
                          <div className="mt-1 flex items-center justify-between text-[11px] text-muted-foreground">
                            <span className="font-mono">{fmtDateTime(p.paid_at)}</span>
                            <span className="font-mono tabular-nums">
                              {fmtDate(p.covers_from)} → {fmtDate(p.covers_until)}
                            </span>
                          </div>
                          {p.note && <p className="mt-1 text-[11px] text-foreground/70">{p.note}</p>}
                        </li>
                      ))}
                    </ul>
                  )}
                </section>
              </div>
            </div>
          )}
        </SheetContent>
      </Sheet>

      {/* Dialogs live outside the Sheet so radix focus management doesn't collide. */}
      {t && (
        <>
          <RenewDialog
            open={renewOpen}
            onOpenChange={setRenewOpen}
            tenantName={t.name}
            plans={plans}
            initialInterval={renewInterval}
            busy={busy}
            onConfirm={doRenew}
          />
          <ConfirmModal
            open={suspendOpen}
            onOpenChange={setSuspendOpen}
            title={`Suspend ${t.name}?`}
            description="Access is cut off immediately (the 0056 status gate). This is audit-logged."
            tenantName={t.name}
            noteLabel="Reason"
            confirmLabel="Suspend tenant"
            destructive
            busy={busy}
            onConfirm={doSuspend}
          />
          <ConfirmModal
            open={reactivateOpen}
            onOpenChange={setReactivateOpen}
            title={`Reactivate ${t.name}?`}
            description="Restores access without changing paid-until. For a lapsed tenant, record a payment instead."
            tenantName={t.name}
            noteLabel="Note"
            confirmLabel="Reactivate tenant"
            busy={busy}
            onConfirm={doReactivate}
          />
        </>
      )}
    </>
  )
}
