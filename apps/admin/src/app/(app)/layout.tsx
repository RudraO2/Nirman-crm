import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Toaster } from '@/components/ui/sonner'
import { GlobalSearch } from '@/components/global-search'
import { AppSidebar } from '@/components/app-sidebar'
import { PausedRecharge } from '@/components/billing/paused-recharge'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const role = user.app_metadata?.role
  if (role !== 'admin') redirect('/login')

  // Story 9.6 — server-side lockout gate. When this admin's tenant has lapsed
  // (server-enforced via the 0056 chokepoint; billing is admin-only), render the
  // recharge screen instead of the app. This runs on the server, so it cannot be
  // removed client-side — and the data RPCs behind it fail-closed regardless.
  // Fail-open on a read error (network) — the server chokepoint is still the gate.
  const { data: billing } = await supabase.rpc('get_my_billing_status')
  const status = (billing as { status?: string } | null)?.status
  if (status && status !== 'active' && status !== 'trial') {
    const b = billing as { plan_name?: string | null; days_remaining?: number | null }
    return <PausedRecharge planName={b.plan_name ?? null} daysRemaining={b.days_remaining ?? null} />
  }

  return (
    <div className="flex min-h-full bg-ivory">
      <AppSidebar email={user.email} />
      <div className="flex min-w-0 flex-1 flex-col">
        {/* Slim top bar — keeps global search reachable on every page */}
        <header className="sticky top-0 z-10 flex h-14 items-center justify-end gap-4 border-b border-line bg-ivory/85 px-8 backdrop-blur-sm">
          <GlobalSearch />
        </header>
        <main className="mx-auto w-full max-w-[1180px] flex-1 px-8 py-8">{children}</main>
      </div>
      <Toaster position="bottom-right" />
    </div>
  )
}
