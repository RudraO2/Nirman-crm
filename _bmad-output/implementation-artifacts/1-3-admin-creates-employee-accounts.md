---
story_key: 1-3-admin-creates-employee-accounts
epic: 1
story: 3
story_id: 1.3
---

# Story 1.3: Admin creates Employee accounts with one-time password modal

Status: ready-for-dev

## Story

As an Admin,
I want to create Employee accounts and see the generated password once in a modal,
So that I can convey the password out-of-band without it being persisted in the UI.

## Acceptance Criteria

1. **AC-1 — Employee user created in both tables.** Given Admin submits new employee form with a username/email, then `public.users` row exists with `role = employee`, `must_change_password = true`, `is_active = true`, `bcrypt_password_hash` at cost 12; AND `auth.users` entry exists with matching UUID and `app_metadata = {tenant_id, role: "employee"}`.
2. **AC-2 — One-time password modal.** The plaintext 12-char password (mixed case + digits + symbols) is displayed exactly once in a modal labelled "Convey to employee out of band. This will not be shown again."
3. **AC-3 — Modal dismissal removes plaintext.** Dismissing the modal removes the plaintext from UI state. Reopening the employee's profile row does NOT show the password. Refreshing the page does NOT reveal it.
4. **AC-4 — Password stored as bcrypt hash only.** The plaintext is never written to the database, never logged server-side (not even partially), and not present in any response body after the initial creation response.
5. **AC-5 — Timeline records account_created.** `user_events` table records `account_created` event with `actor_id` (admin UUID), `user_id` (new employee UUID), `payload: { admin_name: string }`, `occurred_at`.
6. **AC-6 — Admin-only endpoint.** `create-employee` Edge Function rejects non-admin JWT with HTTP 403. Rejects missing JWT with HTTP 401.
7. **AC-7 — Duplicate username/email rejected.** Attempting to create an employee with an already-registered `email_or_username` (case-insensitive, within the same tenant) returns HTTP 409 `user_already_exists`.

## Tasks / Subtasks

