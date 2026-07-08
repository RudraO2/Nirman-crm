const stats = [
  { value: "1", label: "pipeline for every lead — not a stage-builder to configure" },
  { value: "5", label: "statuses replace a drawer full of colour-coded sticky notes" },
  { value: "0", label: "spreadsheets left once your team is on Nirman CRM" },
];

export function Stats() {
  return (
    <section className="bg-evergreen-3 py-20">
      <div className="mx-auto grid max-w-5xl grid-cols-1 gap-10 px-6 sm:grid-cols-3 sm:gap-6">
        {stats.map((stat) => (
          <div key={stat.label} className="text-center">
            <div className="font-mono text-5xl font-medium tabular-nums text-brass-bright sm:text-6xl">
              {stat.value}
            </div>
            <p className="mx-auto mt-3 max-w-[22ch] text-sm text-ivory/60">{stat.label}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
