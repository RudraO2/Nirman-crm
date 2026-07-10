// Story 9.4 — shapes returned by the 0089 ops RPCs (frozen contracts).

export type TenantStatus = 'trial' | 'active' | 'suspended' | 'cancelled'

/** ops_list_tenants() row. */
export interface OpsTenant {
  tenant_id: string
  name: string
  status: TenantStatus
  plan_name: string | null
  paid_until: string | null
  days_remaining: number | null
}

/** ops_list_tenant_payments() row (SETOF tenant_payments). */
export interface TenantPayment {
  id: string
  tenant_id: string
  plan_id: string
  amount_inr: number
  method: PaymentMethod
  paid_at: string
  covers_from: string
  covers_until: string
  recorded_by: string | null
  note: string | null
  created_at: string
}

/** ops_list_audit() row (SETOF ops_audit_log). */
export interface OpsAuditRow {
  id: string
  seq: number
  actor_user_id: string | null
  action: string
  target_tenant_id: string | null
  detail: Record<string, unknown> | null
  created_at: string
}

/** tenant_payments.method CHECK domain (0088). */
export type PaymentMethod =
  | 'upi'
  | 'cash'
  | 'bank_transfer'
  | 'razorpay'
  | 'comp'
  | 'other'

export const PAYMENT_METHODS: PaymentMethod[] = [
  'upi',
  'cash',
  'bank_transfer',
  'comp',
  'other',
]

/** ops_renew_tenant() return. */
export interface RenewResult {
  tenant_id: string
  status: TenantStatus
  paid_until: string
  payment_id: string
}

/** Plan row (subset — for the renew form's plan_id). */
export interface Plan {
  id: string
  name: string
  price_inr: number
  interval_months: number
  is_active: boolean
}
