// Instant loading skeleton for /import (deferred 6.1 D-6.1-3). Shown while the
// server component fetches the employee list for the assign step.
export default function Loading() {
  return (
    <div className="p-6" aria-busy="true" aria-label="Loading import">
      <div className="mb-2 h-7 w-48 animate-pulse rounded bg-muted" />
      <div className="mb-6 h-4 w-72 animate-pulse rounded bg-muted/60" />
      <div className="space-y-4 rounded-lg border border-border p-6">
        <div className="h-32 animate-pulse rounded-lg border-2 border-dashed border-border bg-muted/30" />
        <div className="h-10 w-40 animate-pulse rounded-md bg-muted" />
      </div>
    </div>
  )
}
