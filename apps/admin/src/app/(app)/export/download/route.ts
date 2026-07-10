import ExcelJS from 'exceljs'
import { createClient } from '@/lib/supabase/server'

type ExportRow = {
  lead_name:         string | null
  phone:             string | null
  status:            string | null
  source:            string | null
  property_type:     string | null
  location:          string | null
  budget_min:        number | null
  budget_max:        number | null
  ticket_size:       string | null
  remarks:           string | null
  interest_type:     string | null
  is_incomplete:     boolean | null
  visit_date:        string | null
  next_followup_at:  string | null
  created_at:        string | null
  assigned_employee: string | null
  timeline_summary:  string | null
}

const COLS = [
  'Name', 'Phone', 'Status', 'Source', 'Property Type', 'Location',
  'Budget Min', 'Budget Max', 'Ticket Size', 'Remarks', 'Interest Type',
  'Is Incomplete', 'Visit Date', 'Next Followup At', 'Created At',
  'Assigned Employee', 'Last 3 Timeline Events',
]

function pad(n: number): string {
  return String(n).padStart(2, '0')
}

export async function GET(request: Request) {
  const supabase = await createClient()
  const { data: { user }, error: authError } = await supabase.auth.getUser()

  if (authError || !user) {
    return new Response('Unauthorized', { status: 401 })
  }

  if (user.app_metadata?.role !== 'admin') {
    return new Response('Forbidden', { status: 403 })
  }

  const { data: userRow } = await supabase
    .from('users')
    .select('email_or_username')
    .eq('id', user.id)
    .single()

  const adminUsername = userRow?.email_or_username ?? user.email ?? 'admin'

  const tenantId = user.app_metadata?.tenant_id as string | undefined
  const { data: tenantRow } = tenantId
    ? await supabase.from('tenants').select('timezone').eq('id', tenantId).single()
    : { data: null }

  const tz = (tenantRow as { timezone?: string } | null)?.timezone ?? 'Asia/Kolkata'

  const now = new Date()
  const fileName = [
    'crm-export',
    `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`,
    `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`,
  ].join('-') + '.xlsx'

  const url = new URL(request.url)
  const p = url.searchParams
  const status        = p.get('status')       || null
  const employeeId    = p.get('employeeId')   || null
  const projectId     = p.get('projectId')    || null
  const propertyType  = p.get('propertyType') || null
  const dateFrom      = p.get('dateFrom')     || null
  const dateTo        = p.get('dateTo')       || null

  const { data: rows, error: rpcError } = await supabase.rpc('export_leads_data', {
    p_file_name:     fileName,
    p_status:        status,
    p_employee_id:   employeeId,
    p_project_id:    projectId,
    p_property_type: propertyType,
    p_date_from:     dateFrom,
    p_date_to:       dateTo,
  })

  if (rpcError) {
    return new Response(rpcError.message, { status: 500 })
  }

  const ts = now.toLocaleString('sv', { timeZone: tz }).replace('T', ' ')
  const watermark = `Exported by ${adminUsername} on ${ts} ${tz}`

  const dataRows: unknown[][] = (rows as ExportRow[]).map((r) => [
    r.lead_name,        r.phone,            r.status,
    r.source,           r.property_type,    r.location,
    r.budget_min,       r.budget_max,       r.ticket_size,
    r.remarks,          r.interest_type,    r.is_incomplete,
    r.visit_date,       r.next_followup_at, r.created_at,
    r.assigned_employee, r.timeline_summary,
  ])

  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Leads')
  ws.addRow([watermark])                          // row 1: watermark banner
  ws.mergeCells(1, 1, 1, COLS.length)             // merge A1:Q1
  ws.addRow(COLS)                                 // row 2: column headers
  ws.addRows(dataRows)                            // rows 3+: data

  const arrayBuffer = await wb.xlsx.writeBuffer()
  const blob = new Blob([new Uint8Array(arrayBuffer as ArrayBuffer)], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })

  return new Response(blob, {
    headers: {
      'Content-Disposition': `attachment; filename="${fileName}"`,
    },
  })
}
