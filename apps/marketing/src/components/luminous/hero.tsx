import Link from "next/link";
import { ArrowRight, Play, TrendingUp } from "lucide-react";

function GrowthVelocityCard() {
  return (
    <div className="electric-card overflow-hidden rounded-[32px] border border-white/10 bg-neutral-900/60 p-6 backdrop-blur-sm sm:p-8">
      {/* Live pulsing badge */}
      <div className="flex items-center justify-between">
        <span className="text-sm text-neutral-400">Pipeline Health</span>
        <span className="inline-flex items-center gap-2 rounded-full border border-amber-500/30 bg-amber-500/10 px-3 py-1 text-xs font-medium text-amber-400">
          <span className="h-1.5 w-1.5 animate-livepulse rounded-full bg-amber-400" />
          Live
        </span>
      </div>

      <div className="mt-6 flex items-end gap-3">
        <span className="font-display text-6xl font-light tracking-tight text-white">+38%</span>
        <span className="mb-2 inline-flex items-center gap-1 text-sm font-medium text-amber-400">
          <TrendingUp className="h-4 w-4" />
          close rate
        </span>
      </div>

      {/* Sparkline — exact path + brass gradient area fill, dot on last point */}
      <div className="mt-6">
        <svg viewBox="0 0 290 60" className="h-24 w-full" preserveAspectRatio="none">
          <defs>
            <linearGradient id="chartGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#C9A354" stopOpacity="0.3" />
              <stop offset="100%" stopColor="#C9A354" stopOpacity="0" />
            </linearGradient>
          </defs>
          <path
            d="M0 50 C 40 50, 60 30, 100 35 C 140 40, 160 10, 200 15 C 240 20, 260 5, 280 0 L 280 60 L 0 60 Z"
            fill="url(#chartGradient)"
          />
          <path
            d="M0 50 C 40 50, 60 30, 100 35 C 140 40, 160 10, 200 15 C 240 20, 260 5, 280 0"
            fill="none"
            stroke="#C9A354"
            strokeWidth="2"
            strokeLinecap="round"
          />
          <circle cx="280" cy="0" r="4" fill="#C9A354" />
          <circle cx="280" cy="0" r="8" fill="#C9A354" fillOpacity="0.25" />
        </svg>
      </div>

      {/* Metric list */}
      <div className="mt-6 space-y-3 border-t border-white/10 pt-6">
        {[
          ["Active leads", "1,284"],
          ["Follow-ups today", "12"],
          ["Sold this month", "5"],
        ].map(([label, value]) => (
          <div key={label} className="flex items-center justify-between text-sm">
            <span className="text-neutral-400">{label}</span>
            <span className="font-medium text-white">{value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function Hero() {
  return (
    <section id="top" className="relative w-full min-h-[90vh] overflow-hidden bg-[#050505]">
      {/* LaserFlow beam — pre-rendered loop (webm trimmed 4s–10s). Cheap GPU
          video decode instead of a live shader. Masked to blend into content. */}
      <video
        autoPlay
        muted
        loop
        playsInline
        poster="/hero-laser-poster.jpg"
        className="pointer-events-none absolute inset-0 z-0 h-full w-full object-cover [mask-image:linear-gradient(to_bottom,black,black_65%,transparent)]"
      >
        <source src="/hero-laser.webm" type="video/webm" />
        <source src="/hero-laser.mp4" type="video/mp4" />
      </video>

      {/* Global <Background/> supplies the atmospheric star-field + glows. */}
      <div className="relative z-10 mx-auto grid w-full max-w-7xl grid-cols-12 items-center gap-8 px-6 py-24">
        {/* Left — copy */}
        <div className="animate-entry col-span-12 lg:col-span-7">
          <span className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-1.5 text-sm text-neutral-300">
            <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />
            Real estate CRM · built by Nirman Media
          </span>

          <h1 className="mt-6 font-display text-5xl font-light leading-[1.05] tracking-tight text-white sm:text-7xl">
            RETIRE THE REGISTER<span className="inline-flex empty:hidden"></span>
            <br />
            ONE PIPELINE
          </h1>

          <p className="mt-6 max-w-lg text-lg text-neutral-400">
            Nirman CRM replaces the paper register and the scattered Excel sheets with one simple screen
            your sales team already knows how to use: status, follow-up, call. Built for how real estate
            actually sells.
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-4">
            <a
              href="#pricing"
              className="inline-flex items-center gap-2 rounded-full bg-gradient-to-r from-yellow-200 via-amber-400 to-amber-500 px-6 py-3 text-sm font-semibold text-black shadow-lg shadow-amber-500/60 transition-transform hover:scale-[1.03]"
            >
              Book a live demo
              <ArrowRight className="h-4 w-4" />
            </a>
            <Link
              href="/demo"
              className="inline-flex items-center gap-2 rounded-full bg-white px-6 py-3 text-sm font-semibold text-black transition-transform hover:scale-[1.03]"
            >
              <Play className="h-4 w-4" />
              See it live
            </Link>
          </div>
        </div>

        {/* Right — pipeline health card */}
        <div className="animate-entry col-span-12 lg:col-span-5" style={{ animationDelay: "0.15s" }}>
          <GrowthVelocityCard />
        </div>
      </div>
    </section>
  );
}
