// Story 3.6 — send-followup-notifications Edge Function
// Called every minute by pg_cron (migration 0026).
// Sends FCM push notifications at T-24h, T-1h, T=0 before each scheduled follow-up.
// Deduplicates via domain_events (event_type='notification_sent').
//
// Required secrets:
//   supabase secrets set FCM_SERVICE_ACCOUNT='{"type":"service_account",...}'

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';

const TIERS = [
  { key: '24h', windowStart: 23 * 60 + 59.5, windowEnd: 24 * 60 + 0.5, label: 'tomorrow' },
  { key: '1h',  windowStart: 59.5,            windowEnd: 60.5,           label: 'in 1 hour' },
  { key: '0h',  windowStart: -0.5,            windowEnd: 0.5,            label: 'now'       },
] as const;

Deno.serve(async (req) => {
  if (req.method !== 'POST' && req.method !== 'GET') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  let totalSent = 0;

  for (const tier of TIERS) {
    const windowLow  = `now() + interval '${tier.windowStart} minutes'`;
    const windowHigh = `now() + interval '${tier.windowEnd} minutes'`;

    const { data: leads, error } = await supabase
      .from('leads')
      .select('id, assigned_to_user_id, next_followup_at, name_encrypted')
      .not('next_followup_at', 'is', null)
      .not('assigned_to_user_id', 'is', null)
      .not('status', 'in', '("dead","sold")')
      .gte('next_followup_at', new Date(Date.now() + tier.windowStart * 60_000).toISOString())
      .lte('next_followup_at', new Date(Date.now() + tier.windowEnd   * 60_000).toISOString());

    if (error || !leads?.length) continue;

    for (const lead of leads) {
      const followupIso = lead.next_followup_at as string;

      // Dedup: skip if already sent this tier for this follow-up timestamp
      const { count } = await supabase
        .from('domain_events')
        .select('id', { count: 'exact', head: true })
        .eq('event_type', 'notification_sent')
        .contains('payload', {
          lead_id: lead.id,
          followup_at: followupIso,
          tier: tier.key,
        });

      if ((count ?? 0) > 0) continue;

      // Get device tokens for the assigned user
      const { data: tokens } = await supabase
        .from('device_tokens')
        .select('token, tenant_id')
        .eq('user_id', lead.assigned_to_user_id);

      if (!tokens?.length) continue;

      const tenantId = tokens[0].tenant_id as string;
      const title = 'Follow-up reminder';
      const body  = `Your follow-up is due ${tier.label}`;

      let anySent = false;
      for (const { token } of tokens) {
        const ok = await sendFcmNotification({
          token,
          title,
          body,
          data: { lead_id: lead.id, type: 'followup_reminder', tier: tier.key },
        });
        if (ok) anySent = true;
        else {
          // Clean up stale token (404 from FCM)
          await supabase.from('device_tokens').delete()
            .eq('user_id', lead.assigned_to_user_id).eq('token', token);
        }
      }

      if (anySent) {
        // Log dedup record
        await supabase.from('domain_events').insert({
          tenant_id:  tenantId,
          event_type: 'notification_sent',
          payload: {
            lead_id:    lead.id,
            followup_at: followupIso,
            tier:       tier.key,
            title,
            body,
          },
          occurred_at: new Date().toISOString(),
        });
        totalSent++;
      }
    }
  }

  return new Response(JSON.stringify({ sent: totalSent }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
