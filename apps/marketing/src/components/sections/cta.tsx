import { Button } from "@/components/button";

export function Cta() {
  return (
    <section id="contact" className="relative isolate overflow-hidden bg-evergreen-3 py-28">
      <div className="relative mx-auto max-w-2xl px-6 text-center">
        <h2 className="font-serif text-3xl text-ivory sm:text-4xl">
          Ready to close the register for good?{" "}
          <span className="italic">See it live.</span>
        </h2>
        <p className="mx-auto mt-5 max-w-md text-balance text-ivory/65">
          A 20-minute walkthrough with your own leads. No slides, no sales script — just the pipeline.
        </p>
        <div className="mt-9 flex flex-wrap items-center justify-center gap-4">
          <Button href="mailto:hello@nirmanmedia.com?subject=Nirman%20CRM%20demo" variant="primary">
            Email hello@nirmanmedia.com
          </Button>
        </div>
      </div>
    </section>
  );
}
