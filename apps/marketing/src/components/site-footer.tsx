export function SiteFooter() {
  return (
    <footer className="border-t border-white/10 bg-evergreen-3 py-10">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-6 text-sm text-ivory/50 sm:flex-row">
        <div className="flex items-baseline gap-1.5">
          <span className="font-serif italic text-ivory/80">Nirman</span>
          <span className="font-mono text-[10px] tracking-[0.14em] text-brass-bright uppercase">CRM</span>
        </div>
        <p>© {new Date().getFullYear()} Nirman Media. Built for real estate builders, by Nirman Media.</p>
      </div>
    </footer>
  );
}
