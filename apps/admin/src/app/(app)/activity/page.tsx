import { createClient } from '@/lib/supabase/server'
import { ActivityView, type ActivityRow } from '@/components/activity/activity-view'

export default async function ActivityPage() {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_employee_activity_stats')

  if (error) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load activity data: {error.message}</p>
      </div>
    )
  }

  return <ActivityView employees={(data ?? []) as ActivityRow[]} />
}
