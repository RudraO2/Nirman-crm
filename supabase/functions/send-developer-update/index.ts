// Story 14.4 — send-developer-update Edge Function
// Triggered by the admin server action immediately after a successful post_developer_update RPC.
// Resolves the update's audience (internal team always; partner_agency users only when the update is
// shareable AND their agency is shared to the project) via get_developer_update_audience(), then fans
// out FCM push to every device_token of those users.
//
// verify_jwt = false (deploy with --no-verify-jwt) — admin server action calls with the service-role
// key in the Authorization header; same trust model as send-assignment-notification.
//
// Body: { update_id: uuid }
// Response: { sent: number, recipients?: number, reason?: string }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';

interface DeveloperUpdateBody {
  update_id: string;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const UPDATE_TYPE_LABEL: Record<string, string> = {
  construction: 'Construction update',
  pricing: 'Pricing update',
  inventory: 'Inventory update',
  announcement: 'Announcement',
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 });
  }

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  let payload: DeveloperUpdateBody;
  try {
    payload = await req.json() as DeveloperUpdateBody;
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  const { update_id } = payload;
  if (!update_id) {
    return jsonResponse({ error: 'missing_fields' }, 400);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  // The update row supplies tenant + title/body.
  const { data: update, error: updErr } = await supabase
    .from('developer_updates')
    .select('id, tenant_id, update_type, body')
    .eq('id', update_id)
    .single();
  if (updErr || !update) {
    return jsonResponse({ error: 'update_not_found', detail: updErr?.message }, 404);
  }

  const title = UPDATE_TYPE_LABEL[update.update_type as string] ?? 'Developer update';
  const body = (typeof update.body === 'string' && update.body.length > 120)
    ? `${update.body.slice(0, 117)}...`
    : (update.body as string);

  // Audience (internal + opted-in partners) → user_ids.
  const { data: audience, error: audErr } = await supabase.rpc(
    'get_developer_update_audience',
    { p_update_id: update_id },
  );
  if (audErr) {
    return jsonResponse({ error: 'audience_lookup_failed', detail: audErr.message }, 500);
  }
  const userIds = (audience ?? []).map((r: { user_id: string }) => r.user_id);
  if (!userIds.length) {
    return jsonResponse({ sent: 0, recipients: 0, reason: 'no_recipients' });
  }

  // Device tokens for the whole audience.
  const { data: tokens, error: tokErr } = await supabase
    .from('device_tokens')
    .select('token, user_id')
    .in('user_id', userIds);
  if (tokErr) {
    return jsonResponse({ error: 'token_lookup_failed', detail: tokErr.message }, 500);
  }
  if (!tokens?.length) {
    return jsonResponse({ sent: 0, recipients: userIds.length, reason: 'no_tokens' });
  }

  let sent = 0;
  for (const { token, user_id } of tokens) {
    const ok = await sendFcmNotification({
      token,
      title,
      body,
      data: { update_id, type: 'developer_update' },
    });
    if (ok) {
      sent++;
    } else {
      // Stale token — delete (same pattern as 3.6 / send-assignment-notification)
      await supabase.from('device_tokens').delete().eq('user_id', user_id).eq('token', token);
    }
  }

  if (sent > 0) {
    await supabase.from('domain_events').insert({
      tenant_id: update.tenant_id,
      event_type: 'notification_sent',
      payload: { type: 'developer_update', update_id, title, recipients: userIds.length, sent },
      occurred_at: new Date().toISOString(),
    });
  }

  return jsonResponse({ sent, recipients: userIds.length });
});
