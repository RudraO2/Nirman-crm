// Story 8.4 — accept a team-invite link and create the employee account.
//
// verify_jwt=false BY DESIGN: the invitee has no session yet. Per the standing
// 8.3 rule every no-verify-jwt fn must authenticate its caller in-fn — here the
// single-use invitation token IS the credential (256-bit random, only its
// sha256 stored, claimed atomically so two accepts of one token cannot race).
//
// Flow: claim invitation (atomic UPDATE) → tenant must be trial/active →
// dual-store user create (auth.users via admin API + public.users bcrypt, same
// as create-employee) with the invitee's OWN password (must_change_password
// false) → user_events account_created {via:'invite'} → stamp accepted_user_id.
// Any failure after the claim un-claims the invitation so the link stays usable.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { CORS_HEADERS, errorResponse, successResponse } from "./_shared/errors.ts";

const AcceptInviteInput = z.object({
  token: z.string().regex(/^[0-9a-f]{64}$/, "Malformed invite token"),
  username: z.string().trim().min(3).max(100).regex(/^[\x20-\x7E]+$/, "Username must contain only printable ASCII characters"),
  password: z.string().min(8).max(72),
  full_name: z.string().trim().max(120).optional(),
});

async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") return errorResponse("validation_error", "Use POST");

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }
  const parsed = AcceptInviteInput.safeParse(body);
  if (!parsed.success) {
    return errorResponse("validation_error", "Invalid input", parsed.error.flatten().fieldErrors);
  }

  const rawInput = parsed.data.username.trim().toLowerCase();
  const username = rawInput.includes("@") ? rawInput : `${rawInput}@employees.nirman.local`;

  const adminClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  // 1. Claim the invitation atomically — the token is the caller's credential.
  const tokenHash = await sha256Hex(parsed.data.token);
  const { data: claimed, error: claimErr } = await adminClient
    .from("invitations")
    .update({ accepted_at: new Date().toISOString() })
    .eq("token_hash", tokenHash)
    .is("accepted_at", null)
    .is("revoked_at", null)
    .gt("expires_at", new Date().toISOString())
    .select("id, tenant_id, invited_role")
    .maybeSingle();
  if (claimErr) {
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "invite_claim_failed", error: claimErr.message }));
    return errorResponse("internal_error", "Could not process the invite");
  }
  if (!claimed) {
    return errorResponse("unauthorised", "This invite link is invalid, expired, revoked, or already used");
  }
  const inviteId = claimed.id as string;
  const tenantId = claimed.tenant_id as string;
  // 0113: the role was fixed at mint time by an existing admin of the tenant.
  const role = (claimed.invited_role as string | undefined) === "admin" ? "admin" : "employee";

  const unclaim = async () => {
    const { error } = await adminClient
      .from("invitations")
      .update({ accepted_at: null, accepted_user_id: null })
      .eq("id", inviteId);
    if (error) {
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "invite_unclaim_failed", invite_id: inviteId, error: error.message }));
    }
  };

  // 2. The tenant must still be allowed in (0056 lifecycle gate).
  const { data: tenant } = await adminClient
    .from("tenants")
    .select("status")
    .eq("id", tenantId)
    .single();
  if (!tenant || !["trial", "active"].includes(tenant.status as string)) {
    await unclaim();
    return errorResponse("forbidden_tenant", "This workspace is not accepting new members right now");
  }

  // 3. Dual-store account creation (create-employee pattern, invitee's own password).
  const { data: authData, error: authErr } = await adminClient.auth.admin.createUser({
    email: username,
    password: parsed.data.password,
    email_confirm: true,
    app_metadata: { tenant_id: tenantId, role },
    ...(parsed.data.full_name ? { user_metadata: { full_name: parsed.data.full_name } } : {}),
  });
  if (authErr || !authData?.user) {
    await unclaim();
    const msg = authErr?.message?.toLowerCase() ?? "";
    if (msg.includes("already registered") || msg.includes("already exists") || msg.includes("email_exists")) {
      return errorResponse("user_already_exists", "That username is already taken — pick another");
    }
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "auth_user_creation_failed", error: authErr?.message }));
    return errorResponse("internal_error", "Failed to create the account");
  }
  const authUserId = authData.user.id;

  const rollbackUser = async () => {
    await adminClient.from("users").delete().eq("id", authUserId);
    const { error: delErr } = await adminClient.auth.admin.deleteUser(authUserId);
    if (delErr) {
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "auth_user_delete_failed", user_id: authUserId, error: delErr.message }));
    }
  };

  let bcryptHash: string;
  try {
    bcryptHash = await bcrypt.hash(parsed.data.password, 12);
  } catch (e) {
    await rollbackUser();
    await unclaim();
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "bcrypt_hash_failed", error: String(e) }));
    return errorResponse("internal_error", "Failed to secure the password");
  }

  const { error: profileErr } = await adminClient.from("users").insert({
    id: authUserId,
    tenant_id: tenantId,
    role,
    email_or_username: username,
    bcrypt_password_hash: bcryptHash,
    must_change_password: false, // they just chose this password themselves
    is_active: true,
  });
  if (profileErr) {
    await rollbackUser();
    await unclaim();
    if (profileErr.code === "23505") {
      return errorResponse("user_already_exists", "That username is already taken — pick another");
    }
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "profile_insert_failed", error: profileErr.message }));
    return errorResponse("internal_error", "Failed to create the account");
  }

  const { error: eventErr } = await adminClient.from("user_events").insert({
    tenant_id: tenantId,
    user_id: authUserId,
    actor_id: authUserId,
    event_type: "account_created",
    payload: { via: "invite", invite_id: inviteId },
  });
  if (eventErr) {
    await rollbackUser();
    await unclaim();
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "user_event_insert_failed", error: eventErr.message }));
    return errorResponse("internal_error", "Failed to record the account");
  }

  // 4. Stamp who accepted (best-effort — the claim already burned the link).
  const { error: stampErr } = await adminClient
    .from("invitations")
    .update({ accepted_user_id: authUserId })
    .eq("id", inviteId);
  if (stampErr) {
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "invite_stamp_failed", invite_id: inviteId, error: stampErr.message }));
  }

  console.log(JSON.stringify({
    ts: new Date().toISOString(), level: "info", event: "invite_accepted",
    tenant_id: tenantId, user_id: authUserId, invite_id: inviteId,
    // NEVER log username or password
  }));

  return successResponse({ user_id: authUserId, username, role }, 201);
});
