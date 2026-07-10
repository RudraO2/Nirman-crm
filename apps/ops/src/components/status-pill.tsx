import { cn } from "@/lib/utils"
import { pillLabel, pillTone } from "@/lib/format"
import type { TenantStatus } from "@/lib/types"

const TONE_CLS: Record<string, string> = {
  active: "bg-st-active-bg text-st-active",
  trial: "bg-st-trial-bg text-st-trial",
  grace: "bg-st-grace-bg text-st-grace",
  suspended: "bg-st-suspended-bg text-st-suspended",
  cancelled: "bg-st-cancelled-bg text-st-cancelled",
}

/**
 * Status pill. `days` lets us surface the UI-derived "Grace" state (an active
 * tenant already past paid_until, awaiting the hourly sweep) — pass it from the
 * row's days_remaining. Omit for contexts with no billing window (uses the raw
 * enum status).
 */
export function StatusPill({
  status,
  days = null,
  className,
}: {
  status: TenantStatus
  days?: number | null
  className?: string
}) {
  const tone = pillTone(status, days)
  return (
    <span
      className={cn(
        "inline-flex h-[19px] w-fit items-center gap-1.5 rounded-full px-2 text-[11px] font-semibold tracking-wide",
        TONE_CLS[tone],
        className
      )}
    >
      <span className="size-1.5 rounded-full bg-current opacity-80" />
      {pillLabel(status, days)}
    </span>
  )
}
