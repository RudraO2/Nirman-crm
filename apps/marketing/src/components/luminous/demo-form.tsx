"use client";

import { useState } from "react";

// Audit H10: this form used to be a dead <form> with no handler — every
// prospect who submitted lost their info silently. It now POSTs to the
// demo_requests table (0103) via plain PostgREST with the public anon key
// (write-only: anon has INSERT on email/source and nothing else).
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

type FormState = "idle" | "busy" | "done" | "error";

export function DemoForm() {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<FormState>("idle");

  const emailOk = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!emailOk || state === "busy") return;
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      // Env not wired on this deployment — fail loudly, never silently.
      setState("error");
      return;
    }
    setState("busy");
    try {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/demo_requests`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: SUPABASE_ANON_KEY,
          Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
          Prefer: "return=minimal",
        },
        body: JSON.stringify({ email: email.trim(), source: "marketing_footer" }),
      });
      setState(res.ok ? "done" : "error");
    } catch {
      setState("error");
    }
  }

  if (state === "done") {
    return (
      <p className="mx-auto mt-6 max-w-md rounded-full border border-amber-500/30 bg-amber-500/10 px-5 py-2.5 text-sm text-amber-200">
        Got it — we&apos;ll reach out within a day to set up your walkthrough.
      </p>
    );
  }

  return (
    <form className="mx-auto mt-6 max-w-md" onSubmit={submit} noValidate>
      <div className="flex gap-2">
        <input
          type="email"
          required
          value={email}
          onChange={(e) => {
            setEmail(e.target.value);
            if (state === "error") setState("idle");
          }}
          placeholder="you@yourbuild.com"
          aria-label="Work email"
          aria-invalid={email.length > 0 && !emailOk}
          className="h-10 flex-1 rounded-full border border-white/15 bg-white/5 px-4 text-sm text-white placeholder:text-neutral-500 focus:border-amber-500/50 focus:outline-none"
        />
        <button
          type="submit"
          disabled={state === "busy" || !emailOk}
          className="h-10 rounded-full bg-white px-5 text-sm font-semibold text-black transition-transform hover:scale-[1.03] disabled:opacity-60 disabled:hover:scale-100"
        >
          {state === "busy" ? "Sending…" : "Book a demo"}
        </button>
      </div>
      {state === "error" && (
        <p className="mt-2 text-xs text-red-400" role="alert">
          That didn&apos;t go through — please try again in a moment.
        </p>
      )}
    </form>
  );
}
