// Story 8.3 — negative/positive auth-guard tests (AC-5).
// Run: deno test --allow-env supabase/functions/_shared/serviceAuth.test.ts
//
// Covers one bad-token ⇒ 401 and one correct-token ⇒ pass per guard family:
//   - service-role family (send-developer-update, send-amendment-notification)
//   - cron family (process-overdue-followups, send-followup-notifications, streak-at-risk)
//   - admin-JWT family absent-token ⇒ 401 (verifyJwtAndScope, no-network branch)

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { requireCronSecret, requireServiceRole, safeEq } from './serviceAuth.ts';

const SERVICE_KEY = 'svc-role-key-abc123';
const CRON_SECRET = 'cron-secret-xyz789';

function reqWith(headers: Record<string, string>): Request {
  return new Request('https://x.functions.supabase.co/fn', { method: 'POST', headers });
}

// ── safeEq constant-time compare ──────────────────────────────────────────────
Deno.test('safeEq: equal strings match', () => {
  assertEquals(safeEq('hunter2', 'hunter2'), true);
});
Deno.test('safeEq: different value, same length ⇒ false', () => {
  assertEquals(safeEq('hunter2', 'hunterX'), false);
});
Deno.test('safeEq: different length ⇒ false', () => {
  assertEquals(safeEq('short', 'longer-value'), false);
});

// ── service-role family ───────────────────────────────────────────────────────
Deno.test('requireServiceRole: correct bearer ⇒ pass (null)', () => {
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SERVICE_KEY);
  assertEquals(requireServiceRole(reqWith({ Authorization: `Bearer ${SERVICE_KEY}` })), null);
});
Deno.test('requireServiceRole: wrong bearer ⇒ 401', () => {
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SERVICE_KEY);
  assertEquals(requireServiceRole(reqWith({ Authorization: 'Bearer nope' }))?.status, 401);
});
Deno.test('requireServiceRole: absent bearer ⇒ 401', () => {
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', SERVICE_KEY);
  assertEquals(requireServiceRole(reqWith({}))?.status, 401);
});
Deno.test('requireServiceRole: unset secret ⇒ 401 even if token empty', () => {
  Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY');
  assertEquals(requireServiceRole(reqWith({ Authorization: 'Bearer ' }))?.status, 401);
});

// ── cron family ───────────────────────────────────────────────────────────────
Deno.test('requireCronSecret: correct header ⇒ pass (null)', () => {
  Deno.env.set('CRON_SECRET', CRON_SECRET);
  assertEquals(requireCronSecret(reqWith({ 'x-cron-secret': CRON_SECRET })), null);
});
Deno.test('requireCronSecret: wrong header ⇒ 401', () => {
  Deno.env.set('CRON_SECRET', CRON_SECRET);
  assertEquals(requireCronSecret(reqWith({ 'x-cron-secret': 'nope' }))?.status, 401);
});
Deno.test('requireCronSecret: absent header ⇒ 401', () => {
  Deno.env.set('CRON_SECRET', CRON_SECRET);
  assertEquals(requireCronSecret(reqWith({}))?.status, 401);
});

// ── admin-JWT family: absent token ⇒ 401 (no-network branch of verifyJwtAndScope) ─
Deno.test('verifyJwtAndScope: absent bearer ⇒ 401', async () => {
  // auth.ts throws at import if these are unset — set before the dynamic import.
  Deno.env.set('SUPABASE_URL', 'https://x.supabase.co');
  Deno.env.set('SUPABASE_ANON_KEY', 'anon-key');
  const { verifyJwtAndScope, isAuthFailure } = await import('./auth.ts');
  const result = await verifyJwtAndScope(reqWith({}));
  assertEquals(isAuthFailure(result), true);
  if (isAuthFailure(result)) assertEquals(result.response.status, 401);
});
