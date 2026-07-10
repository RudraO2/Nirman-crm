import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Toaster } from '@/components/ui/sonner'
import { OpsSidebar } from '@/components/ops-sidebar'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  // Authority check = the DB guard, not a client claim. A user who is not in
  // platform_admins is bounced back to /login (which signs the stale session
  // out). Every RPC re-guards with is_platform_admin() regardless.
  // TODO(9.7): MFA/TOTP step-up should gate here before the console renders.
  const { data: isAdmin, error } = await supabase.rpc('is_platform_admin')
  // A transient RPC error must NOT be read as "not authorised" (that path signs
  // the session out on the login page). Bounce to /login for a clean re-auth
  // instead; only an explicit `false` means the account lacks platform-admin.
  if (error) redirect('/login')
  if (isAdmin !== true) redirect('/login?error=not_authorised')

  return (
    <div className="flex min-h-screen bg-background">
      <OpsSidebar email={user.email} />
      <main className="min-w-0 flex-1">{children}</main>
      <Toaster position="bottom-right" />
    </div>
  )
}
