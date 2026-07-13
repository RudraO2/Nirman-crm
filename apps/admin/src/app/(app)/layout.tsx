import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Toaster } from '@/components/ui/sonner'
import { GlobalSearch } from '@/components/global-search'
import { AppSidebar } from '@/components/app-sidebar'
import { InventorySignalProvider } from '@/components/inventory-signal'
import { PausedRecharge } from '@/components/billing/paused-recharge'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const role = user.app_metadata?.role
  if (role !== 'admin') redirect('/login')

  // Story 9.6 — server-side lockout gate. When this admin's tenant has lapsed
  // (server-enforced via the 0056 chokepoint + 0092 hard cutoff), render the
  // recharge screen instead of the app. This runs on the server, so it cannot be
  // removed client-side — and the data RPCs behind it fail-closed regardless.
  // Fail-open on a read error (network) — the server chokepoint is still the gate.
  // Progressive disclosure §1 — tenant_uses_inventory fetched alongside billing
  // (independent; one wasted read on the rare paused-tenant render is cheaper than
  // a serial round-trip on every navigation). Sidebar + tab strips consume it via
  // context; router.refresh() after the first project insert re-runs this,
  // unfolding the Inventory group. Fail-open on a read error (null → true):
  // never hide earned navigation.
  const [{ data: billing }, { data: invSignal }] = await Promise.all([
    supabase.rpc('get_my_billing_status'),
    supabase.rpc('tenant_uses_inventory'),
  ])
  const usesInventory = invSignal !== false
  const b = billing as {
    status?: string
    plan_name?: string | null
    days_remaining?: number | null
  } | null
  const status = b?.status
  if (status && status !== 'active' && status !== 'trial') {
    return <PausedRecharge planName={b?.plan_name ?? null} daysRemaining={b?.days_remaining ?? null} />
  }

  // Advance-expiry warning: active/trial but within the 3-day window.
  const days = b?.days_remaining
  const showWarning =
    (status === 'active' || status === 'trial') && days != null && days >= 0 && days <= 3

  return (
    <InventorySignalProvider usesInventory={usesInventory}>
    <div className="flex min-h-full bg-ivory">
      <AppSidebar email={user.email} />
      <div className="flex min-w-0 flex-1 flex-col">
        {showWarning && (
          <div className="flex items-center gap-2 border-b border-amber-200 bg-amber-50 px-8 py-2.5 text-sm text-amber-800">
            <span aria-hidden="true">⚠️</span>
            <span>
              Your subscription ends in <strong>{days} day{days === 1 ? '' : 's'}</strong> — please recharge to keep access.
            </span>
          </div>
        )}
        {/* Slim top bar — keeps global search reachable on every page */}
        <header className="sticky top-0 z-10 flex h-14 items-center justify-end gap-4 border-b border-line bg-ivory/85 px-8 backdrop-blur-sm">
          <GlobalSearch />
        </header>
        <main className="mx-auto w-full max-w-[1180px] flex-1 px-8 py-8">{children}</main>
      </div>
      <Toaster position="bottom-right" />
    </div>
    </InventorySignalProvider>
  )
}
