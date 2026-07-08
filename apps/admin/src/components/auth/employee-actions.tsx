"use client"
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { DeactivationBlockedDialog } from './deactivation-blocked-dialog'
import { GeneratedPasswordModal } from './generated-password-modal'

interface EmployeeActionsProps {
  employeeId: string
  employeeName: string
  isActive: boolean
}

export function EmployeeActions({ employeeId, employeeName, isActive }: EmployeeActionsProps) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [blockedDialogOpen, setBlockedDialogOpen] = useState(false)
  const [resetConfirmOpen, setResetConfirmOpen] = useState(false)
  const [resetLoading, setResetLoading] = useState(false)
  const [newPassword, setNewPassword] = useState<string | null>(null)
  const router = useRouter()

  async function handleResetPassword() {
    setResetLoading(true)
    setError(null)
    const supabase = createClient()
    const { data, error: fnError } = await supabase.functions.invoke('reset-employee-password', {
      body: { targetUserId: employeeId },
    })
    setResetLoading(false)
    if (fnError || !data?.data?.temp_password) {
      setError(data?.error?.message ?? fnError?.message ?? 'Failed to reset password')
      return
    }
    setResetConfirmOpen(false)
    setNewPassword(data.data.temp_password)
    router.refresh()
  }

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
      <div className="flex flex-col items-end gap-1">
        <div className="flex items-center justify-end gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={resetLoading}
            onClick={() => { setError(null); setResetConfirmOpen(true) }}
          >
            Reset password
          </Button>
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
        </div>
        {error && <p className="text-destructive text-xs">{error}</p>}
      </div>

      <DeactivationBlockedDialog
        employeeId={employeeId}
        employeeName={employeeName}
        open={blockedDialogOpen}
        onOpenChange={setBlockedDialogOpen}
        onSuccess={handleDeactivateSuccess}
      />

      <Dialog open={resetConfirmOpen} onOpenChange={(open) => { if (!resetLoading) setResetConfirmOpen(open) }}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Reset password for {employeeName}?</DialogTitle>
            <DialogDescription>
              A new temporary password will be generated and shown once. Their current
              sessions are signed out and they must set a new password on next login.
            </DialogDescription>
          </DialogHeader>
          {error && <p className="text-destructive text-sm">{error}</p>}
          <DialogFooter>
            <Button
              variant="outline"
              type="button"
              disabled={resetLoading}
              onClick={() => setResetConfirmOpen(false)}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              type="button"
              disabled={resetLoading}
              onClick={handleResetPassword}
            >
              {resetLoading ? 'Resetting…' : 'Reset password'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <GeneratedPasswordModal
        password={newPassword}
        onDismiss={() => setNewPassword(null)}
        title={`New password for ${employeeName}`}
        description="Convey to the user out of band. This will not be shown again."
      />
    </>
  )
}
