import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const ChangePasswordInput = z.object({
  currentPassword: z.string().min(1).max(200),
  newPassword: z
    .string()
    .min(8, "New password must be at least 8 characters")
    .max(200)
    .regex(/[A-Z]/, "New password must contain at least one uppercase letter")
    .regex(/[a-z]/, "New password must contain at least one lowercase letter")
    .regex(/[0-9]/, "New password must contain at least one number"),
});

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return errorResponse("validation_error", "Use POST");
  }

  // 1. Verify JWT — both Employee and Admin roles accepted
  const authResult = await verifyJwtAndScope(req);
  if (isAuthFailure(authResult)) return authResult.response;
  const { actorId, tenantId } = authResult;

  // 2. Parse and validate body
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }

  const parsed = ChangePasswordInput.safeParse(body);
  if (!parsed.success) {
    const issues = parsed.error.flatten().fieldErrors;
    const firstMessage =
      (Object.values(issues)[0] as string[] | undefined)?.[0] ?? "Invalid input";
    return errorResponse("validation_error", firstMessage, issues);
  }

  const { currentPassword, newPassword } = parsed.data;

  // 3. Guard: new password must differ from current (prevents forced-change bypass)
  if (newPassword === currentPassword) {
    return errorResponse("validation_error", "New password must differ from current password.");
  }

  // 4. Service-role client for admin operations (bypasses RLS for cross-table writes)
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 5. Fetch current bcrypt hash from public.users
  const { data: userProfile, error: profileErr } = await adminClient
    .from("users")
    .select("id, email_or_username, bcrypt_password_hash, must_change_password")
    .eq("id", actorId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (profileErr || !userProfile) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "change_password_profile_lookup_failed",
      actor_id: actorId, error: profileErr?.message ?? "no profile found",
    }));
    return errorResponse("internal_error", "Could not load user profile");
  }

  // 6. Verify current password — constant-time bcrypt compare
  let currentPasswordValid = false;
  try {
    currentPasswordValid = await bcrypt.compare(
      currentPassword,
      userProfile.bcrypt_password_hash,
    );
  } catch {
    currentPasswordValid = false;
  }

  if (!currentPasswordValid) {
    return errorResponse("validation_error", "Current password is incorrect");
  }

  // 7. Bcrypt new password at cost 12 (NFR-9) — NEVER LOG
  let newHash: string;
  try {
    newHash = await bcrypt.hash(newPassword, 12);
  } catch (e) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "change_password_bcrypt_failed", error: String(e),
    }));
    return errorResponse("internal_error", "Password hashing failed");
  }

  // 8. Update auth.users password — FIRST (Supabase Auth is authoritative for JWT issuance).
  // Only set must_change_password; Supabase merges app_metadata so other keys are preserved.
  const { error: authUpdateErr } = await adminClient.auth.admin.updateUserById(
    actorId,
    {
      password: newPassword,
      app_metadata: { must_change_password: false },
    },
  );

  if (authUpdateErr) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "change_password_auth_update_failed",
      actor_id: actorId, error: authUpdateErr.message,
    }));
    return errorResponse("internal_error", "Failed to update authentication credentials");
  }

  // 9. Update public.users — sync bcrypt hash + clear must_change_password flag
  const { error: profileUpdateErr } = await adminClient
    .from("users")
    .update({ bcrypt_password_hash: newHash, must_change_password: false })
    .eq("id", actorId)
    .eq("tenant_id", tenantId);

  if (profileUpdateErr) {
    // auth.users already updated. Returning 500 here causes an unrecoverable retry loop:
    // client retries with old password → bcrypt fails (hash still old) → loops forever.
    // Log credential_sync_failure and fall through — client gets new session.
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "credential_sync_failure",
      actor_id: actorId,
      detail: "auth.users updated but public.users bcrypt hash update failed",
      error: profileUpdateErr.message,
    }));
  }

  // 10. Log user_events — fire-and-forget (best-effort; don't add latency to bcrypt-heavy path)
  adminClient.from("user_events").insert({
    tenant_id: tenantId,
    user_id: actorId,
    actor_id: actorId,
    event_type: "password_changed",
    payload: { was_forced_change: userProfile.must_change_password },
  }).then(({ error: eventErr }) => {
    if (eventErr) {
      console.error(JSON.stringify({
        ts: new Date().toISOString(), level: "error",
        event: "user_event_insert_failed",
        actor_id: actorId, error: eventErr.message,
      }));
    }
  });

  // 11. Get canonical email from auth.users for re-sign-in.
  const { data: authUserData } = await adminClient.auth.admin.getUserById(actorId);
  const loginEmail = authUserData?.user?.email ?? userProfile.email_or_username;

  // 12. Re-sign in with new password to issue fresh JWT with must_change_password=false
  const anonClient = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: newSession, error: signInErr } = await anonClient.auth.signInWithPassword({
    email: loginEmail,
    password: newPassword,
  });

  if (signInErr || !newSession?.session) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "change_password_re_signin_failed",
      actor_id: actorId, error: signInErr?.message,
    }));
    return errorResponse(
      "internal_error",
      "Password changed but session refresh failed — please log in again",
    );
  }

  console.log(JSON.stringify({
    ts: new Date().toISOString(), level: "info",
    event: "password_changed",
    tenant_id: tenantId,
    actor_id: actorId,
    was_forced_change: userProfile.must_change_password,
    sync_ok: !profileUpdateErr,
    // NEVER log currentPassword or newPassword
  }));

  return successResponse({
    access_token: newSession.session.access_token,
    refresh_token: newSession.session.refresh_token,
    expires_at: newSession.session.expires_at,
  });
});
