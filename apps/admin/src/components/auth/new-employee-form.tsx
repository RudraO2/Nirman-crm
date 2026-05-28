"use client"
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { GeneratedPasswordModal } from './generated-password-modal'

export function NewEmployeeForm() {
  const [open, setOpen] = useState(false)
  const [username, setUsername] = useState('')
  const [generatedPassword, setGeneratedPassword] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const router = useRouter()

  async function handleSubmit(e: React.FormEvent) {
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
    setOpen(false)
    router.refresh()
  }

  return (
    <>
      <Button onClick={() => setOpen(true)}>Add Employee</Button>
      {open && (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40">
          <form
            onSubmit={handleSubmit}
            className="bg-background rounded-lg border p-6 space-y-4 w-full max-w-sm shadow-lg z-50"
          >
            <h2 className="text-lg font-semibold">Add Employee</h2>
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
              </p>
            </div>
            {error && <p className="text-destructive text-sm">{error}</p>}
            <div className="flex gap-2">
              <Button type="submit" disabled={loading}>
                {loading ? 'Creating…' : 'Create Employee'}
              </Button>
              <Button variant="outline" type="button" onClick={() => { setOpen(false); setError(null) }}>
                Cancel
              </Button>
            </div>
          </form>
        </div>
      )}
      <GeneratedPasswordModal
        password={generatedPassword}
        onDismiss={() => setGeneratedPassword(null)}
      />
    </>
  )
}
