'use client'

import { useState, useMemo } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { inr, rpcErrorMessage } from '@/lib/format'
import { verifyStepUp } from '@/lib/step-up'
import { PAYMENT_METHODS, type Plan, type PaymentMethod } from '@/lib/types'
import { UserPlus, Check, Copy, TriangleAlert, RefreshCw } from 'lucide-react'
import { toast } from 'sonner'

type Start = 'trial' | 'paid'
const selectCls =
  'h-8 w-full rounded-[8px] border border-input bg-background px-2.5 text-sm text-foreground outline-none focus:border-ring focus:ring-3 focus:ring-ring/40'

function genPassword(builder: string): string {
  const stem = (builder.replace(/[^A-Za-z]/g, '').slice(0, 5) || 'Acme')
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
  let s = ''
  for (let i = 0; i < 7; i++) s += chars[Math.floor(Math.random() * chars.length)]
  return `${stem.charAt(0).toUpperCase()}${stem.slice(1).toLowerCase()}-${s}`
}

interface Result {
  tenant_id: string
  admin_user_id: string
  admin_username: string
  status: string
}

export function ProvisionFlow({ plans }: { plans: Plan[] }) {
  const router = useRouter()
  const [step, setStep] = useState(1)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<Result | null>(null)

  // form
  const [name, setName] = useState('')
  const [timezone, setTimezone] = useState('Asia/Kolkata')
  const [adminName, setAdminName] = useState('')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState(() => genPassword(''))
  const [planId, setPlanId] = useState(plans[0]?.id ?? '')
  const [start, setStart] = useState<Start>('trial')
  const [amount, setAmount] = useState(plans[0] ? String(plans[0].price_inr) : '')
  const [method, setMethod] = useState<PaymentMethod>('upi')
  // Story 9.7 step-up: a fresh authenticator code is required to actually provision.
  const [mfaCode, setMfaCode] = useState('')

  const selectedPlan = plans.find((p) => p.id === planId)
  const amountNum = Number(amount)
  const amountValid = Number.isInteger(amountNum) && amountNum >= 0 && amount.trim() !== ''

  const step1ok = name.trim().length > 0
  const step2ok = username.trim().length > 0 && password.length >= 8
  const step3ok = start === 'trial' || (!!planId && amountValid)
  const canProvision = step1ok && step2ok && step3ok && mfaCode.length === 6 && !busy

  const displayUser = useMemo(() => {
    const u = username.trim().toLowerCase()
    if (!u) return '—'
    return u.includes('@') ? u : `${u}@employees.nirman.local`
  }, [username])

  function regen() {
    setPassword(genPassword(name))
  }

  function next() {
    if (step < 3) { setStep(step + 1); window.scrollTo({ top: 0, behavior: 'smooth' }) }
    else provision()
  }

  async function provision() {
    setBusy(true)
    // Step-up: re-confirm a fresh authenticator code before creating the account.
    const stepUp = await verifyStepUp(mfaCode)
    if (!stepUp.ok) {
      setBusy(false)
      toast.error(stepUp.error ?? 'Verification failed.')
      return
    }
    const supabase = createClient()
    const { data, error } = await supabase.rpc('provision_tenant', {
      p_builder_name: name.trim(),
      p_admin_username: username.trim(),
      p_admin_password: password,
      p_admin_name: adminName.trim() || null,
      p_plan_id: start === 'paid' ? planId : (planId || null),
      p_start: start,
      p_amount_inr: start === 'paid' ? amountNum : null,
      p_method: start === 'paid' ? method : null,
      p_timezone: timezone,
    })
    setBusy(false)
    if (error) {
      toast.error(rpcErrorMessage(error))
      return
    }
    setResult(data as Result)
    toast.success(`${name.trim()} provisioned.`)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  function copy(text: string) {
    navigator.clipboard?.writeText(text)
    toast.success('Copied')
  }

  // ── Success handoff ────────────────────────────────────────────────────────
  if (result) {
    return (
      <div className="mx-auto max-w-[1000px] px-8 py-8">
        <div className="grid size-11 place-items-center rounded-[12px] bg-st-active-bg text-st-active">
          <Check className="size-6" />
        </div>
        <h1 className="mt-3.5 text-[20px] font-semibold">{name.trim()} is live</h1>
        <p className="mt-1.5 text-sm text-muted-foreground">
          Hand these credentials to the builder. The password won&apos;t be shown again — copy it now.
        </p>

        <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-[1fr_320px]">
          <div className="rounded-[12px] border border-border bg-card p-5">
            <p className="eyebrow mb-3">Credentials to hand over</p>
            <div className="rounded-[10px] border border-input bg-background px-4">
              <CredRow label="Sign-in URL" value="your builder admin URL" onCopy={copy} />
              <CredRow label="Username" value={username.trim()} mono onCopy={copy} />
              <CredRow label="Temp password" value={password} mono onCopy={copy} last />
            </div>
            <div className="mt-4 flex items-start gap-2.5 rounded-[10px] border border-st-grace/30 bg-st-grace-bg px-3.5 py-3 text-xs text-foreground/80">
              <TriangleAlert className="mt-0.5 size-4 flex-shrink-0 text-st-grace" />
              They&apos;re forced to set a new password on first login. If you lose this, reset it from their
              row — it can&apos;t be shown again.
            </div>
            <div className="mt-5 flex gap-2.5">
              <Button onClick={() => router.push('/')}>Back to tenants</Button>
              <Button variant="outline" onClick={() => { setResult(null); setStep(1); setName(''); setUsername(''); setAdminName(''); setPassword(genPassword('')) }}>
                Provision another
              </Button>
            </div>
          </div>
          <aside className="h-fit rounded-[12px] border border-border bg-popover p-4">
            <p className="eyebrow mb-3">New tenant</p>
            <Kv k="Status" v={<span className="font-medium capitalize">{result.status}</span>} />
            <Kv k="Plan" v={selectedPlan?.name ?? '—'} />
            <Kv k="Start" v={start === 'paid' ? 'Paid now' : 'Trial (14 days)'} last />
            <p className="mt-3.5 text-[11px] leading-relaxed text-muted-foreground">
              It now appears in your Tenants list. When they pay, open the row → Record payment → status flips to active.
            </p>
          </aside>
        </div>
      </div>
    )
  }

  // ── Wizard ─────────────────────────────────────────────────────────────────
  const stepMeta = [
    { n: 1, t: 'Builder', s: 'company details' },
    { n: 2, t: 'First admin', s: 'login account' },
    { n: 3, t: 'Plan & window', s: 'starting access' },
  ]

  return (
    <div className="mx-auto max-w-[1040px] px-8 py-8">
      <div className="flex items-center gap-2.5">
        <UserPlus className="size-5 text-primary" />
        <h1 className="text-[20px] font-semibold">Provision a builder</h1>
      </div>
      <p className="mt-1.5 text-sm text-muted-foreground">
        Create the builder&apos;s workspace, its first admin login, and the starting plan. Ends with credentials to hand over.
      </p>

      {/* Stepper */}
      <div className="mt-6 flex gap-2">
        {stepMeta.map((m) => {
          const state = step === m.n ? 'on' : step > m.n ? 'done' : 'idle'
          return (
            <div
              key={m.n}
              className={
                'flex flex-1 items-center gap-2.5 rounded-[10px] border bg-card px-3 py-2.5 ' +
                (state === 'on' ? 'border-primary' : 'border-border')
              }
            >
              <span
                className={
                  'grid size-[22px] flex-shrink-0 place-items-center rounded-full text-[11px] font-bold ' +
                  (state === 'on'
                    ? 'bg-primary text-primary-foreground'
                    : state === 'done'
                      ? 'bg-st-active-bg text-st-active'
                      : 'border border-input bg-popover text-muted-foreground')
                }
              >
                {state === 'done' ? <Check className="size-3.5" /> : m.n}
              </span>
              <span className="min-w-0 leading-tight">
                <span className={'block text-[12.5px] font-semibold ' + (state === 'idle' ? 'text-muted-foreground' : 'text-foreground')}>
                  {m.t}
                </span>
                <small className="block text-[10.5px] text-muted-foreground">{m.s}</small>
              </span>
            </div>
          )
        })}
      </div>

      <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-[1fr_320px]">
        <div>
          <div className="rounded-[12px] border border-border bg-card p-5">
            {step === 1 && (
              <div className="space-y-4">
                <div>
                  <h2 className="text-[15px] font-semibold">Builder details</h2>
                  <p className="text-xs text-muted-foreground">The company you just signed — becomes a tenant row.</p>
                </div>
                <Field label="Builder name" required>
                  <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Acme Builders" autoFocus />
                </Field>
                <Field label="Timezone">
                  <select className={selectCls} value={timezone} onChange={(e) => setTimezone(e.target.value)}>
                    <option value="Asia/Kolkata">Asia/Kolkata (IST)</option>
                    <option value="Asia/Dubai">Asia/Dubai</option>
                  </select>
                </Field>
              </div>
            )}

            {step === 2 && (
              <div className="space-y-4">
                <div>
                  <h2 className="text-[15px] font-semibold">First admin account</h2>
                  <p className="text-xs text-muted-foreground">The one login you hand over. They add their own team after.</p>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <Field label="Full name">
                    <Input value={adminName} onChange={(e) => setAdminName(e.target.value)} placeholder="Rahul Mehta" />
                  </Field>
                  <Field label="Login username" required>
                    <Input className="font-mono" value={username} onChange={(e) => setUsername(e.target.value)} placeholder="rahul.acme" autoComplete="off" />
                  </Field>
                </div>
                <p className="text-[11px] text-muted-foreground">
                  Signs in as <span className="font-mono text-foreground">{displayUser}</span>
                </p>
                <Field label="Temporary password">
                  <div className="flex gap-2">
                    <Input className="font-mono" value={password} readOnly />
                    <Button variant="outline" type="button" onClick={regen}><RefreshCw /> Regenerate</Button>
                  </div>
                </Field>
                <p className="text-[11px] text-muted-foreground">Auto-generated. They&apos;re forced to change it on first login.</p>
              </div>
            )}

            {step === 3 && (
              <div className="space-y-4">
                <div>
                  <h2 className="text-[15px] font-semibold">Plan &amp; first window</h2>
                  <p className="text-xs text-muted-foreground">Where they start. You can renew/extend later from their row.</p>
                </div>

                {plans.length === 0 ? (
                  <p className="rounded-[8px] border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                    No active plans. Seed a plan before provisioning a paid builder.
                  </p>
                ) : (
                  <Field label="Plan">
                    <div className="space-y-2">
                      {plans.map((p) => (
                        <button
                          key={p.id}
                          type="button"
                          onClick={() => { setPlanId(p.id); setAmount(String(p.price_inr)) }}
                          className={
                            'flex w-full items-center justify-between rounded-[10px] border px-3.5 py-3 text-left ' +
                            (planId === p.id ? 'border-primary bg-primary/8' : 'border-input bg-background')
                          }
                        >
                          <span>
                            <b className="text-sm">{p.name}</b>
                            <small className="ml-2 text-muted-foreground">{p.interval_months} month{p.interval_months > 1 ? 's' : ''}</small>
                          </span>
                          <span className="font-mono text-sm font-semibold">{inr(p.price_inr)}</span>
                        </button>
                      ))}
                    </div>
                  </Field>
                )}

                <Field label="Start as">
                  <div className="flex flex-wrap gap-2">
                    <Chip on={start === 'trial'} onClick={() => setStart('trial')}>Trial (14 days free)</Chip>
                    <Chip on={start === 'paid'} onClick={() => setStart('paid')} disabled={plans.length === 0}>Paid now</Chip>
                  </div>
                </Field>

                {start === 'trial' ? (
                  <p className="text-[11px] text-muted-foreground">Works free for 14 days, then needs a recharge. No money recorded now.</p>
                ) : (
                  <div className="grid grid-cols-2 gap-3">
                    <Field label="Amount (₹)">
                      <Input inputMode="numeric" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, ''))} aria-invalid={amount.length > 0 && !amountValid} />
                    </Field>
                    <Field label="Method">
                      <select className={selectCls} value={method} onChange={(e) => setMethod(e.target.value as PaymentMethod)}>
                        {PAYMENT_METHODS.map((m) => <option key={m} value={m}>{m}</option>)}
                      </select>
                    </Field>
                  </div>
                )}

                {/* Story 9.7 step-up — a fresh authenticator code to actually create the account. */}
                <Field label="Authenticator code" required>
                  <Input
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    maxLength={6}
                    placeholder="••••••"
                    value={mfaCode}
                    onChange={(e) => setMfaCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                    className="text-center font-mono tracking-[0.4em]"
                  />
                  <p className="text-[11px] text-muted-foreground">Confirms it&apos;s you before a new builder login is created.</p>
                </Field>
              </div>
            )}
          </div>

          <div className="mt-5 flex justify-between gap-2.5">
            <Button variant="ghost" onClick={() => setStep(step - 1)} disabled={step === 1 || busy}>Back</Button>
            <Button onClick={next} disabled={(step === 1 && !step1ok) || (step === 2 && !step2ok) || (step === 3 && !canProvision)}>
              {step === 3 ? (busy ? 'Provisioning…' : 'Provision builder') : 'Continue'}
            </Button>
          </div>
        </div>

        {/* Summary rail */}
        <aside className="h-fit rounded-[12px] border border-border bg-popover p-4 lg:sticky lg:top-6">
          <p className="eyebrow mb-3">Summary</p>
          <Kv k="Builder" v={name.trim() || <span className="text-muted-foreground">—</span>} />
          <Kv k="First admin" v={<span className="font-mono text-xs">{displayUser}</span>} />
          <Kv k="Plan" v={selectedPlan?.name ?? '—'} />
          <Kv k="Start" v={start === 'paid' ? `Paid ${amountValid ? inr(amountNum) : ''}` : 'Trial'} last />
          <div className="mt-3.5 border-t border-border pt-3.5">
            <p className="eyebrow mb-2.5">What this does</p>
            <ul className="space-y-2 text-[11.5px] text-muted-foreground">
              <li>Creates the tenant + its first admin login</li>
              <li>Sets status &amp; the first paid-until window</li>
              <li>Writes an audit-log row (who provisioned whom)</li>
            </ul>
          </div>
          <p className="mt-3.5 text-[11px] leading-relaxed text-muted-foreground">
            No money moves here. &quot;Paid now&quot; records a collection you already took (UPI/cash).
          </p>
        </aside>
      </div>
    </div>
  )
}

