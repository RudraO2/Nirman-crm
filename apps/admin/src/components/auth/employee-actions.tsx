"use client"
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { DeactivationBlockedDialog } from './deactivation-blocked-dialog'

interface EmployeeActionsProps {
  employeeId: string
  employeeName: string
  isActive: boolean
}

export function EmployeeActions({ employeeId, employeeName, isActive }: EmployeeActionsProps) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [blockedDialogOpen, setBlockedDialogOpen] = useState(false)
  const router = useRouter()

  async function handleReactivate() {
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const { data, error: fnError } = await supabase.functions.invoke('manage-employee', {
      body: { action: 'reactivate', targetUserId: employeeId },
    })
    if (fnError || data?.error) {
      setLoading(false)
      setError(data?.error?.message ?? fnError?.message ?? 'Action failed')
      return
    }
    router.refresh()
    setLoading(false)
  }

  async function handleDeactivateClick() {
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const { data: count, error: rpcErr } = await supabase.rpc(
      'get_employee_active_lead_count',
      { p_employee_id: employeeId }
    )
    if (rpcErr) {
      setLoading(false)
      setError(rpcErr.message ?? 'Failed to check leads.')
      return
    }
    setLoading(false)
    if ((count as number) > 0) {
      setBlockedDialogOpen(true)
      return
    }
    // No active leads — proceed directly
    setLoading(true)
    const { data, error: fnError } = await supabase.functions.invoke('manage-employee', {
      body: { action: 'deactivate', targetUserId: employeeId },
    })
    if (fnError || data?.error) {
      setLoading(false)
      setError(data?.error?.message ?? fnError?.message ?? 'Action failed')
      return
    }
    router.refresh()
    setLoading(false)
  }

  function handleDeactivateSuccess() {
    setBlockedDialogOpen(false)
    router.refresh()
  }

  return (
    <>
      <div className="flex flex-col items-start gap-1">
        {isActive ? (
          <Button
            variant="destructive"
            size="sm"
            disabled={loading}
            onClick={handleDeactivateClick}
          >
            {loading ? 'Working…' : 'Deactivate'}
          </Button>
        ) : (
          <Button
            variant="outline"
            size="sm"
            disabled={loading}
            onClick={handleReactivate}
          >
            {loading ? 'Working…' : 'Reactivate'}
          </Button>
        )}
        {error && <p className="text-destructive text-xs">{error}</p>}
      </div>

      <DeactivationBlockedDialog
        employeeId={employeeId}
        employeeName={employeeName}
        open={blockedDialogOpen}
        onOpenChange={setBlockedDialogOpen}
        onSuccess={handleDeactivateSuccess}
      />
    </>
  )
}
