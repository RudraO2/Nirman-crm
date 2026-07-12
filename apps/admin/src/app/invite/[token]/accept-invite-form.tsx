"use client"
import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

// Story 8.4 — invitee sets their own username + password; the accept-invite
// edge fn validates the single-use token and creates the account. Styled to
// match the login page (same evergreen/brass field classes).
export function AcceptInviteForm({ token }: { token: string }) {
  const [fullName, setFullName] = useState('')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (password !== confirm) {
      setError('Passwords do not match.')
      return
    }
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const response = await supabase.functions.invoke('accept-invite', {
      body: {
        token,
        username: username.trim(),
        password,
        ...(fullName.trim() ? { full_name: fullName.trim() } : {}),
      },
    })
    setLoading(false)
    if (response.error || !response.data?.data?.username) {
      const code = response.data?.error?.code as string | undefined
      if (code === 'unauthorised') {
        setError('This invite link is invalid, expired, or already used. Ask your admin for a new one.')
      } else if (code === 'user_already_exists') {
        setError('That username is already taken — pick another.')
      } else if (code === 'forbidden_tenant') {
        setError('This workspace is not accepting new members right now.')
      } else if (code === 'validation_error') {
        setError('Check the fields: username min 3 chars, password min 8.')
      } else {
        setError('Could not create the account. Try again.')
      }
      return
    }
    setDone(response.data.data.username as string)
  }

  const fieldCls =
    'w-full rounded-[13px] border-[1.5px] px-4 py-3 text-[15px] text-[#F2EEE2] outline-none ' +
    'placeholder:text-[rgba(233,228,214,.3)] focus:border-brass-bright disabled:opacity-60 ' +
    'bg-[rgba(233,228,214,.07)] border-[rgba(233,228,214,.16)]'
  const labelCls =
    'mb-1.5 block text-[11px] font-bold uppercase tracking-[0.1em] text-[rgba(233,228,214,.5)]'

  return (
    <div
      className="flex min-h-screen w-full flex-col justify-center px-6 py-10"
      style={{ background: 'linear-gradient(175deg, var(--evergreen) 0%, var(--evergreen-3) 55%, #0A1912 100%)' }}
    >
      <div className="mx-auto w-full max-w-sm">
        <div className="mb-5 grid size-[58px] place-items-center rounded-[17px] bg-brass font-serif text-[27px] font-semibold italic text-[var(--evergreen-3)]">
          N
        </div>

        {done ? (
          <>
            <h1 className="font-serif text-[30px] font-medium leading-[1.15] text-[#F2EEE2]">
              You&apos;re in! 🎉
            </h1>
            <p className="mb-8 mt-2 text-[13.5px] text-[rgba(233,228,214,.55)]">
              Your account is ready. Sign in on the <b>Nirman CRM mobile app</b> with
              username <span className="font-mono text-brass-bright">{done}</span> and
              the password you just set.
            </p>
          </>
        ) : (
          <>
            <h1 className="font-serif text-[30px] font-medium leading-[1.15] text-[#F2EEE2]">
              Join your team on Nirman <em className="not-italic text-brass-bright">CRM</em>
            </h1>
            <p className="mb-8 mt-2 text-[13.5px] text-[rgba(233,228,214,.55)]">
              Pick a username and password — you&apos;ll use them to sign in on the mobile app.
            </p>

            {error && (
              <div className="mb-5 rounded-[12px] border border-[rgba(179,55,43,.45)] bg-[rgba(179,55,43,.15)] px-4 py-3 text-sm text-[#F0B7B0]">
                {error}
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-3.5">
              <div>
                <label htmlFor="full-name" className={labelCls}>Your name (optional)</label>
                <input id="full-name" value={fullName} onChange={(e) => setFullName(e.target.value)}
                  maxLength={120} autoComplete="name" disabled={loading} className={fieldCls} />
              </div>
              <div>
                <label htmlFor="username" className={labelCls}>Username</label>
                <input id="username" value={username} onChange={(e) => setUsername(e.target.value)}
                  required minLength={3} maxLength={100} autoComplete="username"
                  placeholder="e.g. priya" disabled={loading} className={fieldCls} />
                <p className="mt-1 text-[11px] text-[rgba(233,228,214,.4)]">
                  Plain names sign in as name@employees.nirman.local
                </p>
              </div>
              <div>
                <label htmlFor="password" className={labelCls}>Password</label>
                <input id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                  required minLength={8} maxLength={72} autoComplete="new-password"
                  disabled={loading} className={fieldCls} />
              </div>
              <div>
                <label htmlFor="confirm" className={labelCls}>Confirm password</label>
                <input id="confirm" type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)}
                  required minLength={8} maxLength={72} autoComplete="new-password"
                  disabled={loading} className={fieldCls} />
              </div>
              <button
                type="submit"
                disabled={loading}
                className="mt-3.5 w-full rounded-[13px] bg-brass py-[15px] text-[15px] font-bold text-white transition-transform active:scale-[.98] disabled:opacity-60"
              >
                {loading ? 'Creating account…' : 'Create my account'}
              </button>
            </form>
          </>
        )}

        <p className="mt-6 text-center text-xs text-[rgba(233,228,214,.35)]">
          Nirman CRM · invited by your builder admin
        </p>
      </div>
    </div>
  )
}
