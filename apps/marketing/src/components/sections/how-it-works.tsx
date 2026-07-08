const steps = [
  {
    n: "01",
    title: "Capture",
    body: "Walk-in, referral, ad, associate. Every lead enters through one quick-capture form. Duplicate numbers are caught before they're saved.",
  },
  {
    n: "02",
    title: "Track",
    body: "Status moves the lead forward: Hot, Warm, Cold, Dead, Sold. Every call and remark writes itself to an automatic timeline.",
  },
  {
    n: "03",
    title: "Close",
    body: "Follow-up reminders chase the date, not your team's memory. When it's Sold, everyone sees it. No separate victory lap needed.",
  },
];

export function HowItWorks() {
  return (
    <section id="how-it-works" className="border-y border-line bg-paper py-24 sm:py-32">
      <div className="mx-auto max-w-5xl px-6">
        <div className="mx-auto max-w-xl text-center">
          <p className="eyebrow mb-4">How it works</p>
          <h2 className="font-serif text-3xl text-ink sm:text-4xl">Three steps. That&apos;s the entire training.</h2>
        </div>

        <div className="mt-16 grid grid-cols-1 gap-10 sm:grid-cols-3 sm:gap-8">
          {steps.map((step) => (
            <div key={step.n}>
              <span className="font-mono text-sm text-brass">{step.n}</span>
              <h3 className="mt-2 font-serif text-2xl text-ink">{step.title}</h3>
              <p className="mt-3 text-sm leading-relaxed text-ink-2">{step.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
