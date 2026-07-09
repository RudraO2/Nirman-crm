"use client";

/* Nirman /demo — Interactive Showroom shell.
   Spec: _bmad-output/planning-artifacts/ux-designs/ux-CRM-LMS-2026-07-09/{DESIGN,EXPERIENCE}.md
   Dark stage frames the light product demos (iframed, same-origin) and drives them
   via postMessage. Admin gets shell-drawn browser chrome; the mobile HTML owns its bezel. */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";

type Surface = "admin" | "mobile";

interface Feature {
  key: string; // == postMessage target == deep-link #slug
  label: string;
  blurb: string;
}

const FEATURES: Record<Surface, Feature[]> = {
  admin: [
    { key: "home", label: "Live pipeline", blurb: "Today's leads, missed follow-ups, team pulse at a glance" },
    { key: "leads", label: "Lead management", blurb: "Active, future pool & archived — bulk-assign in one place" },
    { key: "insights", label: "Insights & funnel", blurb: "Where leads drop off, per-employee performance" },
    { key: "team", label: "Team & hierarchy", blurb: "Accounts, tiers and reporting line in one table" },
    { key: "inventory", label: "Inventory & holds", blurb: "Unit grid, holds, amendments, developer updates" },
    { key: "data", label: "Import & export", blurb: "Column-mapping import wizard, filtered exports" },
  ],
  mobile: [
    { key: "home", label: "My leads & today", blurb: "Follow-ups, visits, untouched — the rep's morning" },
    { key: "outcome", label: "One-tap call outcome", blurb: "Log how the call went the moment you hang up" },
    { key: "detail", label: "Lead detail", blurb: "WhatsApp, follow-up, share, full timeline" },
    { key: "plan", label: "Plan", blurb: "Overdue plus scheduled follow-ups and site visits" },
    { key: "alarms", label: "Follow-up alarms", blurb: "Rings even when the app is closed" },
    { key: "you", label: "You & streaks", blurb: "Personal stats, targets, archive" },
  ],
};

const LOGICAL: Record<Surface, { w: number; h: number }> = {
  admin: { w: 1180, h: 760 },
  mobile: { w: 388, h: 812 },
};

const CHROME_H = 44; // admin browser title bar height (unscaled)
const SRC: Record<Surface, string> = {
  admin: "/demo/admin.html",
  mobile: "/demo/mobile.html?embed=1",
};
const SURFACE_LABEL: Record<Surface, string> = { admin: "Admin · Web", mobile: "Field app" };

function naturalSize(s: Surface) {
  return { w: LOGICAL[s].w, h: LOGICAL[s].h + (s === "admin" ? CHROME_H : 0) };
}

