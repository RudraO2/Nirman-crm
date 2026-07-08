// Story 12.3 (Epic 12) — stamp app_metadata.role_tier onto existing auth users.
//
// Additive, idempotent ops job. Mirrors the create-employee privileged-stamping pattern:
// admin-gated entry (verifyJwtAndScope), service-role client for auth.admin updates.
// Drives from public.users (tenant-scoped) so an admin only ever stamps their OWN tenant.
// Preserves existing app_metadata (tenant_id + role) — only adds/corrects role_tier.
// Skips users already carrying the correct role_tier claim → safe to run repeatedly.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { CORS_HEADERS, errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") return errorResponse("validation_error", "Use POST");

  const authResult = await verifyJwtAndScope(req);
  if (isAuthFailure(authResult)) return authResult.response;
  const { role, tenantId, actorId } = authResult;

  // builder_head maps to role='admin'; only the tenant admin may stamp their tenant.
  if (role !== "admin") return errorResponse("forbidden_role", "Admin only");

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1. Tenant-scoped target set from public.users (service role bypasses RLS → filter explicitly).
  const { data: users, error: usersErr } = await adminClient
    .from("users")
    .select("id, role_tier")
    .eq("tenant_id", tenantId);
  if (usersErr) {
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "backfill_users_query_failed", tenant_id: tenantId, error: usersErr.message }));
    return errorResponse("internal_error", "Failed to read users");
  }

  let stamped = 0;
  let skipped = 0;
  let errors = 0;

  for (const u of users ?? []) {
    const desiredTier = u.role_tier as string | null;
    if (!desiredTier) { skipped++; continue; } // 0057 backfill should prevent this; guard anyway

    // Fetch current auth metadata to (a) preserve tenant_id/role, (b) skip if already correct.
    const { data: got, error: getErr } = await adminClient.auth.admin.getUserById(u.id);
    if (getErr || !got?.user) {
      errors++;
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "backfill_get_user_failed", user_id: u.id, error: getErr?.message }));
      continue;
    }
    const meta = (got.user.app_metadata ?? {}) as Record<string, unknown>;
    if (meta.role_tier === desiredTier) { skipped++; continue; } // idempotent

    const { error: updErr } = await adminClient.auth.admin.updateUserById(u.id, {
      app_metadata: { ...meta, role_tier: desiredTier }, // spread preserves tenant_id + role
    });
    if (updErr) {
      errors++;
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "backfill_stamp_failed", user_id: u.id, error: updErr.message }));
      continue;
    }
    stamped++;
  }

  console.log(JSON.stringify({
    ts: new Date().toISOString(), level: "info", tenant_id: tenantId, actor_id: actorId,
    event: "role_tier_backfill_complete", stamped, skipped, errors,
  }));

  return successResponse({ stamped, skipped, errors });
});
