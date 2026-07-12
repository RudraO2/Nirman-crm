import { createClient } from '@/lib/supabase/client'

// Story 9.7 — MFA step-up. The console session is already AAL2 (login TOTP), but the
// most destructive actions (suspend a tenant, provision a new builder) demand a FRESH
// authenticator code at the moment of the action — proof the operator is present, not
// a walked-up unlocked session. This runs a fresh challenge+verify against the
// existing TOTP factor; it does not change the session's AAL, it just re-confirms.
export async function verifyStepUp(
  code: string
): Promise<{ ok: boolean; error?: string }> {
  const supabase = createClient()

  const factors = await supabase.auth.mfa.listFactors()
  if (factors.error) return { ok: false, error: factors.error.message }
  const totp = factors.data.totp[0]
  if (!totp) return { ok: false, error: 'No authenticator is set up on this account.' }

  const challenge = await supabase.auth.mfa.challenge({ factorId: totp.id })
  if (challenge.error) return { ok: false, error: challenge.error.message }

  const verify = await supabase.auth.mfa.verify({
    factorId: totp.id,
    challengeId: challenge.data.id,
    code: code.trim(),
  })
  if (verify.error) return { ok: false, error: 'That code did not match. Try again.' }

  return { ok: true }
}
