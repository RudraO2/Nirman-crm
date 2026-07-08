const pains = [
  {
    label: "The register",
    note: "Handwritten, one copy, in a drawer. If it's lost, so is the lead.",
    rotate: "-rotate-3",
  },
  {
    label: "leads_final_v3.xlsx",
    note: "Three people editing three versions. Nobody knows which one is real.",
    rotate: "rotate-2",
  },
  {
    label: "Missed follow-up",
    note: "No reminder. The client bought from someone who called back.",
    rotate: "rotate-[-6deg]",
  },
  {
    label: "“Wait, who has this lead?”",
    note: "Same number, called twice by two employees, same week.",
    rotate: "rotate-[5deg]",
  },
];

export function PainPoints() {
  return (
    <section id="pain" className="relative overflow-hidden border-b border-line bg-ivory py-24 sm:py-32">
      <div className="mx-auto max-w-5xl px-6">
        <div className="mx-auto max-w-xl text-center">
          <p className="eyebrow mb-4">Sound familiar?</p>
          <h2 className="font-serif text-3xl italic text-ink sm:text-4xl">
            This is what &ldquo;managing leads&rdquo; looks like for most builders.
          </h2>
        </div>

        <div className="relative mx-auto mt-16 grid max-w-3xl grid-cols-1 gap-6 sm:grid-cols-2">
          {pains.map((pain, i) => (
            <div
              key={pain.label}
              className={`${pain.rotate} rounded-lg border border-line-2 bg-paper p-5 shadow-[var(--shadow)] transition-transform duration-300 hover:rotate-0`}
            >
              <p className="font-mono text-xs tracking-tight text-ink-3">Note {i + 1}</p>
              <p className="mt-1 font-serif text-lg text-ink">{pain.label}</p>
              <p className="mt-2 text-sm text-ink-2">{pain.note}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
