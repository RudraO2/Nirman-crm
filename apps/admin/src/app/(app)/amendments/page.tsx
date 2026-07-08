import { createClient } from '@/lib/supabase/server'
import { AmendmentsClient } from './amendments-client'

export interface OrgUser {
  id: string
  email_or_username: string
}

export default async function AmendmentsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  const [usersRes, teamRes] = await Promise.all([
    supabase.from('users').select('id, email_or_username').eq('is_active', true).order('email_or_username'),
    supabase.from('tenant_execution_team').select('user_id'),
  ])

  const teamIds = (teamRes.data ?? []).map((r) => r.user_id as string)

  return (
    <AmendmentsClient
      currentUserId={user?.id ?? ''}
      users={(usersRes.data ?? []) as OrgUser[]}
      initialTeamIds={teamIds}
    />
  )
}
