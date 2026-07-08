import { createClient } from '@/lib/supabase/server'
import { TemplatesClient } from './templates-client'

export interface TemplateRow {
  id: string
  name: string
  body: string
  updated_at: string
}

export default async function TemplatesPage() {
  const supabase = await createClient()
  // tenant_id has no column default — inserts must carry it (RLS re-checks it).
  const { data: { user } } = await supabase.auth.getUser()
  const tenantId = (user?.app_metadata?.tenant_id as string | undefined) ?? ''
  const { data: templates } = await supabase
    .from('whatsapp_templates')
    .select('id, name, body, updated_at')
    .order('created_at', { ascending: true })

  return <TemplatesClient initial={(templates ?? []) as TemplateRow[]} tenantId={tenantId} />
}
