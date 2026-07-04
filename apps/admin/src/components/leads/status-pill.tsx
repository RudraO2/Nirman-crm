import { cn } from '@/lib/utils'

// §3 status palette — tinted pill + colored dot (mockup `.pill`)
const STATUS_CLASS: Record<string, string> = {
  hot:    'bg-hot-bg text-hot',
  warm:   'bg-warm-bg text-warm',
  cold:   'bg-cold-bg text-cold',
  dead:   'bg-dead-bg text-dead',
  sold:   'bg-sold-bg text-sold',
  future: 'bg-future-bg text-future',
}

export function StatusPill({ status }: { status: string }) {
  const cls = STATUS_CLASS[status] ?? 'bg-muted text-muted-foreground'
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11.5px] font-semibold capitalize',
        cls,
      )}
    >
      <span className="size-1.5 rounded-full bg-current" />
      {status}
    </span>
  )
}
