"use client"
import { useCallback, useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { GeneratedPasswordModal } from './generated-password-modal'

interface InvitationRow {
  id: string
  label: string
  invited_role: string
  created_at: string
  expires_at: string
  revoked_at: string | null
  accepted_at: string | null
}

// Story 8.4 — link-based invites (no email yet; links travel over WhatsApp).
// "Invite teammate" mints a single-use 7-day token via create_invitation; the raw
// link is shown ONCE (only its hash is stored). Pending invites list + revoke.
//
// Progressive disclosure §4 — this is now the ONE entry point for adding a team
// member. Link mode is the default; the old "New employee" manual form (admin sets
// username, server mints a temp password via the create-employee edge fn) lives
// behind a low-emphasis text link INSIDE this sheet — one door in, with a side room.
export function InvitePanel() {
  const router = useRouter()
  const [open, setOpen] = useState(false)
  const [manual, setManual] = useState(false)
  const [label, setLabel] = useState('')
  const [role, setRole] = useState<'employee' | 'admin'>('employee')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [freshLink, setFreshLink] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const [invites, setInvites] = useState<InvitationRow[]>([])
  // Manual mode (fallback: invitee has no phone/data in hand right now)
  const [username, setUsername] = useState('')
  const [generatedPassword, setGeneratedPassword] = useState<string | null>(null)

  const loadInvites = useCallback(async () => {
    const supabase = createClient()
    const { data } = await supabase
      .from('invitations')
      .select('id, label, invited_role, created_at, expires_at, revoked_at, accepted_at')
      .order('created_at', { ascending: false })
      .limit(20)
    setInvites((data ?? []) as InvitationRow[])
  }, [])

  useEffect(() => { loadInvites() }, [loadInvites])

  async function createInvite(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const { data, error: rpcErr } = await supabase.rpc('create_invitation', {
      p_label: label.trim(),
      p_role: role,
    })
    setLoading(false)
    if (rpcErr || !data?.token) {
      setError(rpcErr?.message ?? 'Failed to create the invite')
      return
    }
    setFreshLink(`${window.location.origin}/invite/${data.token}`)
    setCopied(false)
    setLabel('')
    setRole('employee')
    loadInvites()
  }

  async function createEmployee(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const { data, error: fnError } = await supabase.functions.invoke('create-employee', {
      body: { username: username.trim() },
    })
    setLoading(false)
    if (fnError || !data?.data?.temp_password) {
      setError(data?.error?.message ?? fnError?.message ?? 'Failed to create employee')
      return
    }
    setGeneratedPassword(data.data.temp_password)
    setUsername('')
    setOpen(false)
    router.refresh()
  }

  async function revoke(id: string) {
    const supabase = createClient()
    const { error: rpcErr } = await supabase.rpc('revoke_invitation', { p_id: id })
    if (rpcErr) setError(rpcErr.message)
    loadInvites()
  }

  function copyLink() {
    if (!freshLink) return
    navigator.clipboard?.writeText(freshLink)
    setCopied(true)
  }

  const pending = invites.filter((i) => !i.accepted_at && !i.revoked_at && new Date(i.expires_at) > new Date())

  return (
    <>
      <Button onClick={() => { setOpen(true); setManual(false); setFreshLink(null); setError(null) }}>
        Invite teammate
      </Button>

      {open && (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-evergreen-3/40 backdrop-blur-sm">
          <div className="z-50 w-full max-w-md space-y-4 rounded-[16px] border border-line bg-paper p-6 shadow-[var(--shadow-lg)]">
            <h2 className="font-serif text-lg font-medium">
              {manual ? 'Create an account directly' : 'Invite a teammate'}
            </h2>

            {freshLink ? (
              <div className="space-y-3">
                <p className="text-sm text-ink-2">
                  Share this link (WhatsApp works well). It creates <b>one</b> account
                  and expires in 7 days. It won&apos;t be shown again.
                </p>
                <div className="flex gap-2">
                  <Input readOnly value={freshLink} className="font-mono text-xs" onFocus={(e) => e.target.select()} />
                  <Button type="button" onClick={copyLink}>{copied ? 'Copied!' : 'Copy'}</Button>
                </div>
                <div className="flex justify-end">
                  <Button variant="outline" type="button" onClick={() => setOpen(false)}>Done</Button>
                </div>
              </div>
            ) : manual ? (
              <form onSubmit={createEmployee} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="username">Username / Email</Label>
                  <Input
                    id="username"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    placeholder="alice  (or  alice@nirman.com)"
                    required
                    minLength={3}
                    pattern="[a-zA-Z0-9._+\-@]+"
                    title="Letters, digits, dot, underscore, plus, hyphen, @"
                  />
                  <p className="text-xs text-muted-foreground">
                    Plain names auto-suffix with @employees.nirman.local for login.
                    You&apos;ll get a temporary password to hand over.
                  </p>
                </div>
                {error && <p className="text-destructive text-sm">{error}</p>}
                <div className="flex gap-2">
                  <Button type="submit" disabled={loading}>
                    {loading ? 'Creating…' : 'Create employee'}
                  </Button>
                  <Button variant="outline" type="button" onClick={() => { setOpen(false); setError(null) }}>
                    Cancel
                  </Button>
                </div>
                <button
                  type="button"
                  onClick={() => { setManual(false); setError(null) }}
                  className="text-xs text-ink-3 underline underline-offset-2 hover:text-ink"
                >
                  ← Back to invite link
                </button>
              </form>
            ) : (
              <form onSubmit={createInvite} className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="invite-label">Who is this for?</Label>
                  <Input
                    id="invite-label"
                    value={label}
                    onChange={(e) => setLabel(e.target.value)}
                    placeholder="e.g. Priya — new sales rep"
                    required
                    minLength={1}
                    maxLength={80}
                  />
                  <p className="text-xs text-muted-foreground">
                    Just a note for your own list — they pick their own username and password.
                  </p>
                </div>
                <div className="space-y-2">
                  <Label>Role</Label>
                  <div className="flex gap-2">
                    {(['employee', 'admin'] as const).map((r) => (
                      <button
                        key={r}
                        type="button"
                        onClick={() => setRole(r)}
                        aria-pressed={role === r}
                        className={
                          'rounded-full border px-3.5 py-1.5 text-sm capitalize transition-colors ' +
                          (role === r
                            ? 'border-evergreen bg-evergreen text-white'
                            : 'border-line bg-paper text-ink-2 hover:text-ink')
                        }
                      >
                        {r}
                      </button>
                    ))}
                  </div>
                  {role === 'admin' && (
                    <p className="text-xs text-muted-foreground">
                      Admins get full access: this dashboard, team, billing status,
                      inventory — same powers as you.
                    </p>
                  )}
                </div>
                {error && <p className="text-destructive text-sm">{error}</p>}
                <div className="flex gap-2">
                  <Button type="submit" disabled={loading}>{loading ? 'Creating…' : 'Create link'}</Button>
                  <Button variant="outline" type="button" onClick={() => { setOpen(false); setError(null) }}>Cancel</Button>
                </div>
                {/* §4 — manual creation stays as an opt-in side room, not a second door */}
                <button
                  type="button"
                  onClick={() => { setManual(true); setError(null) }}
                  className="text-xs text-ink-3 underline underline-offset-2 hover:text-ink"
                >
                  Prefer to set a password yourself? Create the account directly
                </button>
              </form>
            )}

            {!manual && pending.length > 0 && (
              <div className="border-t border-line pt-3">
                <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-3">Pending invites</p>
                <ul className="space-y-1.5">
                  {pending.map((i) => (
                    <li key={i.id} className="flex items-center justify-between gap-2 text-sm">
                      <span className="truncate">
                        {i.label}
                        {i.invited_role === 'admin' && (
                          <span className="ml-1.5 rounded bg-evergreen/10 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-evergreen">
                            admin
                          </span>
                        )}
                      </span>
                      <span className="flex items-center gap-2">
                        <span className="whitespace-nowrap text-xs tabular-nums text-ink-3">
                          expires {new Date(i.expires_at).toLocaleDateString()}
                        </span>
                        <button
                          type="button"
                          onClick={() => revoke(i.id)}
                          className="text-xs text-destructive hover:underline"
                        >
                          Revoke
                        </button>
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        </div>
      )}

      <GeneratedPasswordModal
        password={generatedPassword}
        onDismiss={() => setGeneratedPassword(null)}
      />
    </>
  )
}
