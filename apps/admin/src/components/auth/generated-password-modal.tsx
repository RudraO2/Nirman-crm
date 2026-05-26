"use client"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

interface Props {
  password: string | null
  onDismiss: () => void
}

export function GeneratedPasswordModal({ password, onDismiss }: Props) {
  // password held only in React state — never in localStorage, sessionStorage, or URL
  // onDismiss sets parent state to null — plaintext is garbage-collected immediately
  return (
    <Dialog open={password !== null} onOpenChange={(open) => { if (!open) onDismiss() }}>
      <DialogContent onPointerDownOutside={(e) => e.preventDefault()}>
        <DialogHeader>
          <DialogTitle>Employee Account Created</DialogTitle>
          <DialogDescription>
            Convey to employee out of band. This will not be shown again.
          </DialogDescription>
        </DialogHeader>
        <div className="my-4 rounded bg-muted p-4 font-mono text-lg tracking-widest select-all">
          {password}
        </div>
        <DialogFooter>
          <Button onClick={onDismiss}>I have noted the password</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
