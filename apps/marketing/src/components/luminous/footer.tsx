import { Phone, Mail, MessageCircle } from "lucide-react";
import { Logo } from "@/components/luminous/logo";

const columns = [
  { title: "Product", links: ["The Console", "Leads", "Inventory", "Insights"] },
  { title: "For teams", links: ["Builders / Admins", "Sales agents", "Mobile app", "Security"] },
  { title: "Company", links: ["Nirman Media", "Contact", "Privacy", "Terms"] },
];

export function Footer() {
  return (
    <footer id="footer" className="relative isolate mt-24 overflow-hidden">
      <img
        src="https://hoirqrkdgbmvpwutwuwj.supabase.co/storage/v1/object/public/assets/assets/f5347579-34d0-43b9-99d3-126f6193d19d_1600w.jpg"
        alt=""
        aria-hidden
        className="absolute inset-0 -z-10 h-full w-full object-cover"
      />
      <div className="absolute inset-0 -z-10 bg-black/80" aria-hidden />

      <div className="mx-auto max-w-7xl px-6 py-20">
        {/* Demo request */}
        <div className="mx-auto max-w-xl text-center">
          <h2 className="font-display text-3xl font-light tracking-tight text-white sm:text-4xl">
            Retire the register.
          </h2>
          <p className="mt-3 text-neutral-400">
            Tell us where to reach you and we&apos;ll set up a live walkthrough for your sales floor.
          </p>
          <form className="mx-auto mt-6 flex max-w-md gap-2">
            <input
              type="email"
              placeholder="you@yourbuild.com"
              className="h-10 flex-1 rounded-full border border-white/15 bg-white/5 px-4 text-sm text-white placeholder:text-neutral-500 focus:border-amber-500/50 focus:outline-none"
            />
            <button
              type="submit"
              className="h-10 rounded-full bg-white px-5 text-sm font-semibold text-black transition-transform hover:scale-[1.03]"
            >
              Book a demo
            </button>
          </form>
        </div>

        {/* Link columns */}
        <div className="mt-16 grid grid-cols-2 gap-10 border-t border-white/10 pt-12 sm:grid-cols-3 lg:grid-cols-4">
          {columns.map((col) => (
            <div key={col.title}>
              <p className="text-sm font-medium text-white">{col.title}</p>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((link) => (
                  <li key={link}>
                    <a href="#top" className="text-sm text-neutral-400 transition-colors hover:text-white">
                      {link}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          ))}

          <div className="col-span-2 sm:col-span-3 lg:col-span-1">
            <Logo />
            <p className="mt-4 max-w-xs text-sm text-neutral-400">
              The real-estate CRM for builders and their sales teams. One pipeline, on web and mobile.
            </p>
            <div className="mt-5 flex gap-3">
              {[Phone, Mail, MessageCircle].map((Icon, i) => (
                <a
                  key={i}
                  href="#top"
                  className="flex h-9 w-9 items-center justify-center rounded-full border border-white/10 text-neutral-300 transition-colors hover:border-amber-500/50 hover:text-white"
                >
                  <Icon className="h-4 w-4" />
                </a>
              ))}
            </div>
          </div>
        </div>

        <div className="mt-12 flex flex-col items-center justify-between gap-3 border-t border-white/10 pt-8 text-sm text-neutral-500 sm:flex-row">
          <p>© {new Date().getFullYear()} Nirman Media. All rights reserved.</p>
          <div className="flex gap-6">
            <a href="#top" className="transition-colors hover:text-white">Privacy</a>
            <a href="#top" className="transition-colors hover:text-white">Terms</a>
          </div>
        </div>
      </div>
    </footer>
  );
}
