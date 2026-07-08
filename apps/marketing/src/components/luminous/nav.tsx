import { Logo } from "@/components/luminous/logo";

const links = [
  { label: "Home", href: "#top", active: true },
  { label: "The Console", href: "#platform" },
  { label: "Builders", href: "#testimonials" },
  { label: "Pricing", href: "#pricing" },
  { label: "Contact", href: "#footer" },
];

export function Nav() {
  return (
    <nav className="relative z-50 mx-auto flex max-w-7xl items-center justify-between px-6 py-6">
      <Logo />

      <div className="hidden items-center gap-1 rounded-full border border-white/10 bg-white/5 px-1.5 py-1.5 backdrop-blur-md md:flex">
        {links.map((link) => (
          <a
            key={link.label}
            href={link.href}
            className={
              link.active
                ? "flex items-center gap-2 rounded-full bg-neutral-800/80 px-4 py-1.5 text-sm text-white shadow-inner"
                : "rounded-full px-4 py-1.5 text-sm text-neutral-400 transition-colors hover:text-white"
            }
          >
            {link.active && <span className="h-1.5 w-1.5 rounded-full bg-amber-500" />}
            {link.label}
          </a>
        ))}
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
