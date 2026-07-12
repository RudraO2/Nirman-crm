// Story 16.4 — send-amendment-notification Edge Function
// Triggered by the admin/mobile server action (or a domain_events drain) after an amendment is logged
// or its status changes. Resolves recipients and fans out FCM to their device_tokens.
//   kind 'logged'         → notify every tenant_execution_team member (via get_amendment_log_audience).
//   kind 'status_changed' → notify the originating agent (amendments.logged_by).
// Payload carries only unit/lead/amendment IDs (NO PII). verify_jwt = false (service-role bearer),
// same trust model as send-assignment-notification.
//
// Body: { amendment_id: uuid, kind: 'logged' | 'status_changed' }
// Response: { sent: number, recipients?: number, reason?: string }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';
import { requireServiceRole } from '../_shared/serviceAuth.ts';

interface AmendmentNotificationBody {
  amendment_id: string;
  kind: 'logged' | 'status_changed';
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });

  // Service-role bearer required (invoked from a trusted service-role context, not a browser).
  const unauth = requireServiceRole(req);
  if (unauth) return unauth;

  let payload: AmendmentNotificationBody;
  try {
    payload = await req.json() as AmendmentNotificationBody;
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }
  const { amendment_id, kind } = payload;
  if (!amendment_id || (kind !== 'logged' && kind !== 'status_changed')) {
    return jsonResponse({ error: 'missing_or_invalid_fields' }, 400);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // amendment supplies tenant + status + logged_by; unit_no (not PII) for the title.
  const { data: amd, error: amdErr } = await supabase
    .from('amendments')
    .select('id, tenant_id, status, logged_by, unit_id, lead_id, units(unit_no)')
    .eq('id', amendment_id)
    .single();
  if (amdErr || !amd) return jsonResponse({ error: 'amendment_not_found', detail: amdErr?.message }, 404);

  // Resolve recipient user_ids.
  let userIds: string[] = [];
  if (kind === 'logged') {
    const { data: aud, error: audErr } = await supabase.rpc('get_amendment_log_audience', { p_amendment_id: amendment_id });
    if (audErr) return jsonResponse({ error: 'audience_lookup_failed', detail: audErr.message }, 500);
    userIds = (aud ?? []).map((r: { user_id: string }) => r.user_id);
  } else {
    if (amd.logged_by) userIds = [amd.logged_by as string];
  }
  if (!userIds.length) return jsonResponse({ sent: 0, recipients: 0, reason: 'no_recipients' });

  const unitNo = (amd as { units?: { unit_no?: string } }).units?.unit_no ?? '';
  const title = kind === 'logged' ? 'New amendment logged' : 'Amendment status updated';
  const body = kind === 'logged'
    ? `A modification was requested${unitNo ? ` for unit ${unitNo}` : ''}.`
    : `Unit ${unitNo} amendment is now ${amd.status}.`;

  const { data: tokens, error: tokErr } = await supabase
    .from('device_tokens')
    .select('token, user_id')
    .in('user_id', userIds);
  if (tokErr) return jsonResponse({ error: 'token_lookup_failed', detail: tokErr.message }, 500);
  if (!tokens?.length) return jsonResponse({ sent: 0, recipients: userIds.length, reason: 'no_tokens' });

  let sent = 0;
  for (const { token, user_id } of tokens) {
    // Deep-link (16.4): exec team lands on the amendments surface; the logging
    // agent lands on their lead (their in-app amendment context). No PII.
    const route = kind === 'logged'
      ? '/amendments'
      : (amd.lead_id ? `/lead/${amd.lead_id}` : '/amendments');
    const ok = await sendFcmNotification({
      token, title, body,
      data: { amendment_id, type: 'amendment', kind, route },
    });
    if (ok) sent++;
    else await supabase.from('device_tokens').delete().eq('user_id', user_id).eq('token', token);
  }

  if (sent > 0) {
    await supabase.from('domain_events').insert({
      tenant_id: amd.tenant_id,
      event_type: 'notification_sent',
      payload: { type: 'amendment', kind, amendment_id, recipients: userIds.length, sent },
      occurred_at: new Date().toISOString(),
    });
  }

  return jsonResponse({ sent, recipients: userIds.length });
});
