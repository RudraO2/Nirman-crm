# Nirman CRM

Real Estate CRM + LMS for Nirman Media — multi-tenant SaaS-ready architecture.

## Monorepo Layout

```
nirman-crm/
├── apps/
│   ├── admin/         # Next.js 16.2 admin web (deferred to Story 1.4)
│   └── mobile/        # Flutter 3.44 employee + admin app (deferred to Story 1.4)
├── packages/
│   └── shared-types/  # Generated Supabase TypeScript types
├── supabase/
│   ├── config.toml
│   ├── seed.sql
│   ├── migrations/    # Declarative SQL — roll-forward only
│   ├── functions/
│   │   └── _shared/   # Reusable Edge Function helpers (auth, errors, log)
│   └── tests/
│       └── rls/       # RLS contract tests
└── package.json       # npm workspaces root
```

## Stack

- Postgres 16 via Supabase Cloud (region `ap-south-1`)
- Supabase Edge Functions (Deno + TypeScript)
- Next.js 16.2 + Tailwind v4 + shadcn 4.8 + TanStack Query 5 (admin web)
- Flutter 3.44 + Riverpod 3.3 + Drift + supabase_flutter + firebase_messaging (mobile)
- npm workspaces · TypeScript strict · `@nirman/shared-types` generated post-migration

## Story Status

| Story | Title | Status |
|-------|-------|--------|
| 1.1 | Initialize multi-tenant schema with RLS | in-progress |

## Local Dev (Supabase)

Prereqs: Node 20+, `supabase` CLI (`npm i -g supabase`), Docker Desktop.

```bash
cd supabase
supabase start
supabase test db        # runs supabase/tests/rls/*.test.sql
supabase gen types typescript --linked > ../packages/shared-types/index.ts
```

## Tenant Isolation Contract

Every table carries `tenant_id`. RLS enforces `tenant_id = current_setting('app.current_tenant')::uuid`. Edge Functions call `set_current_tenant(uuid)` RPC after JWT verification. Cross-tenant access impossible by construction, not by code discipline.
