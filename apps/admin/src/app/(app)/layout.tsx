import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Toaster } from '@/components/ui/sonner'
import { GlobalSearch } from '@/components/global-search'
import { AppSidebar } from '@/components/app-sidebar'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const role = user.app_metadata?.role
  if (role !== 'admin') redirect('/login')

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
