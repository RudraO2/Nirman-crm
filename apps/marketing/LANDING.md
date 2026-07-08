# Nirman CRM — Marketing Landing Page

Marketing site for **Nirman CRM** (real-estate CRM for builders; "LMS" = Lead
Management). Separate Next.js app from `apps/admin`.

**Run:** `npm run dev` → http://localhost:3000

## Origin
Adapted from the **"Luminous" template** (an AI-social-SaaS landing). Conversion to
Nirman is partial — a couple of sections still hold placeholder copy (see below).

## Stack
Next.js 16.2.6 (App Router, Turbopack) · React 19 · TypeScript · Tailwind v4 ·
lucide-react · fonts Inter + Bricolage Grotesque (`--font-display`). Theme: dark
`#050505` base + brass `#C9A354` / amber accents (echoes admin's evergreen `#132A21`
+ ivory `#F6F3EC` + brass brand). `react-router-dom` is in deps but **unused**.

## Structure
- **Active** components: `src/components/luminous/*`
- **Dead** (ignore): `src/components/sections/*`
- `app/page.tsx` render order:
  `Background` (fixed star-field + amber blur glows) → `Nav` → `Hero` →
  `Dashboard` → `Testimonials` → `Pricing` → `Footer`

## Section status
| Section | id | State |
|---|---|---|
| Hero | `#top` | ✅ Nirman — "RETIRE THE REGISTER / ONE PIPELINE" + GrowthVelocityCard, `min-h-[90vh]` |
| Dashboard | `#platform` | ✅ Faithful mock of the real admin UI (ivory/evergreen/brass) |
| Testimonials | `#testimonials` | ⚠️ Still fake Luminous creators — **owner edits later, leave alone** |
| Pricing | `#pricing` | ✅ Converted to **book-a-demo** (no prices / no SaaS tiers) |
| Footer | `#footer` | ✅ Nirman Media + demo email capture |

## Known gaps
- Footer/demo links + email form are `#` stubs — **no real contact endpoint** wired.
- **UnicornStudio WebGL hero bg was removed** (caused lag). Also removed duplicate
  `blur-[120px]` layers — global `Background` already glows. Don't stack big CSS
  blurs + live WebGL. Possible future: pre-rendered looping hero video (mp4+webm,
  `opacity-20`, autoplay/muted/playsInline) instead — not built yet.
