import { Logo } from "@/components/luminous/logo";
import { DemoForm } from "@/components/luminous/demo-form";

// Every link points at a destination that actually exists (audit medium: the
// old columns were all dead #top anchors). Sections: #platform #testimonials
// #pricing; pages: /privacy /terms.
const columns = [
  {
    title: "Product",
    links: [
      { label: "The Console", href: "#platform" },
      { label: "Builders", href: "#testimonials" },
      { label: "Pricing", href: "#pricing" },
    ],
  },
  {
    title: "Company",
    links: [
      { label: "Book a demo", href: "#book-demo" },
      { label: "Privacy", href: "/privacy" },
      { label: "Terms", href: "/terms" },
    ],
  },
];

export function Footer() {
  return (
    <footer id="footer" className="relative isolate mt-24 overflow-hidden">
      {/* Served from our own public/ (audit medium: was hotlinked from an
          unrelated third-party Supabase bucket that could vanish any day). */}
      <img
        src="/footer-bg.jpg"
        alt=""
        aria-hidden
        className="absolute inset-0 -z-10 h-full w-full object-cover"
      />
      <div className="absolute inset-0 -z-10 bg-black/80" aria-hidden />

      <div className="mx-auto max-w-7xl px-6 py-20">
        {/* Demo request */}
        <div id="book-demo" className="mx-auto max-w-xl text-center">
          <h2 className="font-display text-3xl font-light tracking-tight text-white sm:text-4xl">
            Retire the register.
          </h2>
          <p className="mt-3 text-neutral-400">
            Tell us where to reach you and we&apos;ll set up a live walkthrough for your sales floor.
          </p>
          <DemoForm />
        </div>

        {/* Link columns */}
        <div className="mt-16 grid grid-cols-2 gap-10 border-t border-white/10 pt-12 sm:grid-cols-3">
          {columns.map((col) => (
            <div key={col.title}>
              <p className="text-sm font-medium text-white">{col.title}</p>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((link) => (
                  <li key={link.label}>
                    <a href={link.href} className="text-sm text-neutral-400 transition-colors hover:text-white">
                      {link.label}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}

          <div className="col-span-2 sm:col-span-1">
            <Logo />
            <p className="mt-4 max-w-xs text-sm text-neutral-400">
              The real-estate CRM for builders and their sales teams. One pipeline, on web and mobile.
            </p>
          </div>
        </div>

        <div className="mt-12 flex flex-col items-center justify-between gap-3 border-t border-white/10 pt-8 text-sm text-neutral-500 sm:flex-row">
          <p>© {new Date().getFullYear()} Nirman Media. All rights reserved.</p>
          <div className="flex gap-6">
            <a href="/privacy" className="transition-colors hover:text-white">Privacy</a>
            <a href="/terms" className="transition-colors hover:text-white">Terms</a>
          </div>
        </div>
      </div>
    </footer>
  );
}
