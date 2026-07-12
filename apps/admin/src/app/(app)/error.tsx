'use client' // Error boundaries must be Client Components

// Route-level error boundary for every (app) segment (audit medium: none existed,
// including the money-moving holds/inventory pages — a render/data error showed
// the framework's raw error screen). Segments can still add their own error.tsx
// to override; this is the safety net.

import { useEffect } from 'react'
import { Button } from '@/components/ui/button'

export default function Error({
  error,
  unstable_retry,
}: {
  error: Error & { digest?: string }
  unstable_retry: () => void
}) {
  useEffect(() => {
    console.error(error)
  }, [error])

  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center gap-4 p-6 text-center">
      <h2 className="font-serif text-xl font-medium text-ink">Something went wrong</h2>
      <p className="max-w-md text-sm text-ink-2">
        The page hit an unexpected error. Your data is safe — retry, or navigate
        elsewhere and come back.
        {error.digest ? ` (ref ${error.digest})` : null}
      </p>
      <Button onClick={() => unstable_retry()}>Try again</Button>
    </div>
  )
}
