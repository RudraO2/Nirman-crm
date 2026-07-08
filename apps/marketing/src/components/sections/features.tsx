import { Phone, Bell, Copy, Download, Smartphone, Lock } from "lucide-react";

const features = [
  {
    icon: Phone,
    title: "Click-to-call",
    body: "Tap the number, call goes out, timeline logs itself. No dialing, no forgetting to note it down.",
  },
  {
    icon: Bell,
    title: "Follow-up reminders",
    body: "Set the next visit date once. Nirman CRM chases the reminder, not your memory.",
  },
  {
    icon: Copy,
    title: "Duplicate lead prevention",
    body: "Same phone number, normalized and checked automatically. Two employees can't chase one lead.",
  },
  {
    icon: Download,
    title: "One-tap Excel export",
    body: "For the accountant, the partner, the bank: a clean sheet whenever it's asked for.",
  },
  {
    icon: Smartphone,
    title: "Built for the field",
    body: "Your sales team lives on their phone. So does the CRM, not a shrunk-down desktop site.",
  },
  {
    icon: Lock,
    title: "Screenshot-blocked leads",
    body: "Client data stays inside the app. An employee who leaves doesn't leave with your leads.",
  },
];

export function Features() {
  return (
    <section className="bg-ivory py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-6">
        <div className="mx-auto max-w-xl text-center">
          <p className="eyebrow mb-4">Everything, minus the clutter</p>
          <h2 className="font-serif text-3xl text-ink sm:text-4xl">
            Fewer screens. <span className="italic">Same job, done properly.</span>
          </h2>
        </div>

        <div className="mt-14 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {features.map(({ icon: Icon, title, body }) => (
            <div key={title} className="h-full rounded-2xl border border-line bg-paper p-6">
              <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-brass-soft">
                <Icon className="h-5 w-5 text-brass-deep" strokeWidth={1.75} aria-hidden />
              </div>
              <h3 className="mt-4 font-serif text-lg text-ink">{title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-ink-2">{body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
