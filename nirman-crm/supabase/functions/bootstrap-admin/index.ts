// Story 1.2 (AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-7, AC-8)
// Bootstrap the first Admin account for the V1 single-tenant deployment.
//
// Security model: caller must provide Authorization: Bearer <BOOTSTRAP_SECRET>
// (a pre-shared env-var secret, NOT a JWT — no auth user exists yet at bootstrap time).
//
// Creates:
//   1. auth.users entry via Supabase Admin API (email_confirm = true, app_metadata carries tenant_id + role)
//   2. public.users profile row with same UUID + bcrypt hash at cost 12
//
// Idempotent: returns 409 if an admin already exists for the seed tenant.
// Run once only. After running, this endpoint should not be re-exposed.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { errorResponse, successResponse } from "./_shared/errors.ts";

// V1 single-tenant seed UUID — matches supabase/seed.sql
const SEED_TENANT_ID = "00000000-0000-0000-0000-000000000001";

const BootstrapInput = z.object({
  email: z.string().email({ message: "Valid email required" }),
  password: z.string().min(8, { message: "Password must be at least 8 characters" }),
});

/** Password strength: min 8 chars, ≥1 uppercase, ≥1 lowercase, ≥1 digit */
function validatePasswordStrength(password: string): string | null {
  if (password.length < 8) return "Password must be at least 8 characters";
  if (!/[A-Z]/.test(password)) return "Password must contain at least one uppercase letter";
  if (!/[a-z]/.test(password)) return "Password must contain at least one lowercase letter";
  if (!/[0-9]/.test(password)) return "Password must contain at least one number";
  return null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Only accept POST
  if (req.method !== "POST") {
    return errorResponse("validation_error", "Method not allowed — use POST");
  }

  // ── AC-7: Verify BOOTSTRAP_SECRET ──────────────────────────────────────────
  const bootstrapSecret = Deno.env.get("BOOTSTRAP_SECRET");
  if (!bootstrapSecret) {
    // Env var not configured — refuse to run to prevent accidental exposure
    return errorResponse("internal_error", "BOOTSTRAP_SECRET is not configured in Edge Function secrets");
  }

  const authHeader = req.headers.get("authorization") ?? req.headers.get("Authorization") ?? "";
  const provided = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  if (!provided || provided !== bootstrapSecret) {
    return errorResponse("unauthorised", "Invalid or missing bootstrap secret");
  }

  // ── Env vars ───────────────────────────────────────────────────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return errorResponse("internal_error", "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in Edge Function secrets");
  }

  // ── Parse + validate body ──────────────────────────────────────────────────
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Request body must be valid JSON");
  }

  const parsed = BootstrapInput.safeParse(body);
  if (!parsed.success) {
    return errorResponse("validation_error", "Invalid input", parsed.error.flatten().fieldErrors);
  }
  const { email, password } = parsed.data;

  // ── AC-6: Password strength ────────────────────────────────────────────────
  const strengthError = validatePasswordStrength(password);
  if (strengthError) {
    return errorResponse("validation_error", strengthError);
  }

  // ── Service-role Supabase client ───────────────────────────────────────────
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ── AC-5: Idempotency check ────────────────────────────────────────────────
  const { data: existingUsers, error: countErr } = await adminClient
    .from("users")
    .select("id")
    .eq("tenant_id", SEED_TENANT_ID)
    .eq("role", "admin")
    .limit(1);

  if (countErr) {
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "idempotency_check_failed", error: countErr.message }));
    return errorResponse("internal_error", "Failed to check existing admin accounts");
  }

  if (existingUsers && existingUsers.length > 0) {
    return errorResponse("user_already_exists", "An admin account already exists for this tenant");
  }

  // ── AC-2: Create Supabase Auth user ───────────────────────────────────────
  const { data: authData, error: authErr } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: {
      tenant_id: SEED_TENANT_ID,
      role: "admin",
    },
  });

  if (authErr || !authData?.user) {
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "auth_user_creation_failed", error: authErr?.message }));
    return errorResponse("internal_error", `Failed to create auth user: ${authErr?.message ?? "unknown error"}`);
  }

  const authUserId = authData.user.id;

  // ── AC-1: Hash password + create public.users profile ────────────────────
  let bcryptHash: string;
  try {
    // npm:bcryptjs — pure JS, reliable in Deno Edge runtime
    bcryptHash = await bcrypt.hash(password, 12);
  } catch (hashErr) {
    // Roll back auth user before returning error
    await adminClient.auth.admin.deleteUser(authUserId);
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "bcrypt_hash_failed", error: String(hashErr) }));
    return errorResponse("internal_error", "Failed to hash password");
  }

  const { error: profileErr } = await adminClient
    .from("users")
    .insert({
      id: authUserId,           // AC-3: same UUID as auth.users.id
      tenant_id: SEED_TENANT_ID,
      role: "admin",
      email_or_username: email,
      bcrypt_password_hash: bcryptHash,
      must_change_password: false,
      is_active: true,
    });

  if (profileErr) {
    // Roll back auth user to prevent orphaned entries
    await adminClient.auth.admin.deleteUser(authUserId);
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "profile_insert_failed", error: profileErr.message }));
    return errorResponse("internal_error", `Failed to create user profile: ${profileErr.message}`);
  }

  console.log(JSON.stringify({
    ts: new Date().toISOString(),
    level: "info",
    tenant_id: SEED_TENANT_ID,
    event: "bootstrap_admin_created",
    user_id: authUserId,
  }));

  // AC-4: login verified via callers calling supabase.auth.signInWithPassword after this
  return successResponse({ user_id: authUserId, email, role: "admin" }, 201);
});
