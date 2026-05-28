import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'

type Metrics = {
  leads_today: number
  leads_yesterday: number
  followups_missed_today: number
  followups_missed_yesterday: number
  sold_this_month: number
  sold_last_month: number
}

export default async function HomePage() {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_builder_home_metrics')

  if (error) {
    return (
      <div className="p-8">
        <p className="text-[var(--rust)]">Failed to load metrics: {error.message}</p>
      </div>
    )
  }

  const m = (data as Metrics[] | null)?.[0]
  if (!m) {
    return (
      <div className="p-8">
        <p className="text-[var(--rust)]">Failed to load metrics: no data returned.</p>
      </div>
    )
  }

  const cards = [
    {
      title: 'Leads Today',
      value: m.leads_today,
      ref: `vs ${m.leads_yesterday} yesterday`,
      href: '/leads',
    },
    {
      title: 'Follow-ups Missed',
      value: m.followups_missed_today,
      ref: `vs ${m.followups_missed_yesterday} yesterday`,
      href: '/leads',
    },
    {
      title: 'Sold This Month',
      value: m.sold_this_month,
      ref: `vs ${m.sold_last_month} last month`,
      href: '/leads?status=sold',
    },
  ]

  return (
    <div className="mx-auto max-w-[1280px] px-6 py-10 space-y-10">
      <div className="space-y-2">
        <p className="eyebrow">Today</p>
        <h1
          className="text-4xl tracking-tight text-[var(--ink)]"
          style={{ fontFamily: 'var(--font-serif)', fontWeight: 500 }}
        >
          Business <em className="font-normal italic">at a glance</em>
        </h1>
      </div>

      <div className="grid grid-cols-1 gap-6 sm:grid-cols-3">
        {cards.map((card) => (
          <Link
            key={card.title}
            href={card.href}
            className="group block rounded-[12px] border bg-[var(--cream-raised)] p-6 transition-colors hover:border-[var(--line-strong)]"
            style={{ borderColor: 'var(--line)' }}
          >
            <p className="eyebrow text-[var(--ink-soft)]">{card.title}</p>
            <p
              className="mt-3 text-5xl tabular-nums tracking-tight text-[var(--ink)]"
              style={{ fontFamily: 'var(--font-serif)', fontWeight: 500 }}
            >
              {card.value}
            </p>
            <p className="mt-2 text-xs text-[var(--ink-soft)]">{card.ref}</p>
          </Link>
        ))}
      </div>
    </div>
  )
}
