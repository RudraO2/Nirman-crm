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
  title?: string
  description?: string
}

export function GeneratedPasswordModal({
  password,
  onDismiss,
  title = 'Employee Account Created',
  description = 'Convey to employee out of band. This will not be shown again.',
}: Props) {
  // password held only in React state — never in localStorage, sessionStorage, or URL
  // onDismiss sets parent state to null — plaintext is garbage-collected immediately
  return (
    <Dialog open={password !== null} onOpenChange={(open) => { if (!open) onDismiss() }}>
      <DialogContent onPointerDownOutside={(e) => e.preventDefault()} onEscapeKeyDown={(e) => e.preventDefault()} onInteractOutside={(e) => e.preventDefault()}>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
          <DialogDescription>
            {description}
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
