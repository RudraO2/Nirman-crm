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

    // AC-7: Call login Edge Function with platform=web
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

    // Establish Supabase session from the Edge Function tokens
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
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="w-full max-w-sm space-y-6 rounded-lg border bg-card p-6 shadow-sm">
        <div className="space-y-1 text-center">
          <h1 className="text-2xl font-semibold tracking-tight">Nirman CRM</h1>
          <p className="text-sm text-muted-foreground">Admin Dashboard</p>
        </div>

        {error && (
          <div className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive border border-destructive/20">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="username">Username</Label>
            <Input
              id="username"
              value={username}
              onChange={e => setUsername(e.target.value)}
              required
              autoComplete="username"
              disabled={loading}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              disabled={loading}
            />
          </div>
          <Button type="submit" disabled={loading} className="w-full">
            {loading ? 'Signing in…' : 'Sign In'}
          </Button>
        </form>
      </div>
    </div>
  )
}

// Suspense required: useSearchParams() suspends in Next.js App Router during SSG
export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  )
}
