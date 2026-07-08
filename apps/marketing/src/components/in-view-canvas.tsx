"use client";

import { useEffect, useRef, useState } from "react";

interface InViewCanvasProps {
  children: React.ReactNode;
  rootMargin?: string;
}

/**
 * Wraps a decorative WebGL background (react-bits Beams, etc). Mounts it only
 * while the section is near the viewport and never mounts it at all for
 * prefers-reduced-motion — these canvases run a permanent render loop, which
 * is otherwise a battery/thermal cost on mobile even when scrolled off-screen.
 */
export function InViewCanvas({ children, rootMargin = "200px 0px" }: InViewCanvasProps) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  const [reducedMotion, setReducedMotion] = useState(false);

  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReducedMotion(media.matches);
    const onChange = () => setReducedMotion(media.matches);
    media.addEventListener("change", onChange);
    return () => media.removeEventListener("change", onChange);
  }, []);

  useEffect(() => {
    const el = ref.current;
    if (!el || reducedMotion) return;
    const observer = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting), { rootMargin });
    observer.observe(el);
    return () => observer.disconnect();
  }, [rootMargin, reducedMotion]);

  return (
    <div ref={ref} className="absolute inset-0">
      {!reducedMotion && visible ? children : null}
    </div>
  );
}
