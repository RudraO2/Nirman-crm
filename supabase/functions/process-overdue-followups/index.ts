// Story 3.7 — process-overdue-followups Edge Function
// Called every 5 minutes by pg_cron (migration 0026).
// Finds leads with followup_overdue timeline events that haven't had a push notification sent.
// Sends "Follow-up overdue" push notification to assigned employee.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';
import { requireCronSecret } from '../_shared/serviceAuth.ts';

Deno.serve(async (req) => {
  if (req.method !== 'POST' && req.method !== 'GET') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  // pg_cron caller must present the shared CRON_SECRET (story 8.3).
  const unauth = requireCronSecret(req);
  if (unauth) return unauth;

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // First: run mark_overdue_followups to log timeline events
  await supabase.rpc('mark_overdue_followups');

  // Find recent followup_overdue events (last 6 minutes to match cron interval + buffer)
  const { data: overdueEvents } = await supabase
    .from('lead_timeline')
    .select('lead_id, tenant_id')
    .eq('event_type', 'followup_overdue')
    .gte('occurred_at', new Date(Date.now() - 6 * 60_000).toISOString())
    .is('actor_user_id', null); // system events only

  if (!overdueEvents?.length) {
    return new Response(JSON.stringify({ sent: 0 }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let totalSent = 0;

  for (const event of overdueEvents) {
    const leadId   = event.lead_id  as string;
    const tenantId = event.tenant_id as string;

    // Skip if overdue push already sent for this lead recently
    const { count } = await supabase
      .from('domain_events')
      .select('id', { count: 'exact', head: true })
      .eq('event_type', 'notification_sent')
      .contains('payload', { lead_id: leadId, tier: 'overdue' })
      .gte('occurred_at', new Date(Date.now() - 30 * 60_000).toISOString());

    if ((count ?? 0) > 0) continue;

    const { data: lead } = await supabase
      .from('leads')
      .select('assigned_to_user_id, status')
      .eq('id', leadId)
      .single();

    if (!lead?.assigned_to_user_id || ['dead', 'sold'].includes(lead.status)) continue;

    const { data: tokens } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('user_id', lead.assigned_to_user_id);

    if (!tokens?.length) continue;

    let anySent = false;
    for (const { token } of tokens) {
      const ok = await sendFcmNotification({
        token,
        title: 'Follow-up overdue',
        body:  'A scheduled follow-up is waiting for your action',
        data:  { lead_id: leadId, type: 'followup_overdue' },
      });
      if (ok) anySent = true;
      else {
        await supabase.from('device_tokens').delete()
          .eq('user_id', lead.assigned_to_user_id).eq('token', token);
      }
    }

    if (anySent) {
      await supabase.from('domain_events').insert({
        tenant_id:  tenantId,
        event_type: 'notification_sent',
        payload:    { lead_id: leadId, tier: 'overdue' },
        occurred_at: new Date().toISOString(),
      });
      totalSent++;
    }
  }

  return new Response(JSON.stringify({ sent: totalSent }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