- [ ] **T-1 — Bootstrap Next.js admin web app**
  - [ ] T-1.1 Run `create-next-app` scaffold in `apps/admin/` (see exact command in Dev Notes)
  - [ ] T-1.2 Install shadcn/ui via `npx shadcn@latest init -t next -b radix`
  - [ ] T-1.3 Add Supabase SSR package: `npm install @supabase/ssr @supabase/supabase-js`
  - [ ] T-1.4 Create `src/lib/supabase/client.ts` (browser client)
  - [ ] T-1.5 Create `src/lib/supabase/server.ts` (server component client)
  - [ ] T-1.6 Create `src/middleware.ts` (session refresh + admin-only guard)
  - [ ] T-1.7 Create `apps/admin/.env.local` with `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (see Dev Notes)
  - [ ] T-1.8 Create root layout `src/app/layout.tsx` with QueryClientProvider + AuthProvider shells
  - [ ] T-1.9 Create login page scaffold `src/app/(auth)/login/page.tsx` (placeholder — Story 1.4 implements full login; just needs "Login coming in Story 1.4" text for now so routing works)

- [ ] **T-2 — Migration: create user_events table**
  - [ ] T-2.1 Create `supabase/migrations/0004_create_user_events.sql` with `user_event_type` enum and `user_events` table (see full SQL in Dev Notes)
  - [ ] T-2.2 Apply migration via `mcp__supabase__apply_migration` to project `vhgruadourflpxuzuxfn`
  - [ ] T-2.3 Verify table exists via `mcp__supabase__execute_sql`: `SELECT table_name FROM information_schema.tables WHERE table_name = 'user_events'`
  - [ ] T-2.4 Regenerate TypeScript types via `mcp__supabase__generate_typescript_types` → overwrite `packages/shared-types/index.ts`

- [ ] **T-3 — Edge Function: create-employee**
  - [ ] T-3.1 Create `supabase/functions/create-employee/_shared/errors.ts` (local copy — MCP bundler workaround; must match canonical `functions/_shared/errors.ts`)
  - [ ] T-3.2 Create `supabase/functions/create-employee/_shared/auth.ts` (local copy — same workaround)
  - [ ] T-3.3 Create `supabase/functions/create-employee/index.ts` (see full implementation pattern in Dev Notes)
  - [ ] T-3.4 Deploy via `mcp__supabase__deploy_edge_function` (name: `create-employee`, project: `vhgruadourflpxuzuxfn`)
  - [ ] T-3.5 Verify deploy: invoke function with admin JWT + valid body → expect 201 `{ data: { user_id, temp_password } }`
  - [ ] T-3.6 Verify AC-6: invoke with no auth header → expect 401; invoke with employee JWT → expect 403
  - [ ] T-3.7 Verify AC-7: invoke again with same username → expect 409 `user_already_exists`
  - [ ] T-3.8 Verify AC-5: `SELECT * FROM user_events WHERE event_type = 'account_created'` via execute_sql

- [ ] **T-4 — Admin team page (server component + form)**
  - [ ] T-4.1 Add shadcn components: `npx shadcn@latest add button input label card dialog table`
  - [ ] T-4.2 Create `src/app/(app)/layout.tsx` (authed shell — redirect to login if no session, redirect if non-admin)
  - [ ] T-4.3 Create `src/app/(app)/team/page.tsx` (server component — fetch employee list; see Dev Notes)
  - [ ] T-4.4 Create `src/components/auth/new-employee-form.tsx` (client component — "use client"; form + mutation + modal trigger)
  - [ ] T-4.5 Create `src/components/auth/generated-password-modal.tsx` (client component — Dialog that clears password on close; see Dev Notes)
  - [ ] T-4.6 Verify: `npm run dev` from `apps/admin/`; navigate to `/team`; create an employee; modal shows password; close modal; reload — password not visible

- [ ] **T-5 — Create create-employee/README.md**
  - [ ] T-5.1 Document: purpose, request body, required auth (admin JWT), response, error codes, plaintext-once guarantee

- [ ] **T-6 — Commit + push + PR**
  - [ ] T-6.1 Create branch `feat/1.3-create-employee` from `main`
  - [ ] T-6.2 Push all files via GitHub MCP
  - [ ] T-6.3 Open PR against `main`
  - [ ] T-6.4 Update sprint-status.yaml: `1-3-admin-creates-employee-accounts: review`

## Dev Notes

### Critical Context: Admin Web App Does Not Exist Yet

`apps/admin/` directory is **empty**. Story 1.3 is the first story that creates the admin web app. T-1 must complete before T-4 is possible. Use the exact scaffold command from architecture.md:

```bash
# Run from monorepo root (nirman-crm/)
cd apps
npx create-next-app@latest admin \
  --typescript \
  --tailwind \
  --app \
  --src-dir \
  --import-alias "@/*" \
  --turbopack \
  --use-npm \
  --skip-install
