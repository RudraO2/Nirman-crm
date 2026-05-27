// Story 1.4 — Platform-segregated login
// Story 1.7 — Rate limiting: 5 fails in 10 min → 15-min lockout (FR-38, Architecture Decision #15)
// FR-30: Employee credentials rejected on web dashboard (HTTP 403). Server-side enforcement.
// NFR-6: JWT tokens expire 24h; refresh tokens valid 30 days.
// NFR-9: Password verified via bcrypt (Supabase Auth holds the authoritative hash).
//
// Security design:
//   1. Service-role lookup of public.users — before any JWT issuance.
//   2. Lockout check: if locked_until > now() → 429 immediately (no bcrypt needed).
//   3. Bcrypt verify (constant-time) to prevent user-enumeration timing oracle.
//   4. On failure: record attempt; if 5+ actual fails in 10 min → set locked_until = now()+15min.
//   5. Platform check: role=employee + platform=web → 403 BEFORE Supabase Auth is called.
//   6. Only then call anonClient.auth.signInWithPassword — issues the official JWT.
//   7. On success: clear locked_until; record success attempt.
//
// NEVER log: username, password, access_token, refresh_token, or any substring thereof.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { errorResponse, successResponse } from "./_shared/errors.ts";

const SEED_TENANT_ID = "00000000-0000-0000-0000-000000000001";

const LoginInput = z.object({
  username: z.string().min(1).max(200),
  password: z.string().min(1).max(200),
  platform: z.enum(["web", "mobile"]),
});

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const DUMMY_HASH = "$2b$12$invalidhashfornonexistentusers0000000000000000000000";

Deno.serve(async (req: Request): Promise<Response> => {
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
  const normalizedUsername = username.toLowerCase().trim();

  // Extract source IP for audit logging
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    ?? req.headers.get("x-real-ip")
    ?? null;

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: userProfile, error: profileErr } = await adminClient
    .from("users")
    .select("id, role, is_active, bcrypt_password_hash, must_change_password, locked_until")
    .eq("tenant_id", SEED_TENANT_ID)
    .ilike("email_or_username", normalizedUsername)
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

  // AC-2: Lockout check — BEFORE bcrypt. Early return for locked accounts.
  // (Attacker triggered lockout themselves; revealing account existence here is acceptable.)
  if (userProfile?.locked_until && new Date(userProfile.locked_until) > new Date()) {
    adminClient.from("auth_failed_attempts").insert({
      tenant_id: SEED_TENANT_ID,
      user_id: userProfile.id,
      ip_address: ip,
      outcome: "locked",
    }).then(({ error }) => {
      if (error) {
        console.error(JSON.stringify({
          ts: new Date().toISOString(), level: "error",
          event: "attempt_record_failed", error: error.message,
        }));
      }
    });
    return errorResponse("account_locked", "Account temporarily locked. Try again later or contact your admin.");
  }

  // AC-6: Always run bcrypt — constant time whether user exists or not (no enumeration timing leak)
  const hashToVerify = userProfile?.bcrypt_password_hash ?? DUMMY_HASH;

  let passwordValid = false;
  try {
    passwordValid = await bcrypt.compare(password, hashToVerify);
  } catch {
    passwordValid = false;
  }

  if (!userProfile || !passwordValid) {
    const outcome = !userProfile ? "unknown_user" : "failed_credentials";

    // AC-3/AC-4: Fire-and-forget — record attempt; maybe trigger lockout for known users
    ;(async () => {
      await adminClient.from("auth_failed_attempts").insert({
        tenant_id: SEED_TENANT_ID,
        user_id: userProfile?.id ?? null,
        ip_address: ip,
        outcome,
      });

      if (userProfile) {
        const tenMinAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString();
        // Count only actual credential failures, not 'locked' or 'success' outcomes.
        // Excluding 'locked' prevents retries-while-locked from inflating the count
        // and causing immediate re-lock after the lockout window expires.
        const { count } = await adminClient
          .from("auth_failed_attempts")
          .select("id", { count: "exact", head: true })
          .eq("user_id", userProfile.id)
          .in("outcome", ["failed_credentials", "unknown_user"])
          .gte("attempted_at", tenMinAgo);

        if ((count ?? 0) >= 5) {
          await adminClient
            .from("users")
            .update({
              locked_until: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
            })
            .eq("id", userProfile.id);

          console.log(JSON.stringify({
            ts: new Date().toISOString(),
            level: "warn",
            event: "account_locked_triggered",
            tenant_id: SEED_TENANT_ID,
            user_id: userProfile.id,
          }));
        }
      }
    })().catch((err) => {
      console.error(JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "attempt_record_failed",
        error: (err as Error)?.message,
      }));
    });

    return errorResponse("unauthorised", "Invalid username or password");
  }

  if (!userProfile.is_active) {
    return errorResponse("unauthorised", "Account deactivated");
  }

  if (userProfile.role === "employee" && platform === "web") {
    console.log(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "info",
        event: "login_platform_rejected",
        tenant_id: SEED_TENANT_ID,
        user_id: userProfile.id,
        platform,
      }),
    );
    return errorResponse(
      "unauthorised_platform",
      "This account is not authorised for web access",
    );
  }

  const anonClient = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: authData, error: signInErr } =
    await anonClient.auth.signInWithPassword({
      email: normalizedUsername,
      password,
    });

  if (signInErr || !authData?.session) {
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "login_supabase_auth_failed",
        error: signInErr?.message,
      }),
    );
    return errorResponse("internal_error", "Authentication service error");
  }

  // AC-5: Success — clear lockout if set; record success (fire-and-forget)
  ;(async () => {
    if (userProfile.locked_until) {
      await adminClient
        .from("users")
        .update({ locked_until: null })
        .eq("id", userProfile.id);
    }
    await adminClient.from("auth_failed_attempts").insert({
      tenant_id: SEED_TENANT_ID,
      user_id: userProfile.id,
      ip_address: ip,
      outcome: "success",
    });
  })().catch((err) => {
    console.error(JSON.stringify({
      ts: new Date().toISOString(),
      level: "error",
      event: "success_cleanup_failed",
      error: (err as Error)?.message,
    }));
  });

  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level: "info",
      event: "login_success",
      tenant_id: SEED_TENANT_ID,
      user_id: userProfile.id,
      role: userProfile.role,
      platform,
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