export function DemoShell() {
  const [surface, setSurface] = useState<Surface>("admin");
  const [mounted, setMounted] = useState<Record<Surface, boolean>>({ admin: true, mobile: false });
  const [ready, setReady] = useState<Record<Surface, boolean>>({ admin: false, mobile: false });
  const [activeFeature, setActiveFeature] = useState<string | null>(null);
  const [visited, setVisited] = useState<Record<Surface, Set<string>>>({ admin: new Set(), mobile: new Set() });
  const [present, setPresent] = useState(false);
  const [bannerDismissed, setBannerDismissed] = useState(false);
  const [announce, setAnnounce] = useState("");
  const [showPulse, setShowPulse] = useState(true);
  const [pulseKey, setPulseKey] = useState(0);
  const [copied, setCopied] = useState(false);

  const stageRef = useRef<HTMLDivElement | null>(null);
  const iframes = useRef<Record<Surface, HTMLIFrameElement | null>>({ admin: null, mobile: null });
  const pending = useRef<Record<Surface, string | null>>({ admin: null, mobile: null });
  const [scale, setScale] = useState(1);

  const features = FEATURES[surface];

  // ── Responsive scale: fit the natural frame into the stage ──────────────
  useEffect(() => {
    const el = stageRef.current;
    if (!el) return;
    const compute = () => {
      const pad = present ? 24 : 40;
      const availW = el.clientWidth - pad * 2;
      const availH = el.clientHeight - pad * 2;
      const nat = naturalSize(surface);
      setScale(Math.min(1, availW / nat.w, availH / nat.h));
    };
    compute();
    const ro = new ResizeObserver(compute);
    ro.observe(el);
    return () => ro.disconnect();
  }, [surface, present]);

  // ── Send a navigate command to a surface (queue until it's ready) ───────
  const drive = useCallback(
    (s: Surface, target: string) => {
      const frame = iframes.current[s];
      if (ready[s] && frame?.contentWindow) {
        frame.contentWindow.postMessage(
          { source: "nirman-demo", action: "navigate", target },
          window.location.origin,
        );
      } else {
        pending.current[s] = target;
      }
    },
    [ready],
  );

  // Mark a surface ready and flush any queued navigate. Called both from the
  // iframe's `ready` message AND its onLoad — onLoad is race-proof for a
  // same-origin iframe (the inline bridge has run by load), so a `ready`
  // message that arrives before this listener attaches can't strand the tour.
  const markReady = useCallback((s: Surface) => {
    setReady((r) => (r[s] ? r : { ...r, [s]: true }));
    const q = pending.current[s];
    const win = iframes.current[s]?.contentWindow;
    if (q && win) {
      win.postMessage({ source: "nirman-demo", action: "navigate", target: q }, window.location.origin);
      pending.current[s] = null;
    }
  }, []);

  // ── postMessage listener (ready handshake + navigated auto-tick) ────────
  useEffect(() => {
    function onMsg(e: MessageEvent) {
      if (e.origin !== window.location.origin) return;
      const d = e.data as { source?: string; event?: string; screen?: string } | null;
      if (!d || d.source !== "nirman-demo-inner") return;
      const src = (["admin", "mobile"] as Surface[]).find(
        (s) => iframes.current[s]?.contentWindow === e.source,
      );
      if (!src) return;
      if (d.event === "ready") {
        markReady(src);
      } else if (d.event === "navigated" && d.screen) {
        const screen = d.screen;
        setVisited((v) => {
          const next = new Set(v[src]);
          next.add(screen);
          return { ...v, [src]: next };
        });
        if (src === surface) {
          const feat = FEATURES[src].find((f) => f.key === screen);
          setActiveFeature(screen);
          if (feat) setAnnounce(`Showing ${feat.label}`);
          setShowPulse(false);
          setPulseKey((k) => k + 1); // re-trigger highlight ring
        }
      }
    }
    window.addEventListener("message", onMsg);
    return () => window.removeEventListener("message", onMsg);
  }, [surface, markReady]);

  // ── Deep link on mount: ?d=surface#slug, else device default ────────────
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const d = params.get("d");
    let initial: Surface;
    if (d === "admin" || d === "mobile") {
      initial = d;
    } else {
      const coarse =
        window.matchMedia?.("(pointer: coarse)").matches || window.innerWidth < 1024;
      initial = coarse ? "mobile" : "admin";
    }
    // One-time external(URL/device)→React init on mount; intentionally synchronous.
    /* eslint-disable react-hooks/set-state-in-effect */
    if (initial !== "admin") {
      setSurface(initial);
      setMounted((m) => ({ ...m, [initial]: true }));
    }
    const slug = window.location.hash.replace(/^#/, "");
    if (slug && FEATURES[initial].some((f) => f.key === slug)) {
      pending.current[initial] = slug;
      setActiveFeature(slug);
    }
    /* eslint-enable react-hooks/set-state-in-effect */
  }, []);

  // ── Surface switch ──────────────────────────────────────────────────────
  const switchSurface = useCallback((s: Surface) => {
    setSurface(s);
    setMounted((m) => ({ ...m, [s]: true }));
    setActiveFeature(null);
    setShowPulse(false);
    const url = new URL(window.location.href);
    url.searchParams.set("d", s);
    url.hash = "";
    window.history.replaceState(null, "", url.toString());
    // move focus onto the freshly shown stage region
    requestAnimationFrame(() => document.getElementById("demo-stage-region")?.focus());
  }, []);

  const onFeature = useCallback(
    (key: string) => {
      setActiveFeature(key);
      setShowPulse(false);
      drive(surface, key);
      const url = new URL(window.location.href);
      url.hash = key;
      window.history.replaceState(null, "", url.toString());
    },
    [drive, surface],
  );

  const copyLink = useCallback(() => {
    const url = new URL(window.location.href);
    url.searchParams.set("d", surface);
    if (activeFeature) url.hash = activeFeature;
    navigator.clipboard?.writeText(url.toString()).then(() => {
      setCopied(true);
      setAnnounce("Link to this view copied");
      setTimeout(() => setCopied(false), 2000);
    });
  }, [surface, activeFeature]);

  const togglePresent = useCallback(() => {
    setPresent((p) => {
      const next = !p;
      if (next) document.documentElement.requestFullscreen?.().catch(() => {});
      else if (document.fullscreenElement) document.exitFullscreen?.().catch(() => {});
      return next;
    });
  }, []);

  useEffect(() => {
    function onFsChange() {
      if (!document.fullscreenElement) setPresent(false);
    }
    function onKey(e: KeyboardEvent) {
      if (!present) return;
      if (e.key === "Escape") setPresent(false);
      if (e.key === "ArrowRight" || e.key === "ArrowLeft")
        switchSurface(surface === "admin" ? "mobile" : "admin");
    }
    document.addEventListener("fullscreenchange", onFsChange);
    window.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("fullscreenchange", onFsChange);
      window.removeEventListener("keydown", onKey);
    };
  }, [present, surface, switchSurface]);

  const visitedCount = visited[surface].size;
  const total = features.length;
  const tourComplete = visitedCount >= Math.min(5, total);

  const nat = naturalSize(surface);
  const frameBox = useMemo(
    () => ({ w: Math.round(nat.w * scale), h: Math.round(nat.h * scale) }),
    [nat.w, nat.h, scale],
  );

  return (
    <div className="flex min-h-screen flex-col bg-[#050505] text-[#F6F3EC]">
      {/* polite live region */}
      <div aria-live="polite" className="sr-only">
        {announce}
      </div>

      {/* ── Top bar ─────────────────────────────────────────────── */}
      {!present && (
        <header className="sticky top-0 z-30 flex items-center justify-between gap-4 border-b border-white/[0.08] bg-[#0D0D0F]/90 px-4 py-3 backdrop-blur-md sm:px-6">
          <Link
            href="/"
            className="flex items-center gap-2 rounded-lg px-2 py-1 text-sm text-[#C7C7C2] outline-none transition-colors hover:text-white focus-visible:ring-2 focus-visible:ring-[#E0C079]"
          >
            <span aria-hidden>←</span> Nirman
          </Link>

          {/* device toggle — tablist, manual activation */}
          <div
            role="tablist"
            aria-label="Choose a demo surface"
            className="flex items-center gap-1 rounded-[10px] border border-white/[0.08] bg-[#131316] p-1"
          >
            {(["admin", "mobile"] as Surface[]).map((s) => {
              const selected = surface === s;
              return (
                <button
                  key={s}
                  role="tab"
                  aria-selected={selected}
                  tabIndex={selected ? 0 : -1}
                  onClick={() => switchSurface(s)}
                  onKeyDown={(e) => {
                    if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
                      e.preventDefault();
                      (e.currentTarget.parentElement?.querySelector(
                        `[role="tab"]:not([aria-selected="true"])`,
                      ) as HTMLElement | null)?.focus();
                    }
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      switchSurface(s);
                    }
                  }}
                  className={
                    "relative rounded-[7px] px-3 py-1.5 text-sm font-medium outline-none transition-colors focus-visible:ring-2 focus-visible:ring-[#E0C079] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0D0D0F] " +
                    (selected
                      ? "bg-[#C9A354]/[0.14] text-white"
                      : "text-[#8A8A85] hover:text-[#C7C7C2]")
                  }
                >
                  {SURFACE_LABEL[s]}
                  {selected && (
                    <span className="absolute inset-x-2 -bottom-[5px] h-0.5 rounded-full bg-[#C9A354]" />
                  )}
                </button>
              );
            })}
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={copyLink}
              className="hidden rounded-lg border border-white/[0.14] px-3 py-2 text-sm text-[#F6F3EC] outline-none transition-colors hover:border-[#C9A354] focus-visible:ring-2 focus-visible:ring-[#E0C079] sm:block"
            >
              {copied ? "Copied ✓" : "Copy link"}
            </button>
            <button
              onClick={togglePresent}
              className="hidden rounded-lg border border-white/[0.14] px-3 py-2 text-sm text-[#F6F3EC] outline-none transition-colors hover:border-[#C9A354] focus-visible:ring-2 focus-visible:ring-[#E0C079] md:block"
            >
              Present
            </button>
            <Link
              href="/#pricing"
              className="rounded-lg bg-[#C9A354] px-4 py-2 text-sm font-semibold text-[#0D0D0F] outline-none transition-colors hover:bg-[#E0C079] focus-visible:ring-2 focus-visible:ring-[#E0C079] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0D0D0F]"
            >
              Book a demo
            </Link>
          </div>
        </header>
      )}

      {/* ── Main: stage + rail ──────────────────────────────────── */}
      <div className={"flex flex-1 " + (present ? "flex-col" : "flex-col lg:flex-row")}>
        {/* stage */}
        <div
          ref={stageRef}
          className="relative flex min-h-[60vh] flex-1 items-center justify-center overflow-hidden p-6 lg:min-h-0"
        >
          {/* live badge */}
          {!present && (
            <span className="pointer-events-none absolute left-4 top-4 z-20 inline-flex items-center gap-2 rounded-full border border-white/[0.08] bg-[#0D0D0F]/90 px-3 py-1 text-xs font-medium text-[#F6F3EC]">
              <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#3FBF6F]" />
              Live · interactive
            </span>
          )}

          <div
            id="demo-stage-region"
            tabIndex={-1}
            aria-label={`${SURFACE_LABEL[surface]} interactive demo`}
            className="relative outline-none"
            style={{ width: frameBox.w, height: frameBox.h }}
          >
            <div
              className="relative origin-top-left"
              style={{ width: nat.w, height: nat.h, transform: `scale(${scale})` }}
            >
              {(["admin", "mobile"] as Surface[]).map((s) => {
                if (!mounted[s]) return null;
                const active = s === surface;
                return (
                  <div
                    key={s}
                    hidden={!active}
                    className="absolute inset-0"
                    style={{ width: naturalSize(s).w, height: naturalSize(s).h }}
                  >
                    {s === "admin" && (
                      <div
                        className="flex items-center gap-2 rounded-t-[12px] bg-[#1A1A1D] px-4"
                        style={{ height: CHROME_H }}
                      >
                        <span className="flex gap-1.5">
                          <span className="h-3 w-3 rounded-full bg-white/20" />
                          <span className="h-3 w-3 rounded-full bg-white/20" />
                          <span className="h-3 w-3 rounded-full bg-white/20" />
                        </span>
                        <span className="ml-3 rounded-md bg-white/[0.06] px-3 py-1 text-xs text-[#8A8A85]">
                          app.nirman.in
                        </span>
                      </div>
                    )}
                    <iframe
                      ref={(el) => {
                        iframes.current[s] = el;
                      }}
                      onLoad={() => markReady(s)}
                      src={SRC[s]}
                      title={
                        s === "admin"
                          ? "Nirman admin dashboard — interactive demo"
                          : "Nirman field app — interactive demo"
                      }
                      className={
                        "block border-0 bg-transparent " +
                        (s === "admin"
                          ? "rounded-b-[12px] shadow-[0_40px_120px_rgba(0,0,0,0.6)]"
                          : "")
                      }
                      style={{ width: LOGICAL[s].w, height: LOGICAL[s].h }}
                    />
                    {/* highlight ring — full-frame pulse on navigate */}
                    {active && activeFeature && (
                      <span
                        key={pulseKey}
                        aria-hidden
                        className="pointer-events-none absolute inset-0 rounded-[12px] motion-safe:animate-[demo-ring_0.5s_cubic-bezier(0.16,1,0.3,1)]"
                        style={{
                          top: s === "admin" ? CHROME_H : 0,
                          boxShadow: "0 0 0 2px #C9A354, 0 0 24px rgba(201,163,84,0.35)",
                        }}
                      />
                    )}
                    {/* first-visit pulse */}
                    {active && showPulse && (
                      <span
                        aria-hidden
                        className="pointer-events-none absolute inset-x-0 bottom-6 flex justify-center"
                        style={{ top: s === "admin" ? CHROME_H : 0 }}
                      >
                        <span className="self-end rounded-full bg-[#0D0D0F]/85 px-4 py-2 text-sm text-[#F6F3EC] motion-safe:animate-pulse">
                          Try clicking anything ↑
                        </span>
                      </span>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          {present && (
            <div className="absolute bottom-4 right-4 z-20 flex items-center gap-2">
              <button
                onClick={() => switchSurface(surface === "admin" ? "mobile" : "admin")}
                className="rounded-lg border border-white/[0.14] bg-[#0D0D0F]/80 px-3 py-2 text-sm text-[#F6F3EC] outline-none hover:border-[#C9A354]"
              >
                {surface === "admin" ? "→ Field app" : "→ Admin"}
              </button>
              <button
                onClick={togglePresent}
                className="rounded-lg border border-white/[0.14] bg-[#0D0D0F]/80 px-3 py-2 text-sm text-[#F6F3EC] outline-none hover:border-[#C9A354]"
              >
                Exit
              </button>
            </div>
          )}
        </div>

        {/* checklist rail */}
        {!present && (
          <aside className="w-full shrink-0 border-t border-white/[0.08] bg-[#0D0D0F] p-5 lg:w-[340px] lg:border-l lg:border-t-0">
            <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[#C9A354]">
              {surface === "admin" ? "Admin highlights" : "Field-app highlights"}
            </p>
            {/* progress meter */}
            <div className="mt-3 flex items-center gap-3">
              <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/[0.08]">
                <div
                  className="h-full rounded-full bg-[#C9A354] transition-all"
                  style={{ width: `${(visitedCount / total) * 100}%` }}
                />
              </div>
              <span className="text-xs text-[#8A8A85]">
                {visitedCount} of {total}
              </span>
            </div>

            <ul className="mt-4 space-y-1.5">
              {features.map((f) => {
                const isVisited = visited[surface].has(f.key);
                const isActive = activeFeature === f.key;
                return (
                  <li key={f.key}>
                    <button
                      onClick={() => onFeature(f.key)}
                      aria-current={isActive ? "true" : undefined}
                      aria-label={`${f.label}${isVisited ? ", visited" : ""}`}
                      disabled={!ready[surface]}
                      aria-disabled={!ready[surface]}
                      className={
                        "flex w-full items-start gap-3 rounded-xl border-l-2 px-3 py-2.5 text-left outline-none transition-colors focus-visible:ring-2 focus-visible:ring-[#E0C079] disabled:cursor-default " +
                        (isActive
                          ? "border-[#C9A354] bg-[#C9A354]/[0.14]"
                          : "border-transparent hover:bg-[#131316]")
                      }
                    >
                      <span className="mt-0.5 shrink-0" aria-hidden>
                        {isVisited ? (
                          <span className="flex h-4 w-4 items-center justify-center rounded-full bg-[#2F7D4F] text-[10px] text-white">
                            ✓
                          </span>
                        ) : (
                          <span
                            className={
                              "block h-4 w-4 rounded-full border-2 " +
                              (isActive ? "border-[#C9A354]" : "border-white/25")
                            }
                          />
                        )}
                      </span>
                      <span>
                        <span className="block text-sm font-semibold text-[#F6F3EC]">{f.label}</span>
                        <span className={"block text-xs " + (isActive ? "text-[#C7C7C2]" : "text-[#8A8A85]")}>
                          {f.blurb}
                        </span>
                      </span>
                    </button>
                  </li>
                );
              })}
            </ul>

            <p className="mt-4 text-xs text-[#8A8A85]">
              Pick a feature, or click around the demo freely — everything is live.
            </p>

            {/* completion CTA — non-dismissible once the tour is ~complete */}
            {tourComplete && (
              <div className="mt-5 rounded-2xl border border-white/[0.08] border-t-2 border-t-[#C9A354] bg-[#131316] p-4">
                <p className="text-sm font-semibold text-[#F6F3EC]">You&apos;ve seen the core.</p>
                <p className="mt-1 text-xs text-[#8A8A85]">
                  Put Nirman in your team&apos;s hands — no register, one pipeline.
                </p>
                <div className="mt-3 flex gap-2">
                  <Link
                    href="/#pricing"
                    className="flex-1 rounded-lg bg-[#C9A354] px-3 py-2 text-center text-sm font-semibold text-[#0D0D0F] transition-colors hover:bg-[#E0C079]"
                  >
                    Start free
                  </Link>
                  <Link
                    href="/#pricing"
                    className="flex-1 rounded-lg border border-white/[0.14] px-3 py-2 text-center text-sm font-semibold text-[#F6F3EC] transition-colors hover:border-[#C9A354]"
                  >
                    Book a walkthrough
                  </Link>
                </div>
              </div>
            )}
          </aside>
        )}
      </div>

      {/* dismissible banner — secondary ask */}
      {!present && !bannerDismissed && !tourComplete && (
        <div className="flex items-center gap-3 border-t border-t-[#C9A354]/40 bg-[#0D0D0F] px-4 py-3 sm:px-6">
          <p className="text-sm text-[#C7C7C2]">Like what you see?</p>
          <Link
            href="/#pricing"
            className="rounded-lg bg-[#C9A354] px-4 py-1.5 text-sm font-semibold text-[#0D0D0F] transition-colors hover:bg-[#E0C079]"
          >
            Start free
          </Link>
          <button
            onClick={() => setBannerDismissed(true)}
            aria-label="Dismiss"
            className="ml-auto text-[#8A8A85] outline-none hover:text-white focus-visible:ring-2 focus-visible:ring-[#E0C079]"
          >
            ✕
          </button>
        </div>
      )}
    </div>
  );
}
