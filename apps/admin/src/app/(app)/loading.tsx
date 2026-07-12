// Group-level instant loading skeleton (audit medium: 12 of 15 (app) segments
// had no loading.tsx — navigations briefly rendered blank). Segments with their
// own loading.tsx (funnel, import, performance) still win, being deeper.
export default function Loading() {
  return (
    <div className="p-6" aria-busy="true" aria-label="Loading">
      <div className="mb-6 h-7 w-48 animate-pulse rounded bg-muted" />
      <div className="mb-6 flex flex-wrap gap-2">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="h-8 w-32 animate-pulse rounded-md bg-muted" />
        ))}
      </div>
      <div className="space-y-3 rounded-lg border border-border p-5">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="h-10 animate-pulse rounded bg-muted/60" />
        ))}
      </div>
    </div>
  )
}
