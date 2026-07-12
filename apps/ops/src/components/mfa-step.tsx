"use client"

// Story 9.7 — TOTP MFA step shown on the login page after a platform-admin passes
// the password + is_platform_admin gate but is not yet at AAL2.
//
//   mode="enroll"    — first-time setup: enroll a TOTP factor, render the QR + secret,
//                      then challenge+verify the code the authenticator app produces.
//   mode="challenge" — returning admin who already has a verified factor: challenge
//                      the existing factor and verify a fresh code.
//
// A successful verify upgrades the session to AAL2; onComplete() then routes into the
// console. The server (app) layout independently re-checks AAL2, so this UI is a
// convenience/entry point, never the sole authority.

import { useEffect, useRef, useState } from 'react'
import { createClient } from '@/lib/supabase/client'

type Mode = 'enroll' | 'challenge'

const fieldCls =
  'w-full rounded-[10px] border border-input bg-[#0E1219] px-3.5 py-2.5 text-sm text-foreground outline-none ' +
  'placeholder:text-muted-foreground focus:border-ring focus:ring-3 focus:ring-ring/30 disabled:opacity-60 ' +
  'text-center tracking-[0.4em] font-mono'
const labelCls =
  'mb-1.5 block text-[10.5px] font-semibold uppercase tracking-[0.1em] text-muted-foreground'

export function MfaStep({
  mode,
  onComplete,
}: {
  mode: Mode
  onComplete: () => void
}) {
  const [factorId, setFactorId] = useState('')
  const [qr, setQr] = useState('') // enroll only: SVG QR (usable as <img src>)
  const [secret, setSecret] = useState('') // enroll only: manual-entry secret
  const [code, setCode] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [setupErr, setSetupErr] = useState<string | null>(null)
  const setupRan = useRef(false)

  // Enroll (or locate the existing factor) once on mount.
  useEffect(() => {
    if (setupRan.current) return
    setupRan.current = true
    const supabase = createClient()
    ;(async () => {
      try {
        if (mode === 'challenge') {
          const { data, error } = await supabase.auth.mfa.listFactors()
          if (error) throw error
          const totp = data.totp[0]
          if (!totp) throw new Error('No authenticator is set up on this account.')
          setFactorId(totp.id)
          return
        }

        // enroll: clear any abandoned unverified factors so we never orphan them,
        // then enroll a fresh one.
        const list = await supabase.auth.mfa.listFactors()
        if (!list.error) {
          for (const f of list.data.all) {
            if (f.factor_type === 'totp' && f.status === 'unverified') {
              await supabase.auth.mfa.unenroll({ factorId: f.id })
            }
          }
        }
        const { data, error } = await supabase.auth.mfa.enroll({
          factorType: 'totp',
          friendlyName: `ops-${Date.now()}`,
        })
        if (error) throw error
        setFactorId(data.id)
        setQr(data.totp.qr_code)
        setSecret(data.totp.secret)
      } catch (e) {
        setSetupErr(
          e instanceof Error
            ? e.message
            : 'Could not start two-factor setup. Try again.'
        )
      }
    })()
  }, [mode])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!factorId || busy) return
    setBusy(true)
    setError(null)
    const supabase = createClient()
    try {
      const challenge = await supabase.auth.mfa.challenge({ factorId })
      if (challenge.error) throw challenge.error
      const verify = await supabase.auth.mfa.verify({
        factorId,
        challengeId: challenge.data.id,
        code: code.trim(),
      })
      if (verify.error) throw verify.error
      onComplete()
    } catch {
      setError('That code did not match. Check your authenticator and try again.')
      setBusy(false)
    }
  }

  if (setupErr) {
    return (
      <div className="mt-6 rounded-[10px] border border-destructive/40 bg-destructive/12 px-3.5 py-2.5 text-sm text-destructive">
        {setupErr}
      </div>
    )
  }

  return (
    <div className="mt-6">
      <p className="eyebrow">
        {mode === 'enroll' ? 'Set up two-factor authentication' : 'Two-factor authentication'}
      </p>

      {mode === 'enroll' && (
        <div className="mt-3 space-y-3">
          <p className="text-[13px] leading-relaxed text-muted-foreground">
            Scan this QR with an authenticator app (Google Authenticator, Authy, 1Password),
            then enter the 6-digit code to finish.
          </p>
          {qr ? (
            <div className="grid place-items-center rounded-[12px] border border-input bg-white p-3">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={qr} alt="TOTP QR code" width={168} height={168} />
            </div>
          ) : (
            <div className="h-[192px] animate-pulse rounded-[12px] bg-muted/40" />
          )}
          {secret && (
            <p className="break-all text-center font-mono text-[11px] text-muted-foreground">
              Can’t scan? Enter this key: <span className="text-foreground">{secret}</span>
            </p>
          )}
        </div>
      )}

      {error && (
        <div className="mt-4 rounded-[10px] border border-destructive/40 bg-destructive/12 px-3.5 py-2.5 text-sm text-destructive">
          {error}
        </div>
      )}

      <form onSubmit={submit} className="mt-4 space-y-3.5">
        <div>
          <label htmlFor="mfa-code" className={labelCls}>
            6-digit code
          </label>
          <input
            id="mfa-code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]*"
            maxLength={6}
            value={code}
            onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
            required
            autoFocus
            disabled={busy}
            className={fieldCls}
            placeholder="••••••"
          />
        </div>
        <button
          type="submit"
          disabled={busy || code.length !== 6 || !factorId}
          className="w-full cursor-pointer rounded-[10px] bg-primary py-3 text-sm font-semibold text-primary-foreground transition-opacity active:scale-[.99] disabled:opacity-60"
        >
          {busy ? 'Verifying…' : mode === 'enroll' ? 'Enable & continue' : 'Verify'}
        </button>
      </form>
    </div>
  )
}
