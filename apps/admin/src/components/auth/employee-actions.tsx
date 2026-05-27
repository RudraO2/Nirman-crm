"use client"
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'

interface EmployeeActionsProps {
  employeeId: string
  isActive: boolean
}

export function EmployeeActions({ employeeId, isActive }: EmployeeActionsProps) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const router = useRouter()

  async function handleAction(action: 'deactivate' | 'reactivate') {
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const { data, error: fnError } = await supabase.functions.invoke('manage-employee', {
      body: { action, targetUserId: employeeId },
    })
    if (fnError || data?.error) {
      setLoading(false)
      setError(data?.error?.message ?? fnError?.message ?? 'Action failed')
      return
    }
    router.refresh()
    setLoading(false)
  }

  return (
    <div className="flex flex-col items-start gap-1">
      {isActive ? (
        <Button
          variant="destructive"
          size="sm"
          disabled={loading}
          onClick={() => handleAction('deactivate')}
        >
          {loading ? 'Working…' : 'Deactivate'}
        </Button>
      ) : (
        <Button
          variant="outline"
          size="sm"
          disabled={loading}
          onClick={() => handleAction('reactivate')}
        >
          {loading ? 'Working…' : 'Reactivate'}
        </Button>
      )}
      {error && <p className="text-destructive text-xs">{error}</p>}
    </div>
  )
}
