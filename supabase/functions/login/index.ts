// Story 1.4 — Platform-segregated login
// FR-30: Employee credentials rejected on web dashboard (HTTP 403). Server-side enforcement.
// NFR-6: JWT tokens expire 24h; refresh tokens valid 30 days.
// NFR-9: Password verified via bcrypt (Supabase Auth holds the authoritative hash).
//
// Security design:
//   1. Service-role lookup of public.users to get role/is_active — before any JWT issuance.
//   2. Bcrypt verify (constant-time) to prevent user-enumeration timing oracle.
//   3. Platform check: role=employee + platform=web → 403 BEFORE Supabase Auth is called.
//   4. Only then call anonClient.auth.signInWithPassword — issues the official JWT.
//
// NEVER log: username, password, access_token, refresh_token, or any substring thereof.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { CORS_HEADERS, errorResponse, successResponse } from "./_shared/errors.ts";

const LoginInput = z.object({
  username: z.string().min(1).max(200),
  password: z.string().min(1).max(200),
  platform: z.enum(["web", "mobile"]),
});

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// Constant-time dummy hash — used when username not found so timing matches a real bcrypt compare.
const DUMMY_HASH = "$2b$12$invalidhashfornonexistentusers0000000000000000000000";

Deno.serve(async (req: Request): Promise<Response> => {
  // CORS preflight — must return 2xx with allow headers before browser sends POST
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return errorResponse("validation_error", "Use POST");
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }

  const parsed = LoginInput.safeParse(body);
  if (!parsed.success) {
    return errorResponse(
      "validation_error",
      "Invalid input",
      parsed.error.flatten().fieldErrors,
    );
  }

  const { username, password, platform } = parsed.data;
  const rawInput = username.toLowerCase().trim();
  // Match the synthetic domain rule used by create-employee so plain usernames work.
  const normalizedUsername = rawInput.includes("@")
    ? rawInput
    : `${rawInput}@employees.nirman.local`;

  // Service-role client — bypasses RLS to look up user by username
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Global lookup — usernames are globally unique across tenants (enforced by
  // auth.users email uniqueness on both creation paths + the 0097 unique index).
  // Exact match: 0097 lowercase-normalized stored values, input is lowercased
  // above, and eq() is immune to the ilike/PostgREST wildcard translation.
  const { data: userProfile, error: profileErr } = await adminClient
    .from("users")
    .select("id, tenant_id, role, is_active, bcrypt_password_hash, must_change_password")
    .eq("email_or_username", normalizedUsername)
    .maybeSingle();

  if (profileErr) {
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "login_profile_lookup_failed",
        error: profileErr.message,
      }),
    );
    return errorResponse("internal_error", "Login unavailable");
  }

  // Always run bcrypt — constant time whether user exists or not (no enumeration timing leak)
  const hashToVerify = userProfile?.bcrypt_password_hash ?? DUMMY_HASH;

  let passwordValid = false;
  try {
    passwordValid = await bcrypt.compare(password, hashToVerify);
  } catch {
    passwordValid = false;
  }

  // Same 401 for "user not found" and "wrong password" — no user enumeration
  if (!userProfile || !passwordValid) {
    return errorResponse("unauthorised", "Invalid username or password");
  }

  // is_active check AFTER bcrypt (prevents timing oracle: active vs inactive accounts)
  if (!userProfile.is_active) {
    return errorResponse("unauthorised", "Account deactivated");
  }

  // Platform segregation — block BEFORE any JWT is issued (FR-30)
  if (userProfile.role === "employee" && platform === "web") {
    console.log(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "info",
        event: "login_platform_rejected",
        tenant_id: userProfile.tenant_id,
        user_id: userProfile.id,
        platform,
        // Do NOT log username or password
      }),
    );
    return errorResponse(
      "unauthorised_platform",
      "This account is not authorised for web access",
    );
  }

  // All checks passed — call Supabase Auth to issue the official JWT + refresh token
  const anonClient = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authData, error: signInErr } =
    await anonClient.auth.signInWithPassword({
      email: normalizedUsername, // auth.users.email was set to username in create-employee
      password,
    });

  if (signInErr || !authData?.session) {
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "login_supabase_auth_failed",
        error: signInErr?.message,
        // Do NOT log username or password
      }),
    );
    return errorResponse("internal_error", "Authentication service error");
  }

  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level: "info",
      event: "login_success",
      tenant_id: userProfile.tenant_id,
      user_id: userProfile.id,
      role: userProfile.role,
      platform,
      // Do NOT log username, password, or tokens
    }),
  );

  return successResponse({
    access_token: authData.session.access_token,
    refresh_token: authData.session.refresh_token,
    expires_at: authData.session.expires_at,
    role: userProfile.role as "admin" | "employee",
    must_change_password: userProfile.must_change_password,
  });
});
