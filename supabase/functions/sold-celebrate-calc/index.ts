// Story 7.2 — sold-celebrate-calc Edge Function.
// Sends the admin "[Employee] just closed [Lead]" push when an employee marks a lead Sold.
// The earned-moment STATS shown on the employee's device come from the
// get_sold_celebration() RPC (client-called) — this function only fans out the admin push.
//
// Auth: employee JWT (verify_jwt). Authorizes the caller owns the sold lead, then uses a
// service-role client to find tenant admins' device tokens and dispatch FCM.
//
// Required secret: FCM_SERVICE_ACCOUNT (already set).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { errorResponse, successResponse } from "../_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "../_shared/auth.ts";
import { sendFcmNotification } from "../_shared/fcm.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return errorResponse("validation_error", "POST only");
  }

  const auth = await verifyJwtAndScope(req);
  if (isAuthFailure(auth)) return auth.response;
  const { actorId, tenantId } = auth;

  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const leadId = typeof body?.lead_id === "string" ? body.lead_id : null;
  const leadNameRaw = typeof body?.lead_name === "string" ? body.lead_name.trim() : "";
  if (!leadId) {
    return errorResponse("validation_error", "lead_id is required");
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // Authorize: caller owns this lead and it is sold.
  const { data: lead } = await admin
    .from("leads")
    .select("id, assigned_to_user_id, status")
    .eq("id", leadId)
    .maybeSingle();

  if (!lead || lead.assigned_to_user_id !== actorId) {
    return errorResponse("not_found", "Lead not found in your queue");
  }
  if (lead.status !== "sold") {
    return errorResponse("validation_error", "Lead is not marked sold");
  }

  // Employee display name for the push body.
  const { data: me } = await admin
    .from("users")
    .select("email_or_username")
    .eq("id", actorId)
    .maybeSingle();
  const employeeName = (me?.email_or_username as string | undefined) ?? "An employee";
  const leadLabel = leadNameRaw.length > 0 ? leadNameRaw : "a lead";

  // Admin device tokens in this tenant.
  const { data: rows } = await admin
    .from("users")
    .select("id, device_tokens(token)")
    .eq("tenant_id", tenantId)
    .eq("role", "admin");

  const tokens: string[] = [];
  for (const u of rows ?? []) {
    const dts = (u as { device_tokens?: { token: string }[] }).device_tokens ?? [];
    for (const dt of dts) if (dt?.token) tokens.push(dt.token);
  }

  let sent = 0;
  for (const token of tokens) {
    const ok = await sendFcmNotification({
      token,
      title: "Lead closed",
      body: `${employeeName} just closed ${leadLabel}`,
      data: { type: "lead_sold", lead_id: leadId },
    });
    if (ok) {
      sent++;
    } else {
      // Best-effort stale-token cleanup.
      await admin.from("device_tokens").delete().eq("token", token);
    }
  }

  return successResponse({ admin_notified: sent });
});
