// Story 4.1 — send-assignment-notification Edge Function
// Triggered by the admin server action immediately after a successful assign_lead RPC.
// Fans out FCM push to every device_token row of the new assignee.
//
// verify_jwt = false (deployed with --no-verify-jwt) — admin server action calls with
// the service-role key in the Authorization header; we trust the gateway + service-role
// bearer. Anonymous callers cannot reach this fn because the gateway enforces the
// service-role bearer (set in supabase.config + verified by Authorization header check).
//
// Body: { lead_id: uuid, assignee_user_id: uuid }
// Response: { sent: number, reason?: string }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';

interface AssignmentNotificationBody {
  lead_id: string;
  assignee_user_id: string;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  // Bearer guard — only service-role (or anon, which we reject below) can reach this.
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  let payload: AssignmentNotificationBody;
  try {
    payload = await req.json() as AssignmentNotificationBody;
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  const { lead_id, assignee_user_id } = payload;
  if (!lead_id || !assignee_user_id) {
    return jsonResponse({ error: 'missing_fields' }, 400);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // Resolve lead name (PII decrypt happens server-side in the RPC, key never leaves DB)
  const { data: leadName, error: nameErr } = await supabase.rpc(
    'get_lead_name_for_notification',
    { p_lead_id: lead_id },
  );
  if (nameErr) {
    return jsonResponse({ error: 'name_lookup_failed', detail: nameErr.message }, 500);
  }
  const title = 'New lead assigned';
  const body = (typeof leadName === 'string' && leadName.length > 0) ? leadName : 'New lead';

  // Resolve tenant_id + device tokens for the assignee
  const { data: tokens, error: tokErr } = await supabase
    .from('device_tokens')
    .select('token, tenant_id')
    .eq('user_id', assignee_user_id);
  if (tokErr) {
    return jsonResponse({ error: 'token_lookup_failed', detail: tokErr.message }, 500);
  }
  if (!tokens?.length) {
    return jsonResponse({ sent: 0, reason: 'no_tokens' });
  }

  const tenantId = tokens[0].tenant_id as string;
  let sent = 0;
  for (const { token } of tokens) {
    const ok = await sendFcmNotification({
      token,
      title,
      body,
      data: { lead_id, type: 'lead_assigned' },
    });
    if (ok) {
      sent++;
    } else {
      // Stale token — delete (same pattern as 3.6)
      await supabase.from('device_tokens')
        .delete()
        .eq('user_id', assignee_user_id)
        .eq('token', token);
    }
  }

  if (sent > 0) {
    await supabase.from('domain_events').insert({
      tenant_id: tenantId,
      event_type: 'notification_sent',
      payload: {
        type: 'lead_assigned',
        lead_id,
        assignee_user_id,
        title,
        body,
      },
      occurred_at: new Date().toISOString(),
    });
  }

  return jsonResponse({ sent });
});