cd admin && npm install
npx shadcn@latest init -t next -b radix
```

This provides: Next.js 16.2 App Router, TypeScript strict, Tailwind v4, shadcn Radix base. Do NOT alter these flags — they match the architecture decision.

### Database Migration (T-2): user_events

Create `supabase/migrations/0004_create_user_events.sql`:

```sql
-- Story 1.3 — User account lifecycle event log
-- Satisfies AC-5 (account_created), extended by Stories 1.5 (password_changed) and 1.6 (deactivated/reactivated)
-- Append-only: no UPDATE/DELETE grants.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_event_type') THEN
    CREATE TYPE public.user_event_type AS ENUM (
      'account_created',
      'account_deactivated',
      'account_reactivated',
      'password_changed',
      'password_reset_by_admin'
    );
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.user_events (
  id           uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  user_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  actor_id     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  event_type   public.user_event_type NOT NULL,
  payload      jsonb NOT NULL DEFAULT '{}',
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_events IS
  'Story 1.3 — Append-only user account lifecycle events. Never UPDATE or DELETE rows.';

CREATE INDEX IF NOT EXISTS user_events_tenant_id_idx  ON public.user_events (tenant_id);
CREATE INDEX IF NOT EXISTS user_events_user_id_idx    ON public.user_events (user_id);
CREATE INDEX IF NOT EXISTS user_events_occurred_at_idx ON public.user_events (occurred_at DESC);

ALTER TABLE public.user_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_events FORCE  ROW LEVEL SECURITY;

-- JWT-claim-based policy (matches 0003_cr_patch pattern already in migrations)
CREATE POLICY user_events_tenant_isolation ON public.user_events
  FOR ALL
  TO authenticated
  USING      (tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid)
  WITH CHECK (tenant_id = ((auth.jwt() -> 'app_metadata') ->> 'tenant_id')::uuid);

-- READ + INSERT for authenticated; NO UPDATE, NO DELETE — append-only
GRANT SELECT, INSERT ON public.user_events TO authenticated;
-- service_role bypasses RLS and has full access implicitly; no explicit grant needed
```

### Edge Function Pattern (T-3): create-employee

**Two-client pattern** — this function needs BOTH:
1. A **JWT-scoped client** (caller's token) to verify identity and role
2. A **service-role client** to call `auth.admin.createUser()` and insert `public.users`

The `verifyJwtAndScope()` from `_shared/auth.ts` returns the JWT client + decoded claims. The service-role client is constructed separately.

**MCP bundler workaround** — copy `_shared/` files locally (same fix as Story 1.2):
- `create-employee/_shared/errors.ts` — exact copy of `functions/_shared/errors.ts`
- `create-employee/_shared/auth.ts` — exact copy of `functions/_shared/auth.ts`
- Import as `./_shared/errors.ts` and `./_shared/auth.ts` (not `../`)

**Password generation** — use `crypto.getRandomValues()` (Deno native, CSPRNG):

```typescript
const CHARSET = 'ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%^&*';
function generateSecurePassword(length = 12): string {
  const bytes = new Uint8Array(length * 2);
  crypto.getRandomValues(bytes);
  let result = '';
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
```

Note: charset excludes visually ambiguous chars (`O`, `0`, `l`, `I`, `1`) to reduce transcription errors when admin reads to employee.

**CRITICAL: Never log the plaintext password** — not even partially. Check: no `console.log`, no `console.error` that includes `password`, `tempPassword`, or any generated string.

**Full Edge Function structure** (`create-employee/index.ts`):

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "npm:bcryptjs";
import { z } from "npm:zod";
import { errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

const CHARSET = 'ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%^&*';

function generateSecurePassword(length = 12): string { /* ... above ... */ }

const CreateEmployeeInput = z.object({
  username: z.string().min(3).max(100),
});

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return errorResponse("validation_error", "Use POST");

  // 1. Verify JWT — get caller identity
  const authResult = await verifyJwtAndScope(req);
  if (isAuthFailure(authResult)) return authResult.response;
  const { actorId, role, tenantId } = authResult;

  // 2. Admin-only guard
  if (role !== "admin") return errorResponse("forbidden_role", "Admin only");

  // 3. Parse body
  let body: unknown;
  try { body = await req.json(); } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }
  const parsed = CreateEmployeeInput.safeParse(body);
  if (!parsed.success) return errorResponse("validation_error", "Invalid input", parsed.error.flatten().fieldErrors);
  const username = parsed.data.username.toLowerCase();

  // 4. Service-role client for admin operations
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 5. Generate password — NEVER LOG
  const tempPassword = generateSecurePassword(12);

  // 6. Create auth.users entry
  const { data: authData, error: authErr } = await adminClient.auth.admin.createUser({
    email: username,
    password: tempPassword,
    email_confirm: true,
    app_metadata: { tenant_id: tenantId, role: "employee" },
  });
  if (authErr || !authData?.user) {
    const msg = authErr?.message?.toLowerCase() ?? "";
    if (msg.includes("already registered") || msg.includes("already exists") || msg.includes("email_exists")) {
      return errorResponse("user_already_exists", "An employee with this username already exists");
    }
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "auth_user_creation_failed", error: authErr?.message }));
    return errorResponse("internal_error", "Failed to create auth user");
  }
  const authUserId = authData.user.id;

  // 7. Bcrypt hash — NEVER return hash to client
  let bcryptHash: string;
  try {
    bcryptHash = await bcrypt.hash(tempPassword, 12);
  } catch (e) {
    await adminClient.auth.admin.deleteUser(authUserId);
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "bcrypt_hash_failed", error: String(e) }));
    return errorResponse("internal_error", "Failed to hash password");
  }

  // 8. Insert public.users
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
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "profile_insert_failed", error: profileErr.message }));
    return errorResponse("internal_error", "Failed to create employee profile");
  }

  // 9. Log account_created to user_events (best-effort)
  const { error: eventErr } = await adminClient.from("user_events").insert({
    tenant_id: tenantId,
    user_id: authUserId,
    actor_id: actorId,
    event_type: "account_created",
    payload: {},
  });
  if (eventErr) {
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "user_event_insert_failed", error: eventErr.message }));
  }

  console.log(JSON.stringify({
    ts: new Date().toISOString(), level: "info",
    tenant_id: tenantId, actor_id: actorId,
    event: "employee_created", user_id: authUserId,
  }));

  // 10. Return plaintext password ONCE
  return successResponse({ user_id: authUserId, temp_password: tempPassword }, 201);
});
```

### Supabase Client Setup (T-1.4–T-1.6)

**`apps/admin/src/lib/supabase/client.ts`** (browser client):
```typescript
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!
  )
}
```

**`apps/admin/src/lib/supabase/server.ts`** (server components):
```typescript
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createClient() {
  const cookieStore = await cookies()
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() { return cookieStore.getAll() },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options))
          } catch { /* called from Server Component — ignore */ }
        },
      },
    }
  )
}
```

**`apps/admin/src/middleware.ts`**:
```typescript
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() { return request.cookies.getAll() },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) => supabaseResponse.cookies.set(name, value, options))
        },
      },
    }
  )

  const { data: { user } } = await supabase.auth.getUser()

  const isAuthRoute = request.nextUrl.pathname.startsWith('/login') ||
    request.nextUrl.pathname.startsWith('/auth')

  if (!user && !isAuthRoute) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    return NextResponse.redirect(url)
  }

  return supabaseResponse
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
}
```

**`apps/admin/.env.local`** (gitignored — never commit):
```
NEXT_PUBLIC_SUPABASE_URL=https://vhgruadourflpxuzuxfn.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<anon/publishable key from Supabase Dashboard>
```

Get the publishable key from Supabase Dashboard → Project Settings → API → `anon public` key.

Also add to root `.env.example`:
```
# Admin web app (Next.js)
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=
```

### Admin Team Page (T-4.3–T-4.5)

**Pattern: server component fetches list; client component owns form + modal state**

**`src/app/(app)/team/page.tsx`** (Server Component):
```tsx
import { createClient } from '@/lib/supabase/server'
import { NewEmployeeForm } from '@/components/auth/new-employee-form'

export default async function TeamPage() {
  const supabase = await createClient()
  const { data: employees } = await supabase
    .from('users')
    .select('id, email_or_username, is_active, created_at')
    .eq('role', 'employee')
    .order('created_at', { ascending: false })

  return (
    <div className="p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-semibold">Team</h1>
        <NewEmployeeForm />
      </div>
      {/* Employee table — map over employees */}
    </div>
  )
}
```

**`src/components/auth/new-employee-form.tsx`** ("use client"):
```tsx
"use client"
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { GeneratedPasswordModal } from './generated-password-modal'

export function NewEmployeeForm() {
  const [open, setOpen] = useState(false)
  const [username, setUsername] = useState('')
  const [generatedPassword, setGeneratedPassword] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const router = useRouter()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)
    const supabase = createClient()
    const { data, error } = await supabase.functions.invoke('create-employee', {
      body: { username: username.trim() },
    })
    setLoading(false)
    if (error || !data?.data?.temp_password) {
      setError(data?.error?.message ?? 'Failed to create employee')
      return
    }
    setGeneratedPassword(data.data.temp_password)
    setOpen(false)
    router.refresh()
  }

  return (
    <>
      <Button onClick={() => setOpen(true)}>Add Employee</Button>
      {open && (
        <form onSubmit={handleSubmit} className="space-y-4 border p-4 rounded">
          <Label htmlFor="username">Username / Email</Label>
          <Input id="username" value={username} onChange={e => setUsername(e.target.value)} required />
          {error && <p className="text-destructive text-sm">{error}</p>}
          <div className="flex gap-2">
            <Button type="submit" disabled={loading}>{loading ? 'Creating…' : 'Create Employee'}</Button>
            <Button variant="outline" type="button" onClick={() => setOpen(false)}>Cancel</Button>
          </div>
        </form>
      )}
      <GeneratedPasswordModal
        password={generatedPassword}
        onDismiss={() => setGeneratedPassword(null)}
      />
    </>
  )
}
```

**`src/components/auth/generated-password-modal.tsx`** ("use client"):
```tsx
"use client"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'

interface Props {
  password: string | null
  onDismiss: () => void
}

export function GeneratedPasswordModal({ password, onDismiss }: Props) {
  return (
    <Dialog open={password !== null} onOpenChange={(open) => { if (!open) onDismiss() }}>
      <DialogContent onPointerDownOutside={(e) => e.preventDefault()}>
        <DialogHeader>
          <DialogTitle>Employee Account Created</DialogTitle>
          <DialogDescription>
            Convey to employee out of band. This will not be shown again.
          </DialogDescription>
        </DialogHeader>
        <div className="my-4 rounded bg-muted p-4 font-mono text-lg tracking-widest select-all">
          {password}
        </div>
        <DialogFooter>
          <Button onClick={onDismiss}>I have noted the password</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
```

**CRITICAL modal rules:**
- `onPointerDownOutside={(e) => e.preventDefault()}` — prevents accidental dismissal by clicking outside
- `select-all` class — makes password easy to copy
- `onDismiss` sets `generatedPassword = null` — plaintext is gone from React state; no recovery path

### Architecture Patterns to Follow

- **Error format:** `{error: {code, message}}` from `_shared/errors.ts` — all Edge Functions
- **Logging:** structured JSON `{ts, level, tenant_id, actor_id, event, ...}` — no PII, no passwords
- **bcryptjs:** `npm:bcryptjs`, cost 12 (NFR-9). Do NOT use `deno.land/x/bcrypt`
- **Rollback on failure:** if `public.users` insert fails after `auth.users` created, call `adminClient.auth.admin.deleteUser(authUserId)` to clean up (same pattern as bootstrap-admin)
- **Service-role for admin writes, JWT-scope for reads:** never bypass RLS on read paths
- **`SUPABASE_SERVICE_ROLE_KEY`** is auto-injected by Supabase Edge runtime — do NOT return it in any response

### Existing Code to Reuse (Do Not Reinvent)

| File | What to reuse |
|------|---------------|
| `functions/_shared/auth.ts` | `verifyJwtAndScope()`, `isAuthFailure()` — copy to `create-employee/_shared/auth.ts` |
| `functions/_shared/errors.ts` | All error codes including `user_already_exists`, `forbidden_role` — copy to `create-employee/_shared/errors.ts` |
| `bootstrap-admin/index.ts` | Rollback pattern (`auth.admin.deleteUser` on profile failure), bcrypt pattern, structured log pattern |
| `packages/shared-types/index.ts` | TypeScript types for `users`, `user_events` tables (after T-2.4 regeneration) |

### Files NOT to Touch (Regression Protection)

- `supabase/migrations/000[1-3]_*.sql` — Never edit applied migrations. Roll-forward only.
- `supabase/functions/_shared/auth.ts` and `errors.ts` — Do NOT modify canonical files. Only add local copies.
- `supabase/functions/bootstrap-admin/` — Story 1.2 is done; don't touch it.
- `supabase/seed.sql` — Seed tenant already exists. Don't touch.
- `packages/shared-types/index.ts` — Regenerate after migration, do not hand-edit.

### Do Not Do

- Do NOT log the plaintext password anywhere — not `console.log`, not `console.error`, not structured logs
- Do NOT store plaintext in `public.users` — only the bcrypt hash
- Do NOT use `deno.land/x/bcrypt` — use `npm:bcryptjs`
- Do NOT import `_shared/` with `../` prefix in Edge Functions — MCP bundler can't resolve it (Story 1.2 debug)
- Do NOT create mobile app screens in this story — mobile login is Story 1.4+
- Do NOT create a complex admin shell in this story — just enough to load `/team` and show the modal
- Do NOT implement Story 1.5 (force-change on login) here — set `must_change_password = true` and leave it for Story 1.5

### Testing Strategy

**Edge Function tests (mandatory — verify via MCP execute_sql + function invoke):**
1. **AC-1:** Create employee → `SELECT id, role, must_change_password FROM public.users WHERE role='employee'` — verify row exists
2. **AC-4:** Verify hash stored: `SELECT length(bcrypt_password_hash) > 0 AS hash_set FROM public.users WHERE role='employee'`
3. **AC-5:** `SELECT * FROM user_events WHERE event_type='account_created'` — verify row with correct actor_id
4. **AC-6:** Call with no auth header → 401; call with employee JWT → 403
5. **AC-7:** Create same username twice → second call returns 409

**UI tests (manual — run dev server):**
1. Navigate to `/team` — employee list loads
2. Click "Add Employee" → form appears
3. Submit valid username → modal shows password with warning text
4. Clicking outside modal does NOT dismiss it (pointer-down-outside prevented)
5. Click "I have noted the password" → modal closes, password gone from DOM
6. Refresh page → password not visible anywhere

### Cross-Story Dependencies

- **Story 1.4** (login): Reads `public.users.bcrypt_password_hash` and `must_change_password`. Employee account created here must be login-ready.
- **Story 1.5** (force password change): Relies on `must_change_password = true` set in this story and `user_events.password_changed` event type already in the enum.
- **Story 1.6** (deactivate/reactivate): Uses `user_events` table created in T-2. Enum already includes `account_deactivated` and `account_reactivated` — do NOT re-create this table in Story 1.6.

### Latest Technical Information (Context7, 2026-05-26)

**Supabase SSR — key env var name change:**
- New preferred name: `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` (same value as `anon key`; functionally identical to `NEXT_PUBLIC_SUPABASE_ANON_KEY`)
- Use `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in `apps/admin/` to match current docs
- `createServerClient` and `createBrowserClient` from `@supabase/ssr` — confirmed current API

**shadcn Dialog — controlled pattern:**
```tsx
<Dialog open={open} onOpenChange={setOpen}>
  <DialogContent>
    <DialogHeader><DialogTitle>…</DialogTitle></DialogHeader>
    {/* content */}
    <DialogFooter><Button onClick={() => setOpen(false)}>Done</Button></DialogFooter>
  </DialogContent>
</Dialog>
```
No `<DialogTrigger>` needed when managing open state externally.

### Project Structure Reference

| Path | Type | Story |
|------|------|-------|
| `supabase/functions/create-employee/index.ts` | NEW | 1.3 |
| `supabase/functions/create-employee/_shared/errors.ts` | NEW (local copy) | 1.3 |
| `supabase/functions/create-employee/_shared/auth.ts` | NEW (local copy) | 1.3 |
| `supabase/functions/create-employee/README.md` | NEW | 1.3 |
| `supabase/migrations/0004_create_user_events.sql` | NEW | 1.3 |
| `packages/shared-types/index.ts` | UPDATE (regenerated) | 1.3 |
| `apps/admin/` | NEW (entire scaffold) | 1.3 |
| `apps/admin/src/app/(app)/team/page.tsx` | NEW | 1.3 |
| `apps/admin/src/components/auth/new-employee-form.tsx` | NEW | 1.3 |
| `apps/admin/src/components/auth/generated-password-modal.tsx` | NEW | 1.3 |
| `apps/admin/src/lib/supabase/client.ts` | NEW | 1.3 |
| `apps/admin/src/lib/supabase/server.ts` | NEW | 1.3 |
| `apps/admin/src/middleware.ts` | NEW | 1.3 |
| `nirman-crm/.env.example` | UPDATE (add NEXT_PUBLIC_* vars) | 1.3 |

### Source Hints

- Architecture §Decision Impact: "Story 1.3 locks: Generated Password modal pattern (Edge Function returns once, never logged)"
- Architecture §Edge Function Patterns: auth pattern, response shape, tenant context
- Architecture §Client Patterns (Web): server components, TanStack Query, React Hook Form
- `functions/_shared/auth.ts` — `verifyJwtAndScope()` source of truth
- `bootstrap-admin/index.ts` — bcrypt + rollback pattern to reuse
- Migration 0001 — `public.users` schema (no changes needed here)

## Dev Agent Record

### Agent Model Used

claude-sonnet-4-6 (bmad-create-story)

### Debug Log References

None yet — story not started.

### Completion Notes List

None yet.

### File List

None yet — populated during dev-story execution.