function Field({ label, required, children }: { label: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label className="text-[10.5px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
        {label}{required && <span className="text-primary">*</span>}
      </Label>
      {children}
    </div>
  )
}

function Chip({ on, disabled, onClick, children }: { on: boolean; disabled?: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className={
        'cursor-pointer rounded-[8px] border px-3 py-2 text-[12.5px] transition-colors disabled:opacity-40 ' +
        (on ? 'border-primary bg-primary/10 text-foreground' : 'border-input bg-background text-muted-foreground hover:text-foreground')
      }
    >
      {children}
    </button>
  )
}

function Kv({ k, v, last }: { k: string; v: React.ReactNode; last?: boolean }) {
  return (
    <div className={'flex items-center justify-between gap-3 py-2 text-[12.5px] ' + (last ? '' : 'border-b border-dashed border-border')}>
      <span className="text-muted-foreground">{k}</span>
      <span className="text-right font-medium">{v}</span>
    </div>
  )
}

function CredRow({ label, value, mono, last, onCopy }: { label: string; value: string; mono?: boolean; last?: boolean; onCopy: (v: string) => void }) {
  return (
    <div className={'flex items-center justify-between gap-3 py-2.5 ' + (last ? '' : 'border-b border-dashed border-border')}>
      <span className="text-[10.5px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">{label}</span>
      <span className="flex items-center gap-2.5">
        <span className={mono ? 'font-mono text-[13px]' : 'text-[13px]'}>{value}</span>
        <button onClick={() => onCopy(value)} className="rounded-[6px] border border-input bg-popover p-1 text-muted-foreground hover:text-foreground" aria-label={`Copy ${label}`}>
          <Copy className="size-3.5" />
        </button>
      </span>
    </div>
  )
}
