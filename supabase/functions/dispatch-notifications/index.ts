// Story 16.4 — dispatch-notifications: the domain_events → FCM drain.
//
// pg_cron posts here every minute (0110 schedule, 0087 x-cron-secret pattern).
// Claims up to 50 undispatched events (claim_domain_events — atomic, SKIP LOCKED,
// ≤1 day old) and routes each:
//   amendment_logged / amendment_status_changed → POST send-amendment-notification
//     (service-role bearer; that fn owns audience + copy + deep-link data)
//   developer_update_posted                     → POST send-developer-update
//   inventory_changed                           → inline FCM to
//     get_inventory_event_audience(unit_id) — internal team + shared partners,
//     route /inventory/<project_id> (kind new_stock|release drives the copy)
//   hold_expiring                               → inline FCM to the holding agent,
//     route /booking (their hold is ~2h from expiry)
// At-most-once: a failed send is logged, never re-queued (no push-spam loops).
// verify_jwt = false; requireCronSecret authenticates the caller in-fn (8.3 rule).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';
import { sendEmail } from '../_shared/email.ts';
import { requireCronSecret } from '../_shared/serviceAuth.ts';

interface DomainEvent {
  id: string;
  tenant_id: string;
  event_type: string;
  payload: Record<string, unknown>;
}

const HANDLED_TYPES = [
  'amendment_logged',
  'amendment_status_changed',
  'developer_update_posted',
  'inventory_changed',
  'hold_expiring',
  'demo_request_created',
];

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });

  const unauth = requireCronSecret(req);
  if (unauth) return unauth;

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const supabase = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  const { data: events, error: claimErr } = await supabase.rpc('claim_domain_events', {
    p_types: HANDLED_TYPES,
    p_limit: 50,
  });
  if (claimErr) return jsonResponse({ error: 'claim_failed', detail: claimErr.message }, 500);
  if (!events?.length) return jsonResponse({ processed: 0 });

  // Fan a user-id list out to every device token; prune dead tokens (fcm.ts pattern).
  async function fanOut(userIds: string[], title: string, body: string, data: Record<string, string>): Promise<number> {
    if (!userIds.length) return 0;
    const { data: tokens } = await supabase
      .from('device_tokens')
      .select('token, user_id')
      .in('user_id', userIds);
    if (!tokens?.length) return 0;
    let sent = 0;
    for (const { token, user_id } of tokens) {
      const ok = await sendFcmNotification({ token, title, body, data });
      if (ok) sent++;
      else await supabase.from('device_tokens').delete().eq('user_id', user_id).eq('token', token);
    }
    return sent;
  }

  // Forward to an existing fan-out fn with the service-role bearer it requires.
  async function forward(fn: string, body: Record<string, unknown>): Promise<boolean> {
    try {
      const res = await fetch(`${supabaseUrl}/functions/v1/${fn}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${serviceKey}` },
        body: JSON.stringify(body),
      });
      return res.ok;
    } catch {
      return false;
    }
  }

  let processed = 0;
  let failed = 0;

  for (const ev of (events as DomainEvent[])) {
    let ok = true;
    try {
      switch (ev.event_type) {
        case 'amendment_logged':
        case 'amendment_status_changed': {
          const amendmentId = ev.payload?.amendment_id as string | undefined;
          if (amendmentId) {
            ok = await forward('send-amendment-notification', {
              amendment_id: amendmentId,
              kind: ev.event_type === 'amendment_logged' ? 'logged' : 'status_changed',
            });
          }
          break;
        }
        case 'developer_update_posted': {
          const updateId = ev.payload?.update_id as string | undefined;
          if (updateId) ok = await forward('send-developer-update', { update_id: updateId });
          break;
        }
        case 'inventory_changed': {
          const unitId = ev.payload?.unit_id as string | undefined;
          const projectId = ev.payload?.project_id as string | undefined;
          const kind = ev.payload?.kind as string | undefined;
          // 0112 noise guard: routine cron-expiry churn is claimed but NEVER
          // pushed — only human-initiated changes (new_stock, force-release
          // 'release') ping the team. Reps who get spammed disable
          // notifications, which kills the valuable follow-up alarms.
          if (kind === 'release_expired') break;
          if (!unitId) break;
          const { data: aud } = await supabase.rpc('get_inventory_event_audience', { p_unit_id: unitId });
          const userIds = (aud ?? []).map((r: { user_id: string }) => r.user_id);
          const title = kind === 'new_stock' ? 'New stock available' : 'Unit back in the pool';
          const body = kind === 'new_stock'
            ? 'A unit was just restocked — check availability.'
            : 'A unit was released and is available again.';
          // Best-effort per token (dead tokens pruned inside fanOut) — an empty
          // audience or 0 delivered is not a dispatch failure.
          await fanOut(userIds, title, body, {
            type: 'inventory',
            kind: kind ?? '',
            unit_id: unitId,
            ...(projectId ? { route: `/inventory/${projectId}` } : { route: '/inventory' }),
          });
          break;
        }
        case 'demo_request_created': {
          // Story 8.5 first consumer: email the founder the moment a prospect
          // submits the marketing demo form. Dormant until RESEND_API_KEY +
          // FOUNDER_NOTIFY_EMAIL are set (sendEmail logs a skip).
          const founderEmail = Deno.env.get('FOUNDER_NOTIFY_EMAIL');
          const requestId = ev.payload?.demo_request_id as string | undefined;
          if (!founderEmail || !requestId) break;
          const { data: reqRow } = await supabase
            .from('demo_requests')
            .select('email, source, created_at')
            .eq('id', requestId)
            .single();
          if (!reqRow) break;
          await sendEmail({
            to: founderEmail,
            subject: 'Nirman CRM — new demo request',
            text: `A prospect just asked for a demo.\n\nContact: ${reqRow.email}\nSource: ${reqRow.source}\nAt: ${reqRow.created_at}\n\nFull list: ops console → demo requests.`,
          });
          break;
        }
        case 'hold_expiring': {
          const agentId = ev.payload?.holding_agent_id as string | undefined;
          const unitId = ev.payload?.unit_id as string | undefined;
          if (!agentId) break;
          await fanOut([agentId], 'Hold expiring soon', 'Your unit hold expires in about 2 hours — confirm the booking or it returns to the pool.', {
            type: 'hold_expiring',
            ...(unitId ? { unit_id: unitId } : {}),
            route: '/booking',
          });
          break;
        }
      }
    } catch (e) {
      ok = false;
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: 'error', event: 'dispatch_failed', domain_event_id: ev.id, type: ev.event_type, error: String(e) }));
    }
    if (ok) processed++;
    else {
      failed++;
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: 'error', event: 'dispatch_forward_failed', domain_event_id: ev.id, type: ev.event_type }));
    }
  }

  return jsonResponse({ processed, failed, claimed: events.length });
});
