# Nirman CRM — design system (mobile, ui-modern-refresh 2026-07-12)

Source of truth in code: `apps/mobile/lib/core/theme/app_theme.dart`
(AppColors, AppType) + `apps/mobile/lib/app.dart` (_buildTheme).

## Theme
Light only. Scene: a rep outdoors in Indian daylight on a mid-range Android.
Warm ivory ground, near-black green ink, evergreen for committed actions.

## Color (Restrained strategy)
- Ground: surfaceBase #F6F3EC (warm ivory) · surfaceRaised #FFFFFF (cards)
- Ink: inkPrimary #1C231F · inkSecondary (muted) · inkDisabled
- Brand: evergreen #132A21 (primary actions, dark panels) ·
  brass #A8823C / brass-bright #C9A354 (accents, on-dark highlights) ·
  brassSoft #EADFC4 (soft fills, selected pills)
- Status: warm/hot/cold/dead/sold each have ink + bg pair (see AppColors)
- Accent budget: brass ≤10% of any screen; evergreen carries primary
  buttons and the success/identity panels only.

## Typography — ONE family
- Inter everywhere (body AND titles). Fraunces retired 2026-07-12
  ("font difference on top" + dated-serif feedback).
- Titles: `AppType.display(fontSize: …)` — Inter w800(w700 for >=24px optical),
  letterSpacing -0.4, fixed sizes. Never call GoogleFonts.fraunces again;
  never use a display font in labels/buttons/data.
- Body 16/14 Inter; labels 12 w700 uppercase tracking for section headers
  (existing WORKSPACE/SETTINGS pattern).
- Code/codes (visit codes): Fira Code stays (functional monospace).
- Scale ratio tight (product register): 12 · 14 · 16 · 18 · 21 · 24.

## Shape & depth
- Radii: 12 inputs/buttons-small, 13–14 primary buttons, 16–18 cards/panels.
- Depth via fills + hairline (AppColors.line) borders, not shadows.
  No elevation stacks; scrolledUnderElevation 0 everywhere (theme-level).

## Components
- AppBar: theme-level surfaceBase + inkPrimary icons + Inter w800 title.
- Primary button: evergreen bg, brassBright fg, h52, radius 13, w700 label.
- Snackbar: evergreen bg, ivory text, brassBright action (theme-level, no
  per-call colors).
- Success moments: evergreen panel + brassSoft check circle (verify-visit
  pattern) — reuse, don't invent new celebration idioms.

## Composition rules (learned from Rudra's eyeball rounds, 2026-07-13)
- **One dark anchor per tab.** Each mobile tab gets exactly ONE evergreen
  element that carries its identity: Leads = the work queue, You = the
  profile card, reception = the verified panel. Never two dark blocks on
  one screen; never zero if the tab has a natural anchor.
- **One-signal lead cards.** Name + status pill, one grey meta line, at most
  ONE flag in ONE color. Red = overdue only; amber = needs action; grey =
  context. The most actionable thing wins; never stack colored flags.
- **Queues are rows, not tiles.** Tappable counts render as full-width rows
  (icon · full label · count pill · chevron), only when non-zero. No boxed
  stat grids that truncate their own labels.
- **Context is text.** Dates, scores, streaks = one quiet uncontained line,
  not a decorated band.
- **Insights are visual.** Boss-facing numbers = charts/bands (momentum
  bars, stacked status band), not repeated stat boxes.

## Bans (project-specific, on top of impeccable's)
- No serif/display fonts anywhere in app UI.
- No confetti/gamification beyond the existing Sold celebration seam.
- No per-screen AppBar/snackbar color overrides — theme owns them.
