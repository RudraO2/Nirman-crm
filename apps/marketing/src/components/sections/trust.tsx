import { ShieldCheck, KeyRound, EyeOff, Timer } from "lucide-react";

const points = [
  {
    icon: ShieldCheck,
    title: "Data isolation by design",
    body: "Row-level security at the database layer keeps every builder's leads separate, not just an app-level filter.",
  },
  {
    icon: KeyRound,
    title: "Encrypted client data",
    body: "Names and phone numbers are encrypted at rest. Your clients' details aren't sitting in plain text.",
  },
  {
    icon: EyeOff,
    title: "Screenshot-blocked on mobile",
    body: "Lead lists can't be screenshotted from the field app, one more way client data stays inside your business.",
  },
  {
    icon: Timer,
    title: "Reminders that actually fire",
    body: "Follow-up notifications run on a schedule your team can't forget to check.",
  },
];

export function Trust() {
  return (
    <section className="bg-mist py-24 sm:py-28">
      <div className="mx-auto max-w-5xl px-6">
        <div className="mx-auto max-w-xl text-center">
          <p className="eyebrow mb-4">Built for real client data</p>
          <h2 className="font-serif text-3xl text-ink sm:text-4xl">Simple for your team. Serious about the data.</h2>
        </div>

        <div className="mt-14 grid grid-cols-1 gap-x-8 gap-y-10 sm:grid-cols-2">
          {points.map(({ icon: Icon, title, body }) => (
            <div key={title} className="flex gap-4">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-evergreen/10">
                <Icon className="h-5 w-5 text-evergreen" strokeWidth={1.75} aria-hidden />
              </div>
              <div>
                <h3 className="font-serif text-lg text-ink">{title}</h3>
                <p className="mt-1.5 text-sm leading-relaxed text-ink-2">{body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
