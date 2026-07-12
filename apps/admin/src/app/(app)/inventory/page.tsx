import { createClient } from '@/lib/supabase/server'
import { InventoryClient } from './inventory-client'

export interface InventoryProjectRow {
  id: string
  name: string
  hold_timer_hours: number | null
  is_active: boolean
}

export default async function InventoryPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  // tenant_id has no column default — inserts must carry it (RLS re-checks it).
  const tenantId = (user?.app_metadata?.tenant_id as string | undefined) ?? ''
  const { data: projects, error } = await supabase
    .from('projects')
    .select('id, name, hold_timer_hours, is_active')
    .order('name', { ascending: true })

  if (error) {
    return <p className="text-danger">Failed to load projects: {error.message}</p>
  }

  return (
    <InventoryClient
      projects={(projects ?? []) as InventoryProjectRow[]}
      tenantId={tenantId}
    />
  )
}
