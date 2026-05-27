// Story 1.1 (AC-7) — Edge Function auth + tenant context binding (local copy — MCP bundler workaround)
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { errorResponse, type ApiError } from "./errors.ts";

export type Role = "admin" | "employee";
export interface AuthedContext { supabase: SupabaseClient; tenantId: string; actorId: string; role: Role; }
export interface AuthFailure { response: Response; }

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) throw new Error("Missing SUPABASE_URL or SUPABASE_ANON_KEY");

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function verifyJwtAndScope(req: Request): Promise<AuthedContext | AuthFailure> {
  const authHeader = req.headers.get("authorization") ?? req.headers.get("Authorization");
  if (!authHeader?.toLowerCase().startsWith("bearer ")) return { response: errorResponse("unauthorised", "Missing or malformed Authorization header") };
  const jwt = authHeader.slice("bearer ".length).trim();
  if (!jwt) return { response: errorResponse("unauthorised", "Empty bearer token") };

  const supabase = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userResult, error: userErr } = await supabase.auth.getUser(jwt);
  if (userErr || !userResult?.user) return { response: errorResponse("unauthorised", "Invalid or expired token") };

  const meta = (userResult.user.app_metadata ?? {}) as Record<string, unknown>;
  const tenantId = typeof meta.tenant_id === "string" ? meta.tenant_id : null;
  const role = typeof meta.role === "string" ? meta.role : null;

  if (!tenantId) return { response: errorResponse("forbidden_tenant", "Tenant claim missing from JWT") };
  if (!UUID_RE.test(tenantId)) return { response: errorResponse("forbidden_tenant", "Tenant claim is not a valid UUID") };
  if (role !== "admin" && role !== "employee") return { response: errorResponse("forbidden_role", "Role claim missing or invalid") };

  return { supabase, tenantId, actorId: userResult.user.id, role };
}

export function isAuthFailure(result: AuthedContext | AuthFailure): result is AuthFailure {
  return "response" in result;
}

export type { ApiError };
