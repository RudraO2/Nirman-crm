import { createClient } from '@/lib/supabase/server'
import { HoldsClient } from './holds-client'

export interface HoldsProjectRow {
  id: string
  name: string
}

export default async function HoldsPage() {
  const supabase = await createClient()
  const { data: projects } = await supabase
    .from('projects')
    .select('id, name')
    .order('name', { ascending: true })

  return <HoldsClient projects={(projects ?? []) as HoldsProjectRow[]} />
}
