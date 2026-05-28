import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { CORS_HEADERS, errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

const UPPER   = "ABCDEFGHIJKLMNPQRSTUVWXYZ"; // 25: no O
const LOWER   = "abcdefghjkmnpqrstuvwxyz";   // 23: no i, l, o
const DIGITS  = "23456789";                  // 8: no 0, 1
const SYMBOLS = "!@#$%^&*";                 // 8
const CHARSET = UPPER + LOWER + DIGITS + SYMBOLS; // 64 (256 % 64 === 0, no bias)

function pickUnbiased(pool: string): string {
  const limit = Math.floor(256 / pool.length) * pool.length;
  for (;;) {
    const [b] = crypto.getRandomValues(new Uint8Array(1));
    if (b < limit) return pool[b % pool.length];
  }
}

function generateSecurePassword(length = 12): string {
  const limit = Math.floor(256 / CHARSET.length) * CHARSET.length;
  // Guarantee ≥1 char from each required class (AC-1)
  const chars = [
    pickUnbiased(UPPER),
    pickUnbiased(LOWER),
    pickUnbiased(DIGITS),
    pickUnbiased(SYMBOLS),
  ];
  // Fill remaining positions from full CHARSET via rejection sampling
  const buf = new Uint8Array(length * 4);
  while (chars.length < length) {
    crypto.getRandomValues(buf);
    for (let i = 0; i < buf.length && chars.length < length; i++) {
      if (buf[i] < limit) chars.push(CHARSET[buf[i] % CHARSET.length]);
    }
  }
  // Fisher-Yates shuffle — rejection-sampling for unbiased index
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

const CreateEmployeeInput = z.object({
  username: z.string().trim().min(3).max(100).regex(/^[\x20-\x7E]+$/, "Username must contain only printable ASCII characters"),
});

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") return errorResponse("validation_error", "Use POST");

  const authResult = await verifyJwtAndScope(req);
  if (isAuthFailure(authResult)) return authResult.response;
  const { actorId, role, tenantId } = authResult;

  if (role !== "admin") return errorResponse("forbidden_role", "Admin only");

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }
  const parsed = CreateEmployeeInput.safeParse(body);
  if (!parsed.success) {
    return errorResponse("validation_error", "Invalid input", parsed.error.flatten().fieldErrors);
  }
  // Supabase auth requires a valid email. Accept either "alice" or "alice@x.com":
  // plain usernames get a synthetic domain so GoTrue accepts the createUser call.
  // Stored as-is in public.users.email_or_username so login lookup matches the input.
  const rawInput = parsed.data.username.trim().toLowerCase();
  const username = rawInput.includes("@")
    ? rawInput
    : `${rawInput}@employees.nirman.local`;

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // NEVER log the plaintext password
  const tempPassword = generateSecurePassword(12);

  const { data: authData, error: authErr } = await adminClient.auth.admin.createUser({
    email: username,
    password: tempPassword,
    email_confirm: true,
    app_metadata: { tenant_id: tenantId, role: "employee" },
  });
  if (authErr || !authData?.user) {
    const msg = authErr?.message?.toLowerCase() ?? "";
    if (
      msg.includes("already registered") ||
      msg.includes("already exists") ||
      msg.includes("email_exists")
    ) {
      return errorResponse("user_already_exists", "An employee with this username already exists");
    }
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "auth_user_creation_failed",
        error: authErr?.message,
      }),
    );
    return errorResponse("internal_error", "Failed to create auth user");
  }
  const authUserId = authData.user.id;

  let bcryptHash: string;
  try {
    bcryptHash = await bcrypt.hash(tempPassword, 12);
  } catch (e) {
    const { error: delErr } = await adminClient.auth.admin.deleteUser(authUserId);
    if (delErr) {
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "auth_user_delete_failed", trigger: "bcrypt_failure", user_id: authUserId, error: delErr.message }));
    }
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "bcrypt_hash_failed",
        error: String(e),
      }),
    );
    return errorResponse("internal_error", "Failed to hash password");
  }

  const { error: profileErr } = await adminClient.from("users").insert({
    id: authUserId,
    tenant_id: tenantId,
    role: "employee",
    email_or_username: username,
    bcrypt_password_hash: bcryptHash,
    must_change_password: true,
    is_active: true,
  });
  if (profileErr) {
    const { error: delErr } = await adminClient.auth.admin.deleteUser(authUserId);
    if (delErr) {
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "auth_user_delete_failed", trigger: "profile_insert_failure", user_id: authUserId, error: delErr.message }));
    }
    if (profileErr.code === "23505") {
      return errorResponse("user_already_exists", "An employee with this username already exists");
    }
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "profile_insert_failed",
        error: profileErr.message,
      }),
    );
    return errorResponse("internal_error", "Failed to create employee profile");
  }

  // Fetch actor name for AC-5 audit payload — fallback to "unknown" on lookup failure
  const { data: actorData } = await adminClient
    .from("users")
    .select("email_or_username")
    .eq("id", actorId)
    .single();

  // AC-5: mandatory — roll back user creation if event insert fails
  const { error: eventErr } = await adminClient.from("user_events").insert({
    tenant_id: tenantId,
    user_id: authUserId,
    actor_id: actorId,
    event_type: "account_created",
    payload: { admin_name: actorData?.email_or_username ?? "unknown" },
  });
  if (eventErr) {
    await adminClient.from("users").delete().eq("id", authUserId);
    const { error: delErr } = await adminClient.auth.admin.deleteUser(authUserId);
    if (delErr) {
      console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "auth_user_delete_failed", trigger: "event_insert_failure", user_id: authUserId, error: delErr.message }));
    }
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "user_event_insert_failed",
        error: eventErr.message,
      }),
    );
    return errorResponse("internal_error", "Failed to record account creation");
  }

  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level: "info",
      tenant_id: tenantId,
      actor_id: actorId,
      event: "employee_created",
      user_id: authUserId,
      // NEVER log username or password here
    }),
  );

  // Plaintext returned ONCE — this is the only place it ever appears
  return successResponse({ user_id: authUserId, temp_password: tempPassword }, 201);
});
