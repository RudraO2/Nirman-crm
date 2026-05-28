import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Toaster } from '@/components/ui/sonner'
import { GlobalSearch } from '@/components/global-search'

const NAV_ITEMS: Array<{ href: string; label: string }> = [
  { href: '/leads',       label: 'Leads' },
  { href: '/team',        label: 'Team' },
  { href: '/future-pool', label: 'Future Pool' },
  { href: '/performance', label: 'Performance' },
  { href: '/funnel',      label: 'Funnel' },
  { href: '/activity',    label: 'Activity' },
  { href: '/import',      label: 'Import' },
  { href: '/export',      label: 'Export' },
  { href: '/projects',    label: 'Projects' },
]

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const role = user.app_metadata?.role
  if (role !== 'admin') redirect('/login')

  return (
    <div className="flex min-h-full flex-col bg-[var(--cream)]">
      {/* Navy-deep top bar — crisp, no rounding, cream text */}
      <header
        className="sticky top-0 z-10 border-b"
        style={{
          background: 'var(--navy-deep)',
          borderColor: 'rgba(192, 179, 149, 0.15)',
        }}
      >
        <div className="flex h-14 items-center gap-8 px-6">
          <Link
            href="/leads"
            className="font-medium tracking-tight"
            style={{
              fontFamily: 'var(--font-serif)',
              color: 'var(--cream)',
              fontSize: '18px',
            }}
          >
            Nirman <em className="font-normal">CRM</em>
          </Link>
          <nav className="flex items-center gap-1">
            {NAV_ITEMS.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="rounded-md px-3 py-1.5 text-sm transition-colors hover:bg-white/5"
                style={{ color: 'rgba(242, 235, 219, 0.78)' }}
              >
                {item.label}
              </Link>
            ))}
          </nav>
          <div className="ml-auto flex items-center gap-4">
            <GlobalSearch />
            <span className="text-xs" style={{ color: 'rgba(242, 235, 219, 0.65)' }}>
              {user.email}
            </span>
          </div>
        </div>
      </header>
      <main className="flex-1">{children}</main>
      <Toaster position="bottom-right" />
    </div>
  )
}
