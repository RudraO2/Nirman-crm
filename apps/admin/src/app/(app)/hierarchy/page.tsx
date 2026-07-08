import { createClient } from '@/lib/supabase/server'
import { HierarchyClient } from './hierarchy-client'

export interface HierUser {
  id: string
  email_or_username: string
  role: string
  role_tier: string | null
  reports_to_user_id: string | null
  agency_id: string | null
  is_external: boolean
  is_active: boolean
}

export interface Agency {
  id: string
  name: string
}

export default async function HierarchyPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  const [usersRes, agenciesRes] = await Promise.all([
    supabase
      .from('users')
      .select('id, email_or_username, role, role_tier, reports_to_user_id, agency_id, is_external, is_active')
      .eq('is_active', true)
      .order('email_or_username'),
    supabase.from('agencies').select('id, name').order('name'),
  ])

  if (usersRes.error) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load team: {usersRes.error.message}</p>
      </div>
    )
  }

  return (
    <HierarchyClient
      currentUserId={user?.id ?? ''}
      tenantId={(user?.app_metadata?.tenant_id as string) ?? ''}
      users={(usersRes.data ?? []) as HierUser[]}
      agencies={(agenciesRes.data ?? []) as Agency[]}
    />
  )
}
