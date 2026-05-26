import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

const CHARSET = "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%^&*";

function generateSecurePassword(length = 12): string {
  const bytes = new Uint8Array(length * 2);
  crypto.getRandomValues(bytes);
  let result = "";
  for (let i = 0; i < bytes.length && result.length < length; i++) {
    const idx = bytes[i] % CHARSET.length;
    if (bytes[i] < Math.floor(256 / CHARSET.length) * CHARSET.length) {
      result += CHARSET[idx];
    }
  }
  while (result.length < length) {
    const extra = new Uint8Array(4);
    crypto.getRandomValues(extra);
    result += CHARSET[extra[0] % CHARSET.length];
  }
  return result;
}

const CreateEmployeeInput = z.object({
  username: z.string().min(3).max(100),
});

Deno.serve(async (req: Request): Promise<Response> => {
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
  const username = parsed.data.username.toLowerCase();

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
    await adminClient.auth.admin.deleteUser(authUserId);
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
    await adminClient.auth.admin.deleteUser(authUserId);
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

  // Best-effort — do not fail the response if event insert fails
  const { error: eventErr } = await adminClient.from("user_events").insert({
    tenant_id: tenantId,
    user_id: authUserId,
    actor_id: actorId,
    event_type: "account_created",
    payload: {},
  });
  if (eventErr) {
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "user_event_insert_failed",
        error: eventErr.message,
      }),
    );
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
