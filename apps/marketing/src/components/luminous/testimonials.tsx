"use client";

import { useState } from "react";
import { ArrowLeft, ArrowRight, Star } from "lucide-react";

const slides = [
  {
    quote:
      "We went from posting on a whim to a system that never sleeps. Luminous tripled our reach in a single quarter, and I stopped dreading the content calendar.",
    author: "Maya Okonkwo",
    role: "Founder, Studio Halo",
    image:
      "https://hoirqrkdgbmvpwutwuwj.supabase.co/storage/v1/object/public/assets/assets/649a17f7-ce90-412e-bc8c-6227953b3ba4_1600w.webp",
  },
  {
    quote:
      "The AI reads the room better than most humans. Our reply game is instant, on-brand, and completely hands-off. It feels like an unfair advantage.",
    author: "Daniel Rivera",
    role: "Head of Growth, Northwind",
    image: "https://images.unsplash.com/photo-1640906152676-dace6710d24b?w=2160&q=80",
  },
  {
    quote:
      "As an agency we manage forty accounts. Luminous is the only reason that number isn't a nightmare. Every client thinks they have a dedicated team.",
    author: "Priya Anand",
    role: "Director, Lumen Collective",
    image: "https://images.unsplash.com/photo-1629946832022-c327f74956e0?w=2160&q=80",
  },
];

export function Testimonials() {
  const [i, setI] = useState(0);
  const [fading, setFading] = useState(false);

  const go = (next: number) => {
    setFading(true);
    setTimeout(() => {
      setI((next + slides.length) % slides.length);
      setFading(false);
    }, 300);
  };

  const s = slides[i];
  const fade = fading ? "opacity-0" : "opacity-100";

  return (
    <section id="testimonials" className="relative mx-auto max-w-7xl px-6 py-24">
      <div className="animate-on-scroll flex items-end justify-between">
        <div>
          <span className="font-display text-8xl font-light text-white/5">02.</span>
          <h2 className="-mt-6 font-display text-4xl font-light tracking-tight text-white sm:text-5xl">
            Loved by operators
          </h2>
        </div>
        <div className="hidden gap-2 sm:flex">
          <button
            onClick={() => go(i - 1)}
            aria-label="Previous testimonial"
            className="flex h-11 w-11 items-center justify-center rounded-full border border-white/10 text-neutral-300 transition-colors hover:border-amber-500/50 hover:text-white"
          >
            <ArrowLeft className="h-4 w-4" />
          </button>
          <button
            onClick={() => go(i + 1)}
            aria-label="Next testimonial"
            className="flex h-11 w-11 items-center justify-center rounded-full border border-white/10 text-neutral-300 transition-colors hover:border-amber-500/50 hover:text-white"
          >
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </div>

      <div className="animate-on-scroll mt-10 grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Text card */}
        <div className="flex flex-col justify-between rounded-[24px] border border-white/10 bg-neutral-900/60 p-8 backdrop-blur-sm sm:p-10">
          <div>
            <div className="flex gap-1 text-amber-400">
              {Array.from({ length: 5 }).map((_, k) => (
                <Star key={k} className="h-4 w-4 fill-amber-400" />
              ))}
            </div>
            <blockquote
              className={`t-quote mt-6 font-display text-2xl font-light leading-snug text-white transition-opacity duration-300 sm:text-3xl ${fade}`}
            >
              “{s.quote}”
            </blockquote>
          </div>
          <div className={`t-meta mt-8 transition-opacity duration-300 ${fade}`}>
            <p className="t-author font-medium text-white">{s.author}</p>
            <p className="t-role text-sm text-neutral-400">{s.role}</p>
          </div>
        </div>

        {/* Image card */}
        <div className="relative h-[600px] overflow-hidden rounded-[24px] border border-white/10">
          <img
            src={s.image}
            alt={s.author}
            className={`t-image h-full w-full object-cover transition-opacity duration-300 ${fade}`}
          />
          <div className="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent" />
          <span className="absolute left-5 top-5 inline-flex items-center gap-2 rounded-full border border-white/15 bg-black/40 px-3 py-1.5 text-xs font-medium text-white backdrop-blur-md">
            <span className="h-1.5 w-1.5 animate-livepulse rounded-full bg-amber-400" />
            Active Creator
          </span>
        </div>
      </div>
    </section>
  );
}
