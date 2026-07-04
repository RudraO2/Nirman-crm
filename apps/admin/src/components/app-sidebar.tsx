'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { cn } from '@/lib/utils'
import { NAV_GROUPS, groupIsActive } from '@/components/nav'

export function AppSidebar({ email }: { email?: string | null }) {
  const pathname = usePathname()
  const initials = (email ?? 'AD').replace(/[^a-zA-Z]/g, '').slice(0, 2).toUpperCase() || 'AD'

  return (
    <aside className="sticky top-0 flex h-screen w-[220px] flex-shrink-0 flex-col bg-gradient-to-b from-evergreen to-evergreen-3 text-[#E9E4D6]">
      {/* Brand */}
      <div className="flex items-center gap-2.5 px-5 py-6">
        <div className="grid size-[34px] place-items-center rounded-[9px] bg-brass font-serif text-[17px] font-semibold italic text-evergreen-3">
          N
        </div>
        <div className="font-serif text-[17px]">
          Nirman <em className="text-brass-bright">CRM</em>
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 py-1.5">
        {NAV_GROUPS.map((group) => {
          const active = groupIsActive(group, pathname)
          const Icon = group.icon
          return (
            <Link
              key={group.key}
              href={group.href}
              className={cn(
                'mb-[3px] flex w-full items-center gap-[11px] rounded-[10px] px-3 py-[11px] text-sm font-medium transition-all',
                active
                  ? 'bg-brass-bright/15 text-brass-bright'
                  : 'text-[#E9E4D6]/70 hover:bg-evergreen-2 hover:text-[#F2EEE2]',
              )}
            >
              <Icon className="size-[17px] flex-shrink-0 opacity-75" />
              <span className="leading-tight">
                {group.label}
                <small
                  className={cn(
                    'mt-px block text-[10.5px] font-normal',
                    active ? 'text-brass-bright/65' : 'text-[#E9E4D6]/40',
                  )}
                >
                  {group.hint}
                </small>
              </span>
            </Link>
          )
        })}
      </nav>

      {/* Footer — user identity */}
      <div className="flex items-center gap-2.5 border-t border-[#E9E4D6]/10 p-4">
        <div className="grid size-8 flex-shrink-0 place-items-center rounded-full bg-brass-soft text-xs font-bold text-evergreen">
          {initials}
        </div>
        <div className="min-w-0">
          <b className="block truncate text-[12.5px] text-[#F2EEE2]">{email ?? 'admin'}</b>
          <span className="text-[11px] text-[#E9E4D6]/50">Builder admin</span>
        </div>
      </div>
    </aside>
  )
}
