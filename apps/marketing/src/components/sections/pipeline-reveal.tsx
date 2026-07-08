import type { CSSProperties } from "react";

const statuses = [
  { name: "Hot", color: "var(--hot)", bg: "var(--hot-bg)" },
  { name: "Warm", color: "var(--warm)", bg: "var(--warm-bg)" },
  { name: "Cold", color: "var(--cold)", bg: "var(--cold-bg)" },
  { name: "Dead", color: "var(--dead)", bg: "var(--dead-bg)" },
  { name: "Sold", color: "var(--sold)", bg: "var(--sold-bg)" },
];

export function PipelineReveal() {
  return (
    <section id="product" className="relative bg-mist py-24 sm:py-32">
      <div className="mx-auto max-w-3xl px-6 text-center">
        <p className="eyebrow mb-4">One screen. No training needed.</p>
        <h2 className="text-balance font-serif text-3xl text-ink sm:text-4xl">
          Every lead has exactly one status.{" "}
          <span className="italic">That&apos;s the whole system.</span>
        </h2>
      </div>

      <div className="mx-auto mt-14 max-w-2xl px-6">
        <div className="rounded-2xl border border-line-2 bg-paper p-6 shadow-[var(--shadow-lg)] sm:p-8">
          <div className="flex items-center justify-between border-b border-line pb-4">
            <span className="font-serif text-lg text-ink">Rohan Mehta</span>
            <span className="font-mono text-xs text-ink-3">2BHK · The Velocity</span>
          </div>

          <div className="mt-5 flex flex-wrap gap-2">
            {statuses.map((s, i) => (
              <span
                key={s.name}
                className={`rounded-full px-3.5 py-1.5 text-sm font-medium ${i === 0 ? "ring-2 ring-offset-2 ring-offset-paper" : "opacity-45"}`}
                style={{
                  color: s.color,
                  backgroundColor: s.bg,
                  ...(i === 0 ? ({ "--tw-ring-color": s.color } as CSSProperties) : {}),
                }}
              >
                {s.name}
              </span>
            ))}
          </div>

          <div className="mt-6 grid grid-cols-2 gap-3 text-left sm:grid-cols-4">
            {[
              ["Next follow-up", "Tomorrow, 11:00 AM"],
              ["Source", "Referral"],
              ["Budget", "₹85L – 95L"],
              ["Last action", "Called · 2h ago"],
            ].map(([k, v]) => (
              <div key={k} className="rounded-lg bg-mist px-3 py-2.5">
                <p className="font-mono text-[10px] uppercase tracking-wide text-ink-3">{k}</p>
                <p className="mt-0.5 text-sm text-ink">{v}</p>
              </div>
            ))}
          </div>

          <div className="mt-6 flex gap-3">
            <div className="flex-1 rounded-lg bg-brass py-2.5 text-center text-sm font-semibold text-white">
              Call now
            </div>
            <div className="flex-1 rounded-lg border border-line-2 py-2.5 text-center text-sm font-medium text-ink">
              Reschedule
            </div>
          </div>
        </div>

        <p className="mx-auto mt-8 max-w-xl text-center text-lg leading-relaxed text-ink-2">
          No pipeline stages to configure. No custom fields to design. Status is the pipeline.
        </p>
      </div>
    </section>
  );
}
