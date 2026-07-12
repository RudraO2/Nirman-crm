import Link from "next/link";
import { Logo } from "@/components/luminous/logo";

// Shared shell for /privacy and /terms — same dark Luminous look as the
// landing page, no landing sections. Content stays in the page files.
export function LegalPage({
  title,
  sections,
}: {
  title: string;
  sections: [string, string][];
}) {
  return (
    <div className="min-h-screen bg-[#050505] text-neutral-300">
      <div className="mx-auto max-w-3xl px-6 py-16">
        <Link href="/" className="inline-block">
          <Logo />
        </Link>
        <h1 className="mt-10 font-display text-4xl font-light tracking-tight text-white">
          {title}
        </h1>
        <p className="mt-2 text-sm text-neutral-500">Last updated: 12 July 2026</p>

        <div className="mt-10 space-y-8">
          {sections.map(([heading, body]) => (
            <section key={heading}>
              <h2 className="text-lg font-medium text-white">{heading}</h2>
              <p className="mt-2 leading-relaxed text-neutral-400">{body}</p>
            </section>
          ))}
        </div>

        <p className="mt-14 border-t border-white/10 pt-6 text-sm text-neutral-500">
          © {new Date().getFullYear()} Nirman Media ·{" "}
          <Link href="/" className="hover:text-white">
            Back to home
          </Link>
        </p>
      </div>
    </div>
  );
}
