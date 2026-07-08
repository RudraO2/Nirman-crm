import { Button } from "@/components/button";

export function Hero() {
  return (
    <section id="top" className="relative isolate overflow-hidden bg-evergreen-3 pt-40 pb-28 sm:pt-48 sm:pb-36">
      <div className="relative mx-auto max-w-4xl px-6 text-center">
        <p className="eyebrow mb-7 text-brass-bright">Real estate CRM · built by Nirman Media</p>

        <h1 className="font-serif text-[2.4rem] leading-[1.1] text-ivory sm:text-6xl sm:leading-[1.05]">
          <span className="block text-2xl text-ivory/55 sm:text-3xl">
            Still tracking leads on paper and scattered spreadsheets?
          </span>
          <span className="mt-4 block italic">Now it&apos;s just one pipeline.</span>
        </h1>

        <p className="mx-auto mt-7 max-w-xl text-balance text-lg text-ivory/65">
          Nirman CRM replaces the paper register and the scattered Excel sheets with one
          simple screen your sales team already knows how to use: status, follow-up, call.
        </p>

        <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
          <Button href="#contact" variant="primary">
            Book a live demo
          </Button>
          <Button href="#product" variant="ghost-on-dark">
            See the pipeline
          </Button>
        </div>
      </div>
    </section>
  );
}
