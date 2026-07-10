import type { TenantStatus } from './types'

/**
 * Relative billing label from days_remaining (server-computed by the RPC via
 * server now(), so we stay consistent with the list's ordering — do NOT
 * recompute from paid_until on the client, which would drift by clock skew).
 *   null           -> "—"          (never enrolled: live V1 tenant + trials)
 *   d < 0          -> "overdue Nd"
 *   d === 0        -> "due today"
 *   d > 0          -> "in Nd"
 */
export function relativeDays(days: number | null): string {
  if (days === null || days === undefined) return '—'
  if (days < 0) return `overdue ${Math.abs(days)}d`
  if (days === 0) return 'due today'
  return `in ${days}d`
}

/** Left-border urgency accent for a list row, by days_remaining. */
export function rowUrgency(days: number | null): 'overdue' | 'expiring' | 'none' {
  if (days === null || days === undefined) return 'none'
  if (days < 0) return 'overdue'
  if (days <= 7) return 'expiring'
  return 'none'
}

/**
 * The pill label to render. "Grace" is a UI-derived state: an `active` tenant
 * whose paid_until has already passed (days_remaining < 0) but which the hourly
 * expire_lapsed_tenants() sweep has not yet flipped to suspended.
 */
export function pillLabel(status: TenantStatus, days: number | null): string {
  if (status === 'active' && days !== null && days < 0) return 'Grace'
  return status.charAt(0).toUpperCase() + status.slice(1)
}

export type PillTone =
  | 'active'
  | 'trial'
  | 'grace'
  | 'suspended'
  | 'cancelled'

export function pillTone(status: TenantStatus, days: number | null): PillTone {
  if (status === 'active' && days !== null && days < 0) return 'grace'
  return status
}

const INR = new Intl.NumberFormat('en-IN', {
  style: 'currency',
  currency: 'INR',
  maximumFractionDigits: 0,
})

export function inr(amount: number): string {
  return INR.format(amount)
}

/** Compact absolute timestamp for ledger / audit (local tz). */
export function fmtDateTime(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

export function fmtDate(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleDateString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  })
}

/**
 * Map a Postgres/PostgREST error to operator-readable copy. The ops RPCs raise
 * 42501 permission_denied, P0002 tenant_not_found / plan_not_found_or_inactive.
 */
export function rpcErrorMessage(err: unknown): string {
  const e = err as { code?: string; message?: string } | null
  const raw = e?.message ?? ''
  if (e?.code === '42501' || /permission_denied/.test(raw))
    return 'Permission denied — this account is not a platform admin.'
  if (/plan_not_found_or_inactive/.test(raw))
    return 'Selected plan not found or inactive.'
  if (e?.code === 'P0002' || /tenant_not_found/.test(raw))
    return 'Tenant not found.'
  if (/username_taken/.test(raw))
    return 'That username is already taken — pick another.'
  if (/weak_password/.test(raw))
    return 'Password too short (min 8 characters).'
  if (/builder_name_required/.test(raw)) return 'Builder name is required.'
  if (/admin_username_required/.test(raw)) return 'Admin username is required.'
  if (/paid_start_needs_plan_amount_method/.test(raw))
    return 'A paid start needs a plan, amount and method.'
  return raw || 'Something went wrong. Please retry.'
}
