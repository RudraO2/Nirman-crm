// Story 1.1 (AC-7) — Edge Function auth + tenant context binding
//
// Every Edge Function follows this contract:
//   1. Read Authorization: Bearer <jwt> header
//   2. Verify JWT via Supabase Auth
//   3. Extract tenant_id + role from app_metadata; validate UUID format
//   4. Open a request-scoped Supabase client with the user's JWT (RLS sees `authenticated`)
//   5. Return { supabase, tenantId, actorId, role } for the function handler
//
// RLS scoping is handled by the JWT-claim branch in the policy via auth_tenant_id():
//   ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid
// No GUC binding needed — PostgREST reads the JWT directly per request.
//
// Reject 401 if JWT missing or invalid; 403 if tenant_id claim is absent or malformed.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { errorResponse, type ApiError } from "./errors.ts";

export type Role = "admin" | "employee";

export interface AuthedContext {
  supabase: SupabaseClient;
  tenantId: string;
  actorId: string;
  role: Role;
}

export interface AuthFailure {
  response: Response;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  throw new Error(
    "Missing SUPABASE_URL or SUPABASE_ANON_KEY in Edge Function environment",
  );
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Verify the request's JWT and return a request-scoped Supabase client.
 * RLS policies scope queries to the caller's tenant via the JWT claim — no GUC binding needed.
 *
 * Usage:
 *   const result = await verifyJwtAndScope(req);
 *   if ("response" in result) return result.response;
 *   const { supabase, tenantId, actorId, role } = result;
 */
export async function verifyJwtAndScope(
  req: Request,
): Promise<AuthedContext | AuthFailure> {
  const authHeader = req.headers.get("authorization") ?? req.headers.get("Authorization");
  if (!authHeader?.toLowerCase().startsWith("bearer ")) {
    return {
      response: errorResponse("unauthorised", "Missing or malformed Authorization header"),
    };
  }
  const jwt = authHeader.slice("bearer ".length).trim();
  if (!jwt) {
    return {
      response: errorResponse("unauthorised", "Empty bearer token"),
    };
  }

  // Request-scoped client carries the user's JWT — PostgREST will see `authenticated`
  const supabase = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userResult, error: userErr } = await supabase.auth.getUser(jwt);
  if (userErr || !userResult?.user) {
    return {
      response: errorResponse("unauthorised", "Invalid or expired token"),
    };
  }

  const meta = (userResult.user.app_metadata ?? {}) as Record<string, unknown>;
  const tenantId = typeof meta.tenant_id === "string" ? meta.tenant_id : null;
  const role = typeof meta.role === "string" ? meta.role : null;

  if (!tenantId) {
    return {
      response: errorResponse(
        "forbidden_role",
        "Tenant claim (app_metadata.tenant_id) missing from JWT",
      ),
    };
  }
  if (!UUID_RE.test(tenantId)) {
    return {
      response: errorResponse(
        "forbidden_role",
        "Tenant claim (app_metadata.tenant_id) is not a valid UUID",
      ),
    };
  }
  if (role !== "admin" && role !== "employee") {
    return {
      response: errorResponse(
        "forbidden_role",
        "Role claim (app_metadata.role) missing or invalid",
      ),
    };
  }

  return {
    supabase,
    tenantId,
    actorId: userResult.user.id,
    role,
  };
}

/**
 * Type guard helper for the union return.
 */
export function isAuthFailure(
  result: AuthedContext | AuthFailure,
): result is AuthFailure {
  return "response" in result;
}

export type { ApiError };
