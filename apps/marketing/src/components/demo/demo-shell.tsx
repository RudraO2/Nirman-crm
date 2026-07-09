"use client";

/* Nirman /demo — product-native interactive demo.
   Spec: _bmad-output/planning-artifacts/ux-designs/ux-CRM-LMS-2026-07-09/{DESIGN,EXPERIENCE}.md
   Evergreen product-themed stage frames the light product (iframed, same-origin).
   No side rail — features are explained by in-context hotspots that live INSIDE the
   demo HTML; the shell just toggles them. Admin gets shell-drawn browser chrome; the
   mobile HTML owns its own bezel. */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";

type Surface = "admin" | "mobile";

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
const HOME_SLUG: Record<Surface, string> = { admin: "home", mobile: "home" };
const ALL_SLUGS: Record<Surface, string[]> = {
  admin: ["home", "leads", "insights", "team", "inventory", "data"],
  mobile: ["home", "outcome", "detail", "plan", "alarms", "you"],
};

function naturalSize(s: Surface) {
  return { w: LOGICAL[s].w, h: LOGICAL[s].h + (s === "admin" ? CHROME_H : 0) };
}

export function DemoShell() {
  const [surface, setSurface] = useState<Surface>("admin");
  const [mounted, setMounted] = useState<Record<Surface, boolean>>({ admin: true, mobile: false });
  const [, setReady] = useState<Record<Surface, boolean>>({ admin: false, mobile: false });
  const [hintsOn, setHintsOn] = useState(true);
  const [present, setPresent] = useState(false);
  const [announce, setAnnounce] = useState("");
  const [copied, setCopied] = useState(false);
  const [lastScreen, setLastScreen] = useState<string>("home");

  const stageRef = useRef<HTMLDivElement | null>(null);
  const iframes = useRef<Record<Surface, HTMLIFrameElement | null>>({ admin: null, mobile: null });
  const pending = useRef<Record<Surface, string | null>>({ admin: null, mobile: null });
  const [scale, setScale] = useState(1);

  // ── Responsive scale: fit the natural device into the stage ─────────────
  useEffect(() => {
    const el = stageRef.current;
    if (!el) return;
    const compute = () => {
      const pad = present ? 16 : 40;
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

  // ── Post a message to a surface's iframe (same-origin) ──────────────────
  const post = useCallback((s: Surface, msg: Record<string, unknown>) => {
    iframes.current[s]?.contentWindow?.postMessage(
      { source: "nirman-demo", ...msg },
      window.location.origin,
    );
  }, []);

  // Mark a surface ready (from `ready` message OR onLoad — onLoad is race-proof
  // for a same-origin iframe), flush queued navigate, and sync the hints state.
  const markReady = useCallback(
    (s: Surface) => {
      setReady((r) => (r[s] ? r : { ...r, [s]: true }));
      post(s, { action: "hints", on: hintsOn });
      const q = pending.current[s];
      if (q) {
        post(s, { action: "navigate", target: q });
        pending.current[s] = null;
      }
    },
    [post, hintsOn],
  );

  // ── postMessage listener (ready + navigated) ────────────────────────────
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
      } else if (d.event === "navigated" && d.screen && src === surface) {
        setLastScreen(d.screen);
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
    if (d === "admin" || d === "mobile") initial = d;
    else {
      const coarse =
        window.matchMedia?.("(pointer: coarse)").matches || window.innerWidth < 1024;
      initial = coarse ? "mobile" : "admin";
    }
    const slug = window.location.hash.replace(/^#/, "");
    if (slug && ALL_SLUGS[initial].includes(slug)) pending.current[initial] = slug;
    // One-time external(URL/device)→React init on mount; intentionally synchronous.
    /* eslint-disable react-hooks/set-state-in-effect */
    if (initial !== "admin") {
      setSurface(initial);
      setMounted((m) => ({ ...m, [initial]: true }));
    }
    /* eslint-enable react-hooks/set-state-in-effect */
  }, []);

  // ── Surface switch ──────────────────────────────────────────────────────
  const switchSurface = useCallback((s: Surface) => {
    setSurface(s);
    setMounted((m) => ({ ...m, [s]: true }));
    setLastScreen(HOME_SLUG[s]);
    const url = new URL(window.location.href);
    url.searchParams.set("d", s);
    url.hash = "";
    window.history.replaceState(null, "", url.toString());
    requestAnimationFrame(() => document.getElementById("demo-stage-region")?.focus());
  }, []);

  const toggleHints = useCallback(() => {
    setHintsOn((on) => {
      const next = !on;
      (["admin", "mobile"] as Surface[]).forEach((s) => post(s, { action: "hints", on: next }));
      setAnnounce(next ? "Feature highlights on" : "Feature highlights off");
      return next;
    });
  }, [post]);

  const copyLink = useCallback(() => {
    const url = new URL(window.location.href);
    url.searchParams.set("d", surface);
    if (lastScreen) url.hash = lastScreen;
    navigator.clipboard?.writeText(url.toString()).then(() => {
      setCopied(true);
      setAnnounce("Link to this view copied");
      setTimeout(() => setCopied(false), 2000);
    });
  }, [surface, lastScreen]);

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

  const nat = naturalSize(surface);
  const frameBox = useMemo(
    () => ({ w: Math.round(nat.w * scale), h: Math.round(nat.h * scale) }),
    [nat.w, nat.h, scale],
  );

  const btn =
    "rounded-lg border border-[#C9A354]/25 bg-white/[0.04] px-3 py-2 text-sm text-[#F6F3EC] outline-none transition-colors hover:border-[#C9A354] focus-visible:ring-2 focus-visible:ring-[#E0C079]";

  return (
    <div
      className="flex min-h-screen flex-col text-[#F6F3EC]"
      style={{ background: "radial-gradient(1200px 820px at 50% -12%, #1E3B2E, #0D1F18 62%, #081511)" }}
    >
      <div aria-live="polite" className="sr-only">
        {announce}
      </div>

      {/* ── Top bar ─────────────────────────────────────────────── */}
      {!present && (
        <header className="sticky top-0 z-30 flex flex-wrap items-center justify-between gap-3 border-b border-[#C9A354]/15 bg-[#0D1F18]/80 px-4 py-3 backdrop-blur-md sm:px-6">
          <Link
            href="/"
            className="flex items-center gap-2 rounded-lg px-2 py-1 text-sm text-[#E9E4D6]/80 outline-none transition-colors hover:text-white focus-visible:ring-2 focus-visible:ring-[#E0C079]"
          >
            <span aria-hidden>←</span> Nirman
          </Link>

          <div
            role="tablist"
            aria-label="Choose a demo surface"
            className="order-last flex w-full items-center justify-center gap-1 rounded-[10px] border border-[#C9A354]/20 bg-black/25 p-1 sm:order-none sm:w-auto"
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
                      (
                        e.currentTarget.parentElement?.querySelector(
                          `[role="tab"]:not([aria-selected="true"])`,
                        ) as HTMLElement | null
                      )?.focus();
                    }
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      switchSurface(s);
                    }
                  }}
                  className={
                    "relative rounded-[7px] px-4 py-1.5 text-sm font-medium outline-none transition-colors focus-visible:ring-2 focus-visible:ring-[#E0C079] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0D1F18] " +
                    (selected ? "bg-[#C9A354]/20 text-white" : "text-[#E9E4D6]/55 hover:text-[#E9E4D6]")
                  }
                >
                  {SURFACE_LABEL[s]}
                  {selected && (
                    <span className="absolute inset-x-3 -bottom-[5px] h-0.5 rounded-full bg-[#C9A354]" />
                  )}
                </button>
              );
            })}
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={toggleHints}
              aria-pressed={hintsOn}
              className={
                "hidden items-center gap-2 rounded-lg border px-3 py-2 text-sm outline-none transition-colors focus-visible:ring-2 focus-visible:ring-[#E0C079] sm:flex " +
                (hintsOn
                  ? "border-[#C9A354] bg-[#C9A354]/15 text-[#F6F3EC]"
                  : "border-[#C9A354]/25 bg-white/[0.04] text-[#E9E4D6]/70")
              }
            >
              <span className="h-1.5 w-1.5 rounded-full bg-[#C9A354]" />
              Highlights
            </button>
            <button onClick={copyLink} className={btn + " hidden md:block"}>
              {copied ? "Copied ✓" : "Copy link"}
            </button>
            <button onClick={togglePresent} className={btn + " hidden md:block"}>
              Present
            </button>
            <Link
              href="/#pricing"
              className="rounded-lg bg-[#C9A354] px-4 py-2 text-sm font-semibold text-[#0D1F18] outline-none transition-colors hover:bg-[#E0C079] focus-visible:ring-2 focus-visible:ring-[#E0C079] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0D1F18]"
            >
              Book a demo
            </Link>
          </div>
        </header>
      )}

      {/* ── Stage ───────────────────────────────────────────────── */}
      <div ref={stageRef} className="relative flex flex-1 items-center justify-center overflow-hidden p-6">
        {!present && (
          <div className="pointer-events-none absolute left-4 top-4 z-20 flex flex-col gap-2">
            <span className="inline-flex items-center gap-2 self-start rounded-full border border-[#C9A354]/25 bg-black/30 px-3 py-1 text-xs font-medium text-[#F6F3EC]">
              <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-[#3FBF6F]" />
              Live · interactive
            </span>
            {hintsOn && (
              <span className="self-start rounded-full bg-black/25 px-3 py-1 text-xs text-[#E9E4D6]/70">
                Tap the brass dots, or click anywhere — it&apos;s the real product
              </span>
            )}
          </div>
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
                      className="flex items-center gap-2 rounded-t-[12px] bg-[#0B1712] px-4"
                      style={{ height: CHROME_H }}
                    >
                      <span className="flex gap-1.5">
                        <span className="h-3 w-3 rounded-full bg-white/15" />
                        <span className="h-3 w-3 rounded-full bg-white/15" />
                        <span className="h-3 w-3 rounded-full bg-white/15" />
                      </span>
                      <span className="ml-3 rounded-md bg-white/[0.06] px-3 py-1 text-xs text-[#E9E4D6]/50">
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
                      (s === "admin" ? "rounded-b-[12px] shadow-[0_40px_120px_rgba(0,0,0,0.55)]" : "")
                    }
                    style={{ width: LOGICAL[s].w, height: LOGICAL[s].h }}
                  />
                </div>
              );
            })}
          </div>
        </div>

        {present && (
          <div className="absolute bottom-4 right-4 z-20 flex items-center gap-2">
            <button onClick={toggleHints} className={btn}>
              {hintsOn ? "Hide highlights" : "Show highlights"}
            </button>
            <button
              onClick={() => switchSurface(surface === "admin" ? "mobile" : "admin")}
              className={btn}
            >
              {surface === "admin" ? "→ Field app" : "→ Admin"}
            </button>
            <button onClick={togglePresent} className={btn}>
              Exit
            </button>
          </div>
        )}
      </div>

      {/* ── Slim conversion strip ───────────────────────────────── */}
      {!present && (
        <div className="flex flex-wrap items-center justify-center gap-3 border-t border-[#C9A354]/15 bg-[#0D1F18]/70 px-4 py-2.5 text-sm sm:px-6">
          <span className="text-[#E9E4D6]/70">This is the real Nirman CRM — like what you see?</span>
          <Link
            href="/#pricing"
            className="rounded-lg bg-[#C9A354] px-4 py-1.5 text-sm font-semibold text-[#0D1F18] transition-colors hover:bg-[#E0C079]"
          >
            Start free
          </Link>
          <Link
            href="/#pricing"
            className="rounded-lg border border-[#C9A354]/30 px-4 py-1.5 text-sm font-semibold text-[#F6F3EC] transition-colors hover:border-[#C9A354]"
          >
            Book a walkthrough
          </Link>
        </div>
      )}
    </div>
  );
}
