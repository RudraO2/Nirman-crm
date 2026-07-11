// Instant loading skeleton for /funnel (deferred 5.3 F-3). Prevents the brief blank
// on a filter-change navigation.
export default function Loading() {
  return (
    <div className="p-6" aria-busy="true" aria-label="Loading funnel">
      <div className="mb-6 h-7 w-40 animate-pulse rounded bg-muted" />
      <div className="mb-6 flex flex-wrap gap-2">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-8 w-28 animate-pulse rounded-md bg-muted" />
        ))}
      </div>
      <div className="space-y-3 rounded-lg border border-border p-5">
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            className="h-12 animate-pulse rounded bg-muted/60"
            style={{ width: `${100 - i * 14}%` }}
          />
        ))}
      </div>
    </div>
  )
}
