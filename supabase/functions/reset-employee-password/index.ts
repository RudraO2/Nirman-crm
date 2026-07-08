// Admin resets a user's password (forgot-password recovery).
// FR: Admin can generate a new temporary password for any account in their tenant.
//
// Auth model (mirrors create-employee + login):
//   The password lives in TWO places and BOTH must be updated in lockstep:
//     1. auth.users            — Supabase GoTrue holds the authoritative hash used by
//                                signInWithPassword (see login/index.ts step 4).
//     2. public.users.bcrypt_password_hash — login verifies THIS first (login/index.ts
//                                step 2) before ever calling GoTrue.
//   Updating only one desyncs login. We update both, then force a password change and
//   revoke all existing sessions.
//
// Uniform by design: no role-based target restriction and no per-user special cases.
// Any admin may reset any account in their own tenant (cross-tenant blocked via tenant_id).
//
// NEVER log: usernames, passwords, tokens, or PII.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { CORS_HEADERS, errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// --- Secure temp-password generator (identical policy to create-employee) -------------
const UPPER   = "ABCDEFGHIJKLMNPQRSTUVWXYZ"; // 25: no O
const LOWER   = "abcdefghjkmnpqrstuvwxyz";   // 23: no i, l, o
const DIGITS  = "23456789";                  // 8: no 0, 1
const SYMBOLS = "!@#$%^&*";                  // 8
const CHARSET = UPPER + LOWER + DIGITS + SYMBOLS; // 64 (256 % 64 === 0, no modulo bias)

function pickUnbiased(pool: string): string {
  const limit = Math.floor(256 / pool.length) * pool.length;
  for (;;) {
    const [b] = crypto.getRandomValues(new Uint8Array(1));
    if (b < limit) return pool[b % pool.length];
  }
}

function generateSecurePassword(length = 12): string {
  const limit = Math.floor(256 / CHARSET.length) * CHARSET.length;
  // Guarantee >=1 char from each required class
  const chars = [
    pickUnbiased(UPPER),
    pickUnbiased(LOWER),
    pickUnbiased(DIGITS),
    pickUnbiased(SYMBOLS),
  ];
  const buf = new Uint8Array(length * 4);
  while (chars.length < length) {
    crypto.getRandomValues(buf);
    for (let i = 0; i < buf.length && chars.length < length; i++) {
      if (buf[i] < limit) chars.push(CHARSET[buf[i] % CHARSET.length]);
    }
  }
  // Fisher-Yates shuffle with rejection-sampled index (unbiased)
  for (let i = chars.length - 1; i > 0; i--) {
    const range = i + 1;
    const shuffleLimit = Math.floor(256 / range) * range;
    let r: number;
    do { [r] = crypto.getRandomValues(new Uint8Array(1)); } while (r >= shuffleLimit);
    const j = r % range;
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}
// -------------------------------------------------------------------------------------

const ResetPasswordInput = z.object({
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
    return errorResponse("forbidden_role", "Only admins can reset passwords");
  }

  // 2. Parse body
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }
  const parsed = ResetPasswordInput.safeParse(body);
  if (!parsed.success) {
    return errorResponse("validation_error", "Invalid input", parsed.error.flatten().fieldErrors);
  }
  const { targetUserId } = parsed.data;

  // 3. Service-role client for privileged operations
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 4. Target must exist in the caller's tenant (cross-tenant reset blocked here)
  const { data: targetUser, error: lookupErr } = await adminClient
    .from("users")
    .select("id, is_active")
    .eq("id", targetUserId)
    .eq("tenant_id", tenantId)
    .maybeSingle();

  if (lookupErr) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "reset_password_lookup_failed",
      target_user_id: targetUserId, error: lookupErr.message,
    }));
    return errorResponse("internal_error", "Failed to look up account");
  }
  if (!targetUser) {
    return errorResponse("validation_error", "Account not found in this organisation");
  }

  // 5. Generate + hash the new temp password (never logged)
  const tempPassword = generateSecurePassword(12);
  let bcryptHash: string;
  try {
    bcryptHash = await bcrypt.hash(tempPassword, 12);
  } catch (e) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "reset_password_bcrypt_failed", error: String(e),
    }));
    return errorResponse("internal_error", "Failed to hash password");
  }

  // 6. Update GoTrue (auth.users) — the hash signInWithPassword checks
  const { error: authErr } = await adminClient.auth.admin.updateUserById(targetUserId, {
    password: tempPassword,
  });
  if (authErr) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "reset_password_auth_update_failed",
      target_user_id: targetUserId, error: authErr.message,
    }));
    return errorResponse("internal_error", "Failed to update credentials");
  }

  // 7. Update public.users — the hash login verifies first — and force a change on next login.
  //    If this fails the two stores are momentarily out of sync; a retry regenerates and
  //    re-sets both, self-healing the desync.
  const { error: updateErr } = await adminClient
    .from("users")
    .update({ bcrypt_password_hash: bcryptHash, must_change_password: true })
    .eq("id", targetUserId)
    .eq("tenant_id", tenantId);

  if (updateErr) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "reset_password_profile_update_failed",
      target_user_id: targetUserId, error: updateErr.message,
    }));
    return errorResponse("internal_error", "Failed to persist new password");
  }

  // 8. Revoke every existing session so the old password can no longer be used.
  //    Non-fatal: the new hash already blocks re-login with the old password.
  const { error: signOutErr } = await adminClient.auth.admin.signOut(targetUserId, "global");
  if (signOutErr) {
    console.error(JSON.stringify({
      ts: new Date().toISOString(), level: "error",
      event: "reset_password_signout_failed",
      target_user_id: targetUserId, error: signOutErr.message,
    }));
  }

  // 9. Append-only audit event — best-effort (non-fatal)
  adminClient.from("user_events").insert({
    tenant_id: tenantId,
    user_id: targetUserId,
    actor_id: actorId,
    event_type: "password_reset_by_admin",
    payload: {},
  }).then(({ error: eventErr }) => {
    if (eventErr) {
      console.error(JSON.stringify({
        ts: new Date().toISOString(), level: "error",
        event: "user_event_insert_failed",
        target_user_id: targetUserId, error: eventErr.message,
      }));
    }
  });

  console.log(JSON.stringify({
    ts: new Date().toISOString(), level: "info",
    event: "password_reset_by_admin",
    tenant_id: tenantId,
    actor_id: actorId,
    target_user_id: targetUserId,
    // NEVER log the username or password
  }));

  // Plaintext returned ONCE — the only place it ever appears.
  return successResponse({ temp_password: tempPassword });
});
