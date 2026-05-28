// Story 7.3 — streak-at-risk Edge Function.
// Invoked by pg_cron every 30 min (migration 0032). Sends the 6 PM (tenant-tz)
// "your streak is at risk" push to employees with a >=3-day streak who have not
// acted today. The RPC streak_at_risk_targets() does all the tz/streak/dedup gating;
// this function just dispatches FCM and logs the dedup record.
//
// verify_jwt = false (cron-invoked). Required secret: FCM_SERVICE_ACCOUNT (already set).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendFcmNotification } from "../_shared/fcm.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: targets, error } = await supabase.rpc("streak_at_risk_targets");
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  let sent = 0;
  for (const t of targets ?? []) {
    const row = t as {
      user_id: string;
      tenant_id: string;
      local_date: string;
      streak_days: number;
      token: string;
    };

    const ok = await sendFcmNotification({
      token: row.token,
      title: "Keep your streak alive",
      body: `Your ${row.streak_days}-day streak is at risk. Log a follow-up to keep it going.`,
      data: { type: "streak_at_risk", route: "/home" },
    });

    if (ok) {
      sent++;
      // Dedup record — one per employee per local day.
      await supabase.from("domain_events").insert({
        tenant_id: row.tenant_id,
        event_type: "notification_sent",
        payload: {
          type: "streak_at_risk",
          user_id: row.user_id,
          local_date: row.local_date,
          streak_days: row.streak_days,
        },
        occurred_at: new Date().toISOString(),
      });
    } else {
      await supabase.from("device_tokens").delete().eq("token", row.token);
    }
  }

  return new Response(JSON.stringify({ sent }), {
    headers: { "Content-Type": "application/json" },
  });
});
