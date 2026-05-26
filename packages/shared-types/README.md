# @nirman/shared-types

Generated Supabase TypeScript types. Consumed by `apps/admin/` and `supabase/functions/*`.

## Regenerate

```bash
# from monorepo root
npm run supabase:gen-types
# or directly
cd packages/shared-types && npm run regen
# or via Supabase MCP
mcp__supabase__generate_typescript_types(project_id="vhgruadourflpxuzuxfn")
```

CI auto-regenerates on every migration merged to `main` (see `.github/workflows/regen-types.yml`, deferred to a later story).

## Don't edit `index.ts` by hand

Schema source of truth is `supabase/migrations/*.sql`. Hand-edits will be overwritten on next regen.
