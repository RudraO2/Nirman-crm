'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'

interface UnlockAccountButtonProps {
  employeeId: string
}

export function UnlockAccountButton({ employeeId }: UnlockAccountButtonProps) {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleUnlock() {
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const { data, error: fnError } = await supabase.functions.invoke('manage-employee', {
      body: { action: 'unlock', targetUserId: employeeId },
    })
    if (fnError || data?.error) {
      setLoading(false)
      setError(data?.error?.message ?? fnError?.message ?? 'Unlock failed')
      return
    }
    setLoading(false)
    router.refresh()
  }

  return (
    <div className="flex flex-col gap-1">
      <Button
        variant="outline"
        size="sm"
        onClick={handleUnlock}
        disabled={loading}
        className="text-amber-600 border-amber-600 hover:bg-amber-50"
      >
        {loading ? 'Unlocking…' : 'Unlock'}
      </Button>
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
