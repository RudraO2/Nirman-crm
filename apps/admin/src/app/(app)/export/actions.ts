'use server'

import { createClient } from '@/lib/supabase/server'

interface ExportFilters {
  status: string | null
  employeeId: string | null
  projectId: string | null
  propertyType: string | null
  dateFrom: string | null
  dateTo: string | null
}

export async function getExportCountAction(filters: ExportFilters): Promise<number> {
  const supabase = await createClient()

  const { data, error } = await supabase.rpc('get_export_count', {
    p_status:        filters.status,
    p_employee_id:   filters.employeeId,
    p_project_id:    filters.projectId,
    p_property_type: filters.propertyType,
    p_date_from:     filters.dateFrom,
    p_date_to:       filters.dateTo,
  })

  if (error) throw new Error(error.message)

  return (data as number) ?? 0
}
