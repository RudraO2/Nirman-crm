// Story 1.6 — Admin deactivates and reactivates Employee accounts
// Story 1.7 — Admin unlocks rate-limited Employee accounts (action: "unlock")
// NEVER log: usernames, passwords, tokens, or PII

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { z } from "npm:zod";
import { errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ManageEmployeeInput = z.object({
  action: z.enum(["deactivate", "reactivate", "unlock"]),
  targetUserId: z.string().uuid("targetUserId must be a valid UUID"),
});

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return errorResponse("validation_error", "Use POST");
  }

  const authResult = await verifyJwtAndScope(req);
  if (isAuthFailure(authResult)) return authResult.response;
  const { actorId, tenantId, role } = authResult;

  if (role !== "admin") {
    return errorResponse("forbidden_role", "Only admins can manage employee accounts");
  }

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

  if (action === "deactivate" && targetUserId === actorId) {
    return errorResponse("validation_error", "Admin cannot deactivate their own account.");
  }

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: targetUser, error: lookupErr } = await adminClient
    .from("users")
    .select("id, role, is_active, locked_until")
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

  // AC-9: Action-aware label (no "unlockd" typo)
  const actionLabel = action === "unlock" ? "unlocked" : `${action}d`;
  if (targetUser.role === "admin") {
    return errorResponse("validation_error", `Only employee accounts can be ${actionLabel}.`);
  }

  // Handle unlock separately (not an is_active change)
  if (action === "unlock") {
    const { error: unlockErr } = await adminClient
      .from("users")
      .update({ locked_until: null })
      .eq("id", targetUserId)
      .eq("tenant_id", tenantId);

    if (unlockErr) {
      console.error(JSON.stringify({
        ts: new Date().toISOString(), level: "error",
        event: "manage_employee_unlock_failed",
        target_user_id: targetUserId, error: unlockErr.message,
      }));
      return errorResponse("internal_error", "Failed to unlock employee account");
    }

    adminClient.from("user_events").insert({
      tenant_id: tenantId,
      user_id: targetUserId,
      actor_id: actorId,
      event_type: "account_unlocked",
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
      event: "employee_unlocked",
      tenant_id: tenantId,
      actor_id: actorId,
      target_user_id: targetUserId,
    }));

    return successResponse({ unlocked: true });
  }

  // Deactivate / Reactivate flow (unchanged from Story 1.6)
  const newIsActive = action === "reactivate";
  if (targetUser.is_active === newIsActive) {
    return successResponse({ is_active: newIsActive, already: true });
  }

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

  if (action === "deactivate") {
    const { error: signOutErr } = await adminClient.auth.admin.signOut(
      targetUserId,
      "global",
    );
    if (signOutErr) {
      console.error(JSON.stringify({
        ts: new Date().toISOString(), level: "error",
        event: "manage_employee_signout_failed",
        target_user_id: targetUserId, error: signOutErr.message,
      }));
    }
  }

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
