"use client"
import { useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'

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

  return (
    <div className="flex min-h-screen items-center justify-center bg-[var(--cream)] px-4">
      <div className="w-full max-w-md">
        {/* Editorial header — outside the card, on cream */}
        <div className="mb-8 text-center">
          <p className="eyebrow mb-3">Nirman Media</p>
          <h1
            className="text-5xl font-medium tracking-tight text-[var(--ink)]"
            style={{ fontFamily: 'var(--font-serif)' }}
          >
            Nirman <em className="font-normal italic">CRM</em>
          </h1>
          <p className="mt-3 text-sm text-[var(--ink-soft)]">
            Admin Dashboard
          </p>
        </div>

        {/* Card — cream-raised on cream, hairline border, no shadow */}
        <div
          className="rounded-[20px] border p-8"
          style={{
            background: 'var(--cream-raised)',
            borderColor: 'var(--line)',
          }}
        >
          {error && (
            <div
              className="mb-6 rounded-md border px-4 py-3 text-sm"
              style={{
                background: 'rgba(156, 61, 42, 0.08)',
                borderColor: 'rgba(156, 61, 42, 0.25)',
                color: 'var(--rust)',
              }}
            >
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-5">
            <div className="space-y-2">
              <Label
                htmlFor="username"
                className="text-xs font-medium uppercase tracking-wider text-[var(--ink-soft)]"
              >
                Username
              </Label>
              <Input
                id="username"
                value={username}
                onChange={e => setUsername(e.target.value)}
                required
                autoComplete="username"
                disabled={loading}
                className="h-11 rounded-md border-[var(--line)] bg-[var(--cream-sunk)] px-4 text-[var(--ink)] placeholder:text-[var(--ink-disabled)] focus-visible:border-[var(--gold-deep)] focus-visible:ring-2 focus-visible:ring-[var(--gold-deep)]/30"
              />
            </div>
            <div className="space-y-2">
              <Label
                htmlFor="password"
                className="text-xs font-medium uppercase tracking-wider text-[var(--ink-soft)]"
              >
                Password
              </Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                required
                autoComplete="current-password"
                disabled={loading}
                className="h-11 rounded-md border-[var(--line)] bg-[var(--cream-sunk)] px-4 text-[var(--ink)] placeholder:text-[var(--ink-disabled)] focus-visible:border-[var(--gold-deep)] focus-visible:ring-2 focus-visible:ring-[var(--gold-deep)]/30"
              />
            </div>
            <Button
              type="submit"
              disabled={loading}
              className="h-11 w-full rounded-full text-sm font-semibold tracking-wide transition-colors"
              style={{
                background: 'var(--gold-bright)',
                color: 'var(--ink)',
              }}
            >
              {loading ? 'Signing in…' : 'Sign In'}
            </Button>
          </form>
        </div>

        {/* Footer — quiet meta line */}
        <p className="mt-6 text-center text-xs text-[var(--ink-disabled)]">
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
