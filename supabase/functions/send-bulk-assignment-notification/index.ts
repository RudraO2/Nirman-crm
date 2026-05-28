// Story 4.2 — send-bulk-assignment-notification Edge Function
// Called by admin UI after a successful bulk_assign_leads RPC.
// Sends ONE push notification per employee listing the count of new leads assigned.
// Body: { assignments: [{ user_id: string, count: number }] }
// Response: { sent: number }
//
// verify_jwt = false (deployed with --no-verify-jwt) — same pattern as send-assignment-notification.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendFcmNotification } from '../_shared/fcm.ts';

interface EmployeeAssignment {
  user_id: string;
  count: number;
}

interface BulkNotificationBody {
  assignments: EmployeeAssignment[];
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

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) {
    return jsonResponse({ error: 'unauthorized' }, 401);
  }

  let payload: BulkNotificationBody;
  try {
    payload = await req.json() as BulkNotificationBody;
  } catch {
    return jsonResponse({ error: 'invalid_json' }, 400);
  }

  if (!Array.isArray(payload.assignments) || payload.assignments.length === 0) {
    return jsonResponse({ error: 'missing_assignments' }, 400);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  let totalSent = 0;

  for (const { user_id, count } of payload.assignments) {
    if (!user_id || !count) continue;

    const { data: tokens, error: tokErr } = await supabase
      .from('device_tokens')
      .select('token')
      .eq('user_id', user_id);

    if (tokErr || !tokens?.length) continue;

    const title = 'New leads assigned';
    const body = `${count} new ${count === 1 ? 'lead' : 'leads'} assigned to you`;

    for (const { token } of tokens) {
      const ok = await sendFcmNotification({
        token,
        title,
        body,
        data: { type: 'bulk_lead_assigned', count: String(count) },
      });
      if (ok) {
        totalSent++;
      } else {
        await supabase.from('device_tokens')
          .delete()
          .eq('user_id', user_id)
          .eq('token', token);
      }
    }
  }

  return jsonResponse({ sent: totalSent });
});
