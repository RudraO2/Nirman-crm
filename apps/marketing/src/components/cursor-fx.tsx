"use client";

import { useEffect, useState } from "react";
import TargetCursor from "@/components/TargetCursor";

/**
 * Mounts the react-bits TargetCursor only where it belongs: fine-pointer
 * (desktop/mouse) devices that haven't asked for reduced motion. On touch it
 * would hide the native cursor for no benefit, so we skip it entirely.
 */
export function CursorFX() {
  const [enabled, setEnabled] = useState(false);

  useEffect(() => {
    const finePointer = window.matchMedia("(pointer: fine)").matches;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    setEnabled(finePointer && !reduced);
  }, []);

  if (!enabled) return null;

  return (
    <TargetCursor
      targetSelector=".cursor-target"
      spinDuration={3}
      cursorColor="#C9A354"
      hideDefaultCursor={false}
    />
  );
}
