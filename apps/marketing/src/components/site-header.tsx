import { Button } from "@/components/button";

export function SiteHeader() {
  return (
    <header className="fixed inset-x-4 top-4 z-50 mx-auto flex max-w-6xl items-center justify-between rounded-2xl border border-white/10 bg-evergreen-3/70 px-5 py-3 shadow-lg backdrop-blur-md sm:inset-x-6 md:inset-x-8">
      <a href="#top" className="flex items-baseline gap-1.5">
        <span className="font-serif text-xl italic text-ivory">Nirman</span>
        <span className="font-mono text-[11px] font-medium tracking-[0.14em] text-brass-bright uppercase">
          CRM
        </span>
      </a>

      <nav className="hidden items-center gap-8 md:flex">
        <a href="#pain" className="text-sm text-ivory/70 transition-colors hover:text-ivory">
          Why we built this
        </a>
        <a href="#product" className="text-sm text-ivory/70 transition-colors hover:text-ivory">
          Product
        </a>
        <a href="#how-it-works" className="text-sm text-ivory/70 transition-colors hover:text-ivory">
          How it works
        </a>
      </nav>

      <Button href="#contact" variant="on-dark" className="min-h-11 px-4 py-2.5 text-sm">
        Book a demo
      </Button>
    </header>
  );
}
