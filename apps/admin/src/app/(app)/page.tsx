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
      <div className="p-6">
        <p className="text-destructive">Failed to load metrics: {error.message}</p>
      </div>
    )
  }

  const m = (data as Metrics[] | null)?.[0]
  if (!m) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load metrics: no data returned.</p>
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
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Dashboard</h1>
        <p className="text-sm text-muted-foreground">Today&apos;s business health at a glance.</p>
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        {cards.map((card) => (
          <Link
            key={card.title}
            href={card.href}
            className="block rounded-lg border bg-card p-6 shadow-sm transition-colors hover:bg-muted"
          >
            <p className="text-sm font-medium text-muted-foreground">{card.title}</p>
            <p className="mt-2 text-4xl font-bold tracking-tight">{card.value}</p>
            <p className="mt-1 text-xs text-muted-foreground">{card.ref}</p>
          </Link>
        ))}
      </div>
    </div>
  )
}
