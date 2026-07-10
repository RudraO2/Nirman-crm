import { createClient } from '@/lib/supabase/server'
import { ProvisionFlow } from '@/components/provision-flow'
import type { Plan } from '@/lib/types'

export default async function ProvisionPage() {
  const supabase = await createClient()
  const { data } = await supabase.rpc('ops_list_plans')
  const plans = (data ?? []) as Plan[]
  return <ProvisionFlow plans={plans} />
}
