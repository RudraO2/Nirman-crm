import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'

const STATUS_CLASS: Record<string, string> = {
  hot:    'bg-red-500/15 text-red-700 dark:text-red-300 border-red-500/30',
  warm:   'bg-amber-500/15 text-amber-700 dark:text-amber-300 border-amber-500/30',
  cold:   'bg-slate-500/15 text-slate-700 dark:text-slate-300 border-slate-500/30',
  dead:   'bg-zinc-500/15 text-zinc-700 dark:text-zinc-300 border-zinc-500/30',
  sold:   'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border-emerald-500/30',
  future: 'bg-violet-500/15 text-violet-700 dark:text-violet-300 border-violet-500/30',
}

export function StatusPill({ status }: { status: string }) {
  const cls = STATUS_CLASS[status] ?? 'bg-muted text-muted-foreground'
  return (
    <Badge variant="outline" className={cn('uppercase tracking-wide text-[10px] font-medium', cls)}>
      {status}
    </Badge>
  )
}
