// Story 1.6 — Admin deactivates and reactivates Employee accounts
// FR-29: Admin can deactivate (tokens invalidated via auth.admin.signOut) and reactivate.
// AC-1/AC-2: is_active=false + signOut global for immediate token revocation
// AC-4: is_active=true on reactivation
// AC-5/AC-6: user_events logged with actor_id (admin) and user_id (employee)
// AC-7: Admin-only; AC-8: no self-deactivation; AC-9: no admin-targeting
// NEVER log: usernames, passwords, tokens, or PII

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { z } from "npm:zod";
import { CORS_HEADERS, errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ManageEmployeeInput = z.object({
  action: z.enum(["deactivate", "reactivate"]),
  targetUserId: z.string().uuid("targetUserId must be a valid UUID"),
});

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return errorResponse("validation_error", "Use POST");
  }

  // 1. Verify caller JWT — must be admin
  const authResult = await verifyJwtAndScope(req);
  if (isAuthFailure(authResult)) return authResult.response;
  const { actorId, tenantId, role } = authResult;

  if (role !== "admin") {
    return errorResponse("forbidden_role", "Only admins can manage employee accounts");
  }

  // 2. Parse body
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }

  const parsed = ManageEmployeeInput.safeParse(body);
  if (!parsed.success) {
    return errorResponse("validation_error", "Invalid input", parsed.error.flatten().fieldErrors);
  }

  const { action, targetUserId } = parsed.data;

  // 3. AC-8: no self-deactivation
  if (action === "deactivate" && targetUserId === actorId) {
    return errorResponse("validation_error", "Admin cannot deactivate their own account.");
  }

  // 4. Service-role client for privileged DB operations
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 5. Fetch target user — verify belongs to same tenant
  const { data: targetUser, error: lookupErr } = await adminClient
    .from("users")
    .select("id, role, is_active")
    .eq("id", targetUserId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (lookupErr) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "manage_employee_lookup_failed",
      target_user_id: targetUserId, error: lookupErr.message,
    }));
    return errorResponse("internal_error", "Failed to look up employee");
  }
  if (!targetUser) {
    return errorResponse("validation_error", "Employee not found in this organisation");
  }

  // 6. AC-9: cannot target another admin
  if (targetUser.role === "admin") {
    return errorResponse("validation_error", `Only employee accounts can be ${action}d.`);
  }

  // 7. Idempotency: already in desired state
  const newIsActive = action === "reactivate";
  if (targetUser.is_active === newIsActive) {
    return successResponse({ is_active: newIsActive, already: true });
  }

  // 8. Update public.users.is_active
  const { error: updateErr } = await adminClient
    .from("users")
    .update({ is_active: newIsActive })
    .eq("id", targetUserId)
    .eq("tenant_id", tenantId);

  if (updateErr) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "manage_employee_update_failed",
      action, target_user_id: targetUserId, error: updateErr.message,
    }));
    return errorResponse("internal_error", "Failed to update employee status");
  }

  // 9. AC-2: invalidate all sessions immediately (exceeds 60s requirement)
  if (action === "deactivate") {
    const { error: signOutErr } = await adminClient.auth.admin.signOut(
      targetUserId,
      "global",
    );
    if (signOutErr) {
      // Non-fatal: is_active=false already blocks new logins
      console.error(JSON.stringify({
        ts: new Date().toISOString(), level: "error",
        event: "manage_employee_signout_failed",
        target_user_id: targetUserId, error: signOutErr.message,
      }));
    }
  }

  // 10. AC-5/AC-6: append-only user_events — best-effort (non-fatal on failure)
  const eventType = action === "deactivate" ? "account_deactivated" : "account_reactivated";
  adminClient.from("user_events").insert({
    tenant_id: tenantId,
    user_id: targetUserId,
    actor_id: actorId,
    event_type: eventType,
    payload: {},
  }).then(({ error: eventErr }) => {
    if (eventErr) {
      console.error(JSON.stringify({
        ts: new Date().toISOString(), level: "error",
        event: "user_event_insert_failed",
        action, target_user_id: targetUserId, error: eventErr.message,
      }));
    }
  });

  console.log(JSON.stringify({
    ts: new Date().toISOString(), level: "info",
    event: `employee_${action}d`,
    tenant_id: tenantId,
    actor_id: actorId,
    target_user_id: targetUserId,
  }));

  return successResponse({ is_active: newIsActive });
});
