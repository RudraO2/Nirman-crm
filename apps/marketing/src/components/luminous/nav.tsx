"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { Logo } from "@/components/luminous/logo";

// `section` drives the scroll-spy; route links (no section) never highlight.
const links = [
  { label: "Home", href: "#top", section: "top" },
  { label: "Live Demo", href: "/demo", section: null },
  { label: "The Console", href: "#platform", section: "platform" },
  { label: "Builders", href: "#testimonials", section: "testimonials" },
  { label: "Pricing", href: "#pricing", section: "pricing" },
  { label: "Contact", href: "#footer", section: "footer" },
];

export function Nav() {
  // Scroll-spy (audit low: "Home" was hardcoded active forever). Track the
  // section nearest the top of the viewport via IntersectionObserver.
  const [active, setActive] = useState("top");

  useEffect(() => {
    const visible = new Map<string, number>();
    const observer = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) visible.set(e.target.id, e.intersectionRatio);
          else visible.delete(e.target.id);
        }
        // Pick the section in view following the nav's own order, so the
        // highlight is stable when two sections straddle the viewport.
        for (const l of links) {
          if (l.section && visible.has(l.section)) {
            setActive(l.section);
            return;
          }
        }
      },
      { rootMargin: "-20% 0px -55% 0px", threshold: [0, 0.1, 0.5] },
    );
    for (const l of links) {
      if (!l.section) continue;
      const el = document.getElementById(l.section);
      if (el) observer.observe(el);
    }
    return () => observer.disconnect();
  }, []);

  return (
    <nav className="relative z-50 mx-auto flex max-w-7xl items-center justify-between px-6 py-6">
      <Logo />

      <div className="hidden items-center gap-1 rounded-full border border-white/10 bg-white/5 px-1.5 py-1.5 backdrop-blur-md md:flex">
        {links.map((link) => {
          const isActive = link.section !== null && active === link.section;
          return (
            <Link
              key={link.label}
              href={link.href}
              className={
                isActive
                  ? "flex items-center gap-2 rounded-full bg-neutral-800/80 px-4 py-1.5 text-sm text-white shadow-inner"
                  : "rounded-full px-4 py-1.5 text-sm text-neutral-400 transition-colors hover:text-white"
              }
            >
              {isActive && <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />}
              {link.label}
            </Link>
          );
        })}
      </div>

      <a
        href="#pricing"
        className="rounded-full bg-gradient-to-b from-amber-400 to-amber-600 px-5 py-2.5 text-sm font-medium text-white shadow-lg shadow-amber-500/20 transition-transform hover:scale-[1.03]"
      >
        Get Started
      </a>
    </nav>
  );
}
