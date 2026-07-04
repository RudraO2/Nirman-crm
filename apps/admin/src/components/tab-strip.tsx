'use client'

import Link from 'next/link'
import { usePathname, useSearchParams } from 'next/navigation'
import { cn } from '@/lib/utils'
import { activeGroup, tabIsActive } from '@/components/nav'

/**
 * Row of styled <Link>s to the current group's sibling routes (§2). Auto-derives
 * the group from the pathname; no route merging, no data moves. `counts` is an
 * optional map (tab.href → number) that a page can pass when it already has the
 * numbers — never fabricated here.
 */
export function TabStrip({ counts }: { counts?: Record<string, number> }) {
  const pathname = usePathname()
  const params = useSearchParams()
  const archived = !!params.get('archived')
  const group = activeGroup(pathname)
  if (!group) return null

  return (
    <div className="mb-5 flex gap-1 border-b-2 border-line">
      {group.tabs.map((tab) => {
        const on = tabIsActive(tab, pathname, archived)
        const count = counts?.[tab.href]
        return (
          <Link
            key={tab.href}
            href={tab.href}
            className={cn(
              '-mb-0.5 border-b-2 px-4 py-2.5 text-[13.5px] font-semibold transition-all',
              on
                ? 'border-brass text-brass'
                : 'border-transparent text-ink-2 hover:text-ink',
            )}
          >
            {tab.label}
            {count != null && (
              <span className="ml-1.5 rounded-full bg-mist px-1.5 py-px text-[10.5px] text-ink-2">
                {count}
              </span>
            )}
          </Link>
        )
      })}
    </div>
  )
}
