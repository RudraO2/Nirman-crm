import { createClient } from '@/lib/supabase/server'
import { ProjectsClient } from './projects-client'

export interface ProjectRow {
  id: string
  name: string
  property_type: string | null
  is_active: boolean
  created_at: string
}

export default async function ProjectsPage() {
  const supabase = await createClient()
  const { data: projects, error } = await supabase
    .from('projects')
    .select('id, name, property_type, is_active, created_at')
    .order('created_at', { ascending: false })

  if (error) {
    return (
      <div className="p-6">
        <p className="text-destructive">Failed to load projects: {error.message}</p>
      </div>
    )
  }

  return (
    <ProjectsClient initialProjects={(projects ?? []) as ProjectRow[]} />
  )
}
