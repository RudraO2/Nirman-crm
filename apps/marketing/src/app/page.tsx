import { Background } from "@/components/luminous/background";
import { Nav } from "@/components/luminous/nav";
import { Hero } from "@/components/luminous/hero";
import { Dashboard } from "@/components/luminous/dashboard";
import { Testimonials } from "@/components/luminous/testimonials";
import { Pricing } from "@/components/luminous/pricing";
import { Footer } from "@/components/luminous/footer";
import { ScrollRevealController } from "@/components/luminous/reveal";

export default function Home() {
  return (
    <>
      <Background />
      <ScrollRevealController />
      <div className="relative z-10">
        <Nav />
        <main>
          <Hero />
          <Dashboard />
          <Testimonials />
          <Pricing />
        </main>
        <Footer />
      </div>
    </>
  );
}
