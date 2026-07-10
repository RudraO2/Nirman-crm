import { createClient } from '@/lib/supabase/server'
import { TenantConsole } from '@/components/tenant-console'
import type { OpsTenant, Plan } from '@/lib/types'

// Server-fetched initial data (guarded RPCs, platform-admin JWT via cookies).
export default async function TenantsPage() {
  const supabase = await createClient()

  const [tenantsRes, plansRes] = await Promise.all([
    supabase.rpc('ops_list_tenants'),
    supabase.rpc('ops_list_plans'),
  ])

  const tenants = (tenantsRes.data ?? []) as OpsTenant[]
  const plans = (plansRes.data ?? []) as Plan[]
  const loadError = tenantsRes.error?.message ?? null

  return <TenantConsole initialTenants={tenants} plans={plans} loadError={loadError} />
}
