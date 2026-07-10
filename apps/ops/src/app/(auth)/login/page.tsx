"use client"

import { useState, useEffect, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

function LoginForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // If the (app) layout bounced a signed-in-but-not-authorised user here, clear
  // that stale session so the DB guard is re-evaluated on the next sign-in.
  useEffect(() => {
    if (searchParams.get('error') === 'not_authorised') {
      setError('This account is not a platform admin.')
      createClient().auth.signOut()
    }
  }, [searchParams])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)

    const supabase = createClient()

    const { error: signInErr } = await supabase.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    })

    if (signInErr) {
      setLoading(false)
      setError('Invalid email or password.')
      return
    }

    // Gate on the platform-admin allowlist (the DB guard). A valid tenant user
    // who is not in platform_admins must not reach the console.
    // TODO(9.7): MFA/TOTP step-up belongs here before granting the console.
    const { data: isAdmin, error: guardErr } = await supabase.rpc('is_platform_admin')
    if (guardErr || isAdmin !== true) {
      await supabase.auth.signOut()
      setLoading(false)
      setError('This account is not a platform admin.')
      return
    }

    router.push('/')
    router.refresh()
  }

  const fieldCls =
    'w-full rounded-[10px] border border-input bg-[#0E1219] px-3.5 py-2.5 text-sm text-foreground outline-none ' +
    'placeholder:text-muted-foreground focus:border-ring focus:ring-3 focus:ring-ring/30 disabled:opacity-60'
  const labelCls =
    'mb-1.5 block text-[10.5px] font-semibold uppercase tracking-[0.1em] text-muted-foreground'

  return (
    <div className="flex min-h-screen flex-col justify-center bg-background px-6 py-10">
      <div className="mx-auto w-full max-w-[360px]">
        <div className="mb-5 grid size-12 place-items-center rounded-[13px] bg-primary text-[24px] font-bold text-primary-foreground">
          N
        </div>

        <h1 className="text-[24px] font-semibold leading-tight text-foreground">Nirman Ops</h1>
        <p className="eyebrow mt-1.5">Platform Console — restricted access</p>

        {error && (
          <div className="mt-6 rounded-[10px] border border-destructive/40 bg-destructive/12 px-3.5 py-2.5 text-sm text-destructive">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="mt-6 space-y-3.5">
          <div>
            <label htmlFor="email" className={labelCls}>Email</label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="username"
              disabled={loading}
              className={fieldCls}
            />
          </div>
          <div>
            <label htmlFor="password" className={labelCls}>Password</label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              disabled={loading}
              className={fieldCls}
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="mt-3.5 w-full cursor-pointer rounded-[10px] bg-primary py-3 text-sm font-semibold text-primary-foreground transition-opacity active:scale-[.99] disabled:opacity-60"
          >
            {loading ? 'Verifying…' : 'Sign in'}
          </button>
        </form>

        <p className="mt-6 text-center text-[11px] text-muted-foreground">
          Platform admins only · every action is audit-logged
        </p>
      </div>
    </div>
  )
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  )
}
