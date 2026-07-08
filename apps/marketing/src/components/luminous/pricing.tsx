import { ArrowRight, Check, Play } from "lucide-react";

// What a builder's team gets in the demo — grounded in the real product surface.
const included = [
  "Admin web dashboard + agent mobile app",
  "Lead capture, status pipeline & duplicate prevention",
  "Click-to-call + follow-up reminders (push)",
  "Inventory, holds & project updates",
  "Funnel + per-agent performance",
  "One-click Excel import / export",
];

export function Pricing() {
  return (
    <section id="pricing" className="relative mx-auto max-w-7xl px-6 py-24">
      <div className="animate-on-scroll mx-auto max-w-2xl text-center">
        <span className="text-xs font-medium uppercase tracking-[0.2em] text-amber-400">Get started</span>
        <h2 className="mt-4 font-display text-4xl font-light tracking-tight text-white sm:text-5xl">
          See Nirman CRM on your own leads.
        </h2>
        <p className="mt-4 text-neutral-400">
          Book a 20-minute walkthrough. We import a sample of your register, set up your projects and
          team, and put the mobile app in your agents&apos; hands, live.
        </p>
      </div>

      <div className="animate-on-scroll mt-14 grid grid-cols-1 items-stretch gap-6 lg:grid-cols-2">
        {/* Left — what's included */}
        <div className="rounded-[24px] border border-white/10 bg-neutral-900/60 p-8 backdrop-blur-sm sm:p-10">
          <p className="text-sm font-medium uppercase tracking-[0.16em] text-neutral-400">
            What we&apos;ll set up together
          </p>
          <ul className="mt-6 space-y-4">
            {included.map((f) => (
              <li key={f} className="flex items-start gap-3 text-[15px] text-neutral-200">
                <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-amber-500/15">
                  <Check className="h-3.5 w-3.5 text-amber-400" />
                </span>
                {f}
              </li>
            ))}
          </ul>
        </div>

        {/* Right — demo CTA card */}
        <div className="electric-card flex flex-col justify-between overflow-hidden rounded-[24px] border border-white/10 bg-neutral-900/80 p-8 backdrop-blur-sm sm:p-10">
          <div>
            <span className="inline-flex items-center gap-2 rounded-full border border-amber-500/30 bg-amber-500/10 px-3 py-1 text-xs font-medium text-amber-400">
              <span className="h-1.5 w-1.5 animate-livepulse rounded-full bg-amber-400" />
              Built for real estate
            </span>
            <h3 className="mt-6 font-display text-3xl font-light leading-tight tracking-tight text-white">
              Book a live demo.
            </h3>
            <p className="mt-3 max-w-sm text-neutral-400">
              No paper register, no scattered Excel sheets. See exactly how your sales floor runs on one
              screen before you commit to anything.
            </p>
          </div>

          <div className="mt-8 flex flex-wrap items-center gap-4">
            <a
              href="#footer"
              className="inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-yellow-200 via-amber-400 to-amber-500 px-6 py-3 text-sm font-semibold text-black shadow-lg shadow-amber-500/40 transition-transform hover:scale-[1.03]"
            >
              Book a live demo
              <ArrowRight className="h-4 w-4" />
            </a>
            <a
              href="#platform"
              className="inline-flex items-center gap-2 rounded-full bg-white/5 px-6 py-3 text-sm font-semibold text-white ring-1 ring-white/10 transition-transform hover:scale-[1.03]"
            >
              <Play className="h-4 w-4" />
              See the pipeline
            </a>
          </div>
        </div>
      </div>
    </section>
  );
}
