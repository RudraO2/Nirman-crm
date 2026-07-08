import { createClient } from '@/lib/supabase/server'
import { DeveloperUpdatesClient } from './developer-updates-client'

export interface UpdProjectRow {
  id: string
  name: string
}

export default async function DeveloperUpdatesPage() {
  const supabase = await createClient()
  const { data: projects } = await supabase
    .from('projects')
    .select('id, name')
    .order('name', { ascending: true })

  return <DeveloperUpdatesClient projects={(projects ?? []) as UpdProjectRow[]} />
}
