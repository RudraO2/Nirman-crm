import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import { TabStrip } from '@/components/tab-strip'

type Metrics = {
  leads_today: number
  leads_yesterday: number
  followups_missed_today: number
  followups_missed_yesterday: number
  sold_this_month: number
  sold_last_month: number
}

/** Percent change vs the prior period, derived from numbers already fetched. */
function delta(cur: number, prev: number): string | null {
  if (!prev) return null
  const pct = Math.round(((cur - prev) / prev) * 100)
  if (pct === 0) return null
  return `${pct > 0 ? '+' : '−'}${Math.abs(pct)}%`
}

export default async function HomePage() {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_builder_home_metrics')

  if (error) {
    return <p className="text-danger">Failed to load metrics: {error.message}</p>
  }

  const m = (data as Metrics[] | null)?.[0]
  if (!m) {
    return <p className="text-danger">Failed to load metrics: no data returned.</p>
  }

  const cards = [
    {
      title: 'Leads today',
      value: m.leads_today,
      ref: `vs ${m.leads_yesterday} yesterday`,
      delta: delta(m.leads_today, m.leads_yesterday),
      href: '/leads',
    },
    {
      title: 'Follow-ups missed',
      value: m.followups_missed_today,
      ref: `vs ${m.followups_missed_yesterday} yesterday`,
      delta: delta(m.followups_missed_today, m.followups_missed_yesterday),
      href: '/leads',
    },
    {
      title: 'Sold this month',
      value: m.sold_this_month,
      ref: `vs ${m.sold_last_month} last month`,
      delta: delta(m.sold_this_month, m.sold_last_month),
      href: '/leads?status=sold',
    },
  ]

  return (
    <div className="space-y-5">
      <div className="space-y-2">
        <p className="eyebrow">Today</p>
        <h1 className="font-serif text-[29px] font-medium leading-[1.15] tracking-[-0.01em] text-ink">
          Business <em className="font-normal italic text-ink-2">at a glance</em>
        </h1>
      </div>

      <TabStrip />

      <div className="grid grid-cols-1 gap-3.5 sm:grid-cols-3">
        {cards.map((card) => (
          <Link
            key={card.title}
            href={card.href}
            className="group block rounded-[14px] border border-line bg-paper p-5 shadow-[var(--shadow)] transition-colors hover:border-brass"
          >
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-ink-2">
              {card.title}
            </p>
            <p className="mt-2 font-serif text-[38px] font-medium leading-[1.1] tabular-nums text-ink">
              {card.value}
            </p>
            <p className="mt-1 text-xs text-ink-3">
              {card.ref}
              {card.delta && (
                <span className="ml-1.5 inline-block rounded-[6px] bg-brass-soft px-[7px] py-px text-[11px] font-bold text-brass">
                  {card.delta}
                </span>
              )}
            </p>
          </Link>
        ))}
      </div>
    </div>
  )
}
