"use client";

import { useEffect } from "react";

/**
 * Adds `.is-visible` to every `.animate-on-scroll` element as it enters the
 * viewport, driving the CSS reveal (translateY + blur -> settled). One shared
 * observer for the whole page. Mount once near the root.
 */
export function ScrollRevealController() {
  useEffect(() => {
    const els = Array.from(document.querySelectorAll<HTMLElement>(".animate-on-scroll"));
    if (!("IntersectionObserver" in window)) {
      els.forEach((el) => el.classList.add("is-visible"));
      return;
    }
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            io.unobserve(entry.target);
          }
        });
      },
      { rootMargin: "0px 0px -10% 0px", threshold: 0.1 }
    );
    els.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);

  return null;
}
