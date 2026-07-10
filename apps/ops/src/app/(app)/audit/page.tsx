import { createClient } from '@/lib/supabase/server'
import { AuditTable } from '@/components/audit-table'
import type { OpsAuditRow } from '@/lib/types'

const PAGE = 100

export default async function AuditPage() {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('ops_list_audit', { p_limit: PAGE, p_offset: 0 })
  const rows = (data ?? []) as OpsAuditRow[]
  return <AuditTable initialRows={rows} loadError={error?.message ?? null} pageSize={PAGE} />
}
