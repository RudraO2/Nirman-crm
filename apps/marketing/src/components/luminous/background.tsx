export function Background() {
  return (
    <div className="fixed inset-0 z-0 bg-[#050505]" aria-hidden>
      {/* Layer 1 — tiled radial star field (200x200), opacity 0.2 via .stars */}
      <div className="stars absolute inset-0" />
      {/* Layer 2 — top-center amber-900 blur, 800x500 */}
      <div className="absolute left-1/2 top-0 h-[500px] w-[800px] -translate-x-1/2 rounded-full bg-amber-900/40 blur-[120px]" />
      {/* Layer 3 — bottom-right amber-950 blur, 600x600 */}
      <div className="absolute bottom-0 right-0 h-[600px] w-[600px] translate-x-1/4 translate-y-1/4 rounded-full bg-amber-950/50 blur-[120px]" />
    </div>
  );
}
