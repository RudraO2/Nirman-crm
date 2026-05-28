import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Toaster } from '@/components/ui/sonner'
import { GlobalSearch } from '@/components/global-search'

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const role = user.app_metadata?.role
  if (role !== 'admin') redirect('/login')

  return (
    <div className="flex min-h-full flex-col">
      <header className="sticky top-0 z-10 flex h-14 items-center gap-6 border-b bg-background/95 px-6 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <Link href="/leads" className="text-sm font-semibold tracking-tight">Nirman CRM</Link>
        <nav className="flex items-center gap-1">
          <Link
            href="/leads"
            className="rounded-md px-3 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            Leads
          </Link>
          <Link
            href="/team"
            className="rounded-md px-3 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            Team
          </Link>
          <Link
            href="/future-pool"
            className="rounded-md px-3 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            Future Pool
          </Link>
          <Link
            href="/projects"
            className="rounded-md px-3 py-1.5 text-sm text-muted-foreground transition hover:bg-muted hover:text-foreground"
          >
            Projects
          </Link>
        </nav>
        <div className="ml-auto flex items-center gap-3">
          <GlobalSearch />
          <span className="text-xs text-muted-foreground">{user.email}</span>
        </div>
      </header>
      <main className="flex-1">{children}</main>
      <Toaster position="bottom-right" />
    </div>
  )
}
