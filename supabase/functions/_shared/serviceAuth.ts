// Story 8.3 — In-function auth guards for `verify_jwt = false` Edge Functions.
//
// These functions are deployed with `--no-verify-jwt`, so Supabase's gateway does NOT
// authenticate the caller. The function MUST authenticate the caller itself, BEFORE any
// service-role / DB work. This module holds the two non-JWT guards:
//
//   requireServiceRole(req) — caller must present the project service-role key as the
//     bearer token. Used by fns invoked only from a trusted server / service-role context
//     (send-developer-update, send-amendment-notification).
//
//   requireCronSecret(req)  — caller must present the shared CRON_SECRET in the
//     `x-cron-secret` header. Used by the pg_cron-invoked fns
//     (process-overdue-followups, send-followup-notifications, streak-at-risk).
//
// Browser-invoked admin fns (send-assignment-notification, send-bulk-assignment-notification)
// do NOT use these — they carry a real admin *user* JWT, so they authenticate via
// verifyJwtAndScope() (see _shared/auth.ts) + a role === 'admin' check. See story 8.3.
//
// Both comparisons are constant-time to avoid leaking the secret via response timing.

/**
 * Constant-time string comparison. Returns true only when both strings are the same
 * length AND every byte matches. The length check short-circuits (lengths are not
 * secret), but the value comparison never early-returns on the first differing byte,
 * so it does not leak how many leading bytes were correct.
 */
export function safeEq(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

function unauthorized(): Response {
  return new Response(JSON.stringify({ error: 'unauthorized' }), {
    status: 401,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * Guard for service-role-invoked fns. Returns a 401 Response if the request's bearer
 * token does not EXACTLY equal SUPABASE_SERVICE_ROLE_KEY; returns null when authorized.
 * Call as the first line of the handler: `const bad = requireServiceRole(req); if (bad) return bad;`
 */
export function requireServiceRole(req: Request): Response | null {
  const expected = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const header = req.headers.get('Authorization') ?? req.headers.get('authorization') ?? '';
  const token = header.replace(/^Bearer\s+/i, '');
  // Empty expected secret must never authorize (misconfig ⇒ reject everything).
  if (expected.length === 0) return unauthorized();
  return safeEq(token, expected) ? null : unauthorized();
}

/**
 * Guard for pg_cron-invoked fns. Returns a 401 Response if the `x-cron-secret` header
 * does not EXACTLY equal CRON_SECRET; returns null when authorized.
 */
export function requireCronSecret(req: Request): Response | null {
  const expected = Deno.env.get('CRON_SECRET') ?? '';
  const got = req.headers.get('x-cron-secret') ?? '';
  // Empty expected secret must never authorize (misconfig ⇒ reject everything).
  if (expected.length === 0) return unauthorized();
  return safeEq(got, expected) ? null : unauthorized();
}
