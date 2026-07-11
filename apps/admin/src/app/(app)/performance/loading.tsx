// Instant loading skeleton for /performance (deferred 5.2 D1). Keeps the layout
// stable while the server component fetches stats on a range-filter navigation.
export default function Loading() {
  return (
    <div className="p-6" aria-busy="true" aria-label="Loading performance dashboard">
      <div className="mb-6 h-7 w-56 animate-pulse rounded bg-muted" />
      <div className="mb-6 flex gap-2">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="h-8 w-24 animate-pulse rounded-md bg-muted" />
        ))}
      </div>
      <div className="mb-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-24 animate-pulse rounded-lg border border-border bg-muted/40" />
        ))}
      </div>
      <div className="space-y-2 rounded-lg border border-border p-4">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="h-10 animate-pulse rounded bg-muted/60" />
        ))}
      </div>
    </div>
  )
}
