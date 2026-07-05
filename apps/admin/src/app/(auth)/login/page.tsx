"use client"
import { useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

function LoginForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(
    searchParams.get('error') === 'not_authorised'
      ? 'Account not authorised for web access.'
      : null
  )

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)

    const supabase = createClient()

    const response = await supabase.functions.invoke('login', {
      body: {
        username: username.trim().toLowerCase(),
        password,
        platform: 'web',
      },
    })

    setLoading(false)

    if (response.error || !response.data?.data?.access_token) {
      const code = response.data?.error?.code as string | undefined
      const message = response.data?.error?.message as string | undefined
      if (code === 'unauthorised_platform') {
        setError('This account is not authorised for web access.')
      } else if (code === 'unauthorised') {
        setError(message ?? 'Invalid username or password.')
      } else {
        setError('Login failed. Please try again.')
      }
      return
    }

    const { access_token, refresh_token } = response.data.data as {
      access_token: string
      refresh_token: string
    }

    const { error: sessionErr } = await supabase.auth.setSession({
      access_token,
      refresh_token,
    })

    if (sessionErr) {
      setError('Failed to establish session. Please try again.')
      return
    }

    router.push('/')
    router.refresh()
  }

  const fieldCls =
    'w-full rounded-[13px] border-[1.5px] px-4 py-3 text-[15px] text-[#F2EEE2] outline-none ' +
    'placeholder:text-[rgba(233,228,214,.3)] focus:border-brass-bright disabled:opacity-60 ' +
    'bg-[rgba(233,228,214,.07)] border-[rgba(233,228,214,.16)]'
  const labelCls =
    'mb-1.5 block text-[11px] font-bold uppercase tracking-[0.1em] text-[rgba(233,228,214,.5)]'

  return (
    <div
      className="flex min-h-screen flex-col justify-center px-6 py-10"
      style={{ background: 'linear-gradient(175deg, var(--evergreen) 0%, var(--evergreen-3) 55%, #0A1912 100%)' }}
    >
      <div className="mx-auto w-full max-w-sm">
        {/* Brass logo mark */}
        <div
          className="mb-5 grid size-[58px] place-items-center rounded-[17px] bg-brass font-serif text-[27px] font-semibold italic text-[var(--evergreen-3)]"
        >
          N
        </div>

        <h1 className="font-serif text-[30px] font-medium leading-[1.15] text-[#F2EEE2]">
          Nirman <em className="not-italic text-brass-bright">CRM</em>
        </h1>
        <p className="mb-8 mt-2 text-[13.5px] text-[rgba(233,228,214,.55)]">
          Admin Dashboard
        </p>

        {error && (
          <div className="mb-5 rounded-[12px] border border-[rgba(179,55,43,.45)] bg-[rgba(179,55,43,.15)] px-4 py-3 text-sm text-[#F0B7B0]">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-3.5">
          <div>
            <label htmlFor="username" className={labelCls}>Username</label>
            <input
              id="username"
              value={username}
              onChange={e => setUsername(e.target.value)}
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
              onChange={e => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              disabled={loading}
              className={fieldCls}
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="mt-3.5 w-full rounded-[13px] bg-brass py-[15px] text-[15px] font-bold text-white transition-transform active:scale-[.98] disabled:opacity-60"
          >
            {loading ? 'Signing in…' : 'Sign In'}
          </button>
        </form>

        {/* Footer — quiet meta line */}
        <p className="mt-6 text-center text-xs text-[rgba(233,228,214,.35)]">
          Editorial CRM · Builder-side discipline
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
