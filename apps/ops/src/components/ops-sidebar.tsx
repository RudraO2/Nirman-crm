'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { Building2, ScrollText, LogOut, UserPlus } from 'lucide-react'
import { cn } from '@/lib/utils'
import { createClient } from '@/lib/supabase/client'

const NAV = [
  { label: 'Tenants', hint: 'billing · lifecycle', href: '/', icon: Building2, match: (p: string) => p === '/' },
  { label: 'Provision', hint: 'onboard a builder', href: '/provision', icon: UserPlus, match: (p: string) => p.startsWith('/provision') },
  { label: 'Audit log', hint: 'immutable trail', href: '/audit', icon: ScrollText, match: (p: string) => p.startsWith('/audit') },
]

export function OpsSidebar({ email }: { email?: string | null }) {
  const pathname = usePathname()
  const router = useRouter()

  async function signOut() {
    await createClient().auth.signOut()
    router.push('/login')
    router.refresh()
  }

  return (
    <aside className="sticky top-0 flex h-screen w-[200px] flex-shrink-0 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground">
      {/* Brand */}
      <div className="flex items-center gap-2.5 px-4 py-4">
        <div className="grid size-8 place-items-center rounded-[8px] bg-primary text-[15px] font-bold text-primary-foreground">
          N
        </div>
        <div className="leading-tight">
          <div className="text-[13px] font-semibold text-[#F2F4F8]">Nirman Ops</div>
          <div className="text-[10px] tracking-wide text-muted-foreground">PLATFORM CONSOLE</div>
        </div>
      </div>

      <nav className="flex-1 px-2.5 py-1.5">
        {NAV.map((item) => {
          const active = item.match(pathname)
          const Icon = item.icon
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                'mb-0.5 flex items-center gap-2.5 rounded-[8px] px-2.5 py-2 text-[13px] font-medium transition-colors',
                active
                  ? 'bg-sidebar-accent text-sidebar-accent-foreground'
                  : 'text-sidebar-foreground/70 hover:bg-sidebar-accent/60 hover:text-sidebar-accent-foreground',
              )}
            >
              <Icon className={cn('size-4 flex-shrink-0', active ? 'text-primary' : 'opacity-70')} />
              <span className="leading-tight">
                {item.label}
                <small className="mt-px block text-[10px] font-normal text-muted-foreground">
                  {item.hint}
                </small>
              </span>
            </Link>
          )
        })}
      </nav>

      {/* Footer — operator identity + sign out */}
      <div className="border-t border-sidebar-border p-3">
        <div className="mb-2 flex items-center gap-2 px-1">
          <div className="grid size-7 flex-shrink-0 place-items-center rounded-full bg-sidebar-accent text-[11px] font-bold text-primary">
            {(email ?? 'OP').replace(/[^a-zA-Z]/g, '').slice(0, 2).toUpperCase() || 'OP'}
          </div>
          <div className="min-w-0">
            <b className="block truncate text-[11.5px] text-[#F2F4F8]">{email ?? 'operator'}</b>
            <span className="text-[10px] text-muted-foreground">Platform admin</span>
          </div>
        </div>
        <button
          onClick={signOut}
          className="flex w-full cursor-pointer items-center gap-2 rounded-[7px] px-2 py-1.5 text-[12px] text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
        >
          <LogOut className="size-3.5" />
          Sign out
        </button>
      </div>
    </aside>
  )
}
