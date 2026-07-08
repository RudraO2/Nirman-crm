"use client";

import {
  LayoutDashboard,
  Users,
  Boxes,
  Building2,
  UsersRound,
  BarChart3,
  Filter,
  Search,
  Plus,
  Phone,
  Clock,
  Asterisk,
} from "lucide-react";
const STATUS: Record<string, { fg: string; bg: string }> = {
  Hot: { fg: "#C24638", bg: "#F9E9E6" },
  Warm: { fg: "#C07A17", bg: "#F7EDD9" },
  Cold: { fg: "#3E6DA6", bg: "#E6EDF6" },
  Dead: { fg: "#78817B", bg: "#ECEEEC" },
  Sold: { fg: "#2F7D4F", bg: "#E3F0E7" },
};

function Pill({ status }: { status: keyof typeof STATUS }) {
  const s = STATUS[status];
  return (
    <span
      className="rounded-full px-2.5 py-0.5 text-xs font-medium"
      style={{ color: s.fg, backgroundColor: s.bg }}
    >
      {status}
    </span>
  );
}

const leads = [
  { name: "Rohan Mehta", phone: "+91 98200 41288", project: "The Velocity · 2BHK", status: "Hot", follow: "Today, 4:00 PM", initials: "RM" },
  { name: "Aisha Khan", phone: "+91 99870 55123", project: "Skyline Grove · 3BHK", status: "Warm", follow: "Tomorrow, 11:00 AM", initials: "AK" },
  { name: "Vikram Rao", phone: "+91 90040 77219", project: "Plot · Whitefield", status: "Cold", follow: "Fri, 5:30 PM", initials: "VR" },
  { name: "Neha Sharma", phone: "+91 98111 90233", project: "The Velocity · 4BHK", status: "Sold", follow: "Closed", initials: "NS" },
] as const;

/** Faithful recreation of the Nirman admin dashboard — ivory brand theme. */
function AdminMock() {
  return (
    <div className="flex h-[560px] text-[13px]" style={{ background: "#F6F3EC", color: "#1C231F" }}>
      {/* Sidebar — evergreen */}
      <aside className="hidden w-56 shrink-0 flex-col p-4 sm:flex" style={{ background: "#132A21" }}>
        <div className="flex items-center gap-2 px-2 pb-6 pt-1">
          <span className="relative flex h-6 w-6 items-center justify-center">
            <Asterisk className="absolute h-6 w-6 rotate-45" style={{ color: "#F6F3EC" }} strokeWidth={2} />
            <Asterisk className="absolute h-6 w-6" style={{ color: "#C9A354" }} strokeWidth={1.5} />
          </span>
          <span className="text-[15px] font-medium italic" style={{ color: "#F6F3EC", fontFamily: "var(--font-display)" }}>
            Nirman
          </span>
        </div>

        <nav className="space-y-0.5">
          {[
            [LayoutDashboard, "Dashboard", true],
            [Users, "Leads", false],
            [Boxes, "Inventory", false],
            [Building2, "Projects", false],
            [UsersRound, "Team", false],
            [BarChart3, "Performance", false],
            [Filter, "Funnel", false],
          ].map(([Icon, label, active], i) => {
            const I = Icon as typeof Users;
            return (
              <div
                key={i}
                className="flex items-center gap-3 rounded-lg px-3 py-2"
                style={
                  active
                    ? { background: "#1B382C", color: "#F6F3EC" }
                    : { color: "rgba(233,228,214,0.55)" }
                }
              >
                <I className="h-4 w-4" style={active ? { color: "#C9A354" } : undefined} />
                {label as string}
              </div>
            );
          })}
        </nav>

        <div className="mt-auto flex items-center gap-2 rounded-lg px-2 py-2" style={{ color: "rgba(233,228,214,0.7)" }}>
          <span className="flex h-7 w-7 items-center justify-center rounded-full text-xs font-medium" style={{ background: "#C9A354", color: "#132A21" }}>
            RB
          </span>
          <div className="leading-tight">
            <p className="text-[12px]" style={{ color: "#F6F3EC" }}>Rudra Builders</p>
            <p className="text-[10px]">Admin</p>
          </div>
        </div>
      </aside>

      {/* Main */}
      <div className="flex min-w-0 flex-1 flex-col">
        {/* Top bar */}
        <div className="flex h-14 items-center justify-between border-b px-5" style={{ borderColor: "#E4DFD3" }}>
          <h3 className="text-lg font-medium" style={{ fontFamily: "var(--font-display)" }}>Leads</h3>
          <div className="flex items-center gap-3">
            <div className="hidden items-center gap-2 rounded-lg px-3 py-1.5 md:flex" style={{ background: "#EDE8DD" }}>
              <Search className="h-3.5 w-3.5" style={{ color: "#98A29A" }} />
              <span style={{ color: "#98A29A" }}>Search leads…</span>
            </div>
            <button className="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-white" style={{ background: "#A8823C" }}>
              <Plus className="h-3.5 w-3.5" />
              New lead
            </button>
          </div>
        </div>

        <div className="min-h-0 flex-1 overflow-hidden p-5">
          {/* 3-metric row */}
          <div className="grid grid-cols-3 gap-3">
            {[
              ["Follow-ups due", "12", Clock],
              ["Site visits this week", "8", Building2],
              ["Sold this month", "5", BarChart3],
            ].map(([label, value, Icon]) => {
              const I = Icon as typeof Clock;
              return (
                <div key={label as string} className="rounded-xl border p-4" style={{ borderColor: "#E4DFD3", background: "#FFFFFF" }}>
                  <div className="flex items-center gap-2" style={{ color: "#98A29A" }}>
                    <I className="h-3.5 w-3.5" />
                    <span className="text-[11px] uppercase tracking-wide">{label as string}</span>
                  </div>
                  <p className="mt-2 text-3xl font-light tabular-nums" style={{ fontFamily: "var(--font-display)" }}>
                    {value as string}
                  </p>
                </div>
              );
            })}
          </div>

          {/* Pipeline header + filter chips */}
          <div className="mt-6 flex items-center justify-between">
            <p className="text-[11px] font-medium uppercase tracking-wider" style={{ color: "#98A29A" }}>
              Today&apos;s pipeline
            </p>
            <div className="flex gap-1.5">
              {["All", "Hot", "Warm", "Cold"].map((c, i) => (
                <span
                  key={c}
                  className="rounded-full px-2.5 py-0.5 text-[11px]"
                  style={i === 0 ? { background: "#132A21", color: "#F6F3EC" } : { background: "#EDE8DD", color: "#5C665F" }}
                >
                  {c}
                </span>
              ))}
            </div>
          </div>

          {/* Lead rows */}
          <div className="mt-3 space-y-2.5">
            {leads.map((l) => (
              <div
                key={l.name}
                className="flex items-center gap-3 rounded-xl border p-3"
                style={{ borderColor: "#E4DFD3", background: "#FFFFFF" }}
              >
                <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-medium" style={{ background: "#EADFC4", color: "#8F6A2D" }}>
                  {l.initials}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-medium" style={{ fontFamily: "var(--font-display)" }}>{l.name}</span>
                    <Pill status={l.status} />
                  </div>
                  <p className="truncate text-[11px]" style={{ color: "#98A29A" }}>
                    {l.phone} · {l.project}
                  </p>
                </div>
                <div className="hidden text-right sm:block">
                  <p className="text-[10px] uppercase tracking-wide" style={{ color: "#98A29A" }}>Next follow-up</p>
                  <p className="text-[12px]" style={{ color: "#5C665F" }}>{l.follow}</p>
                </div>
                <button className="flex h-8 w-8 items-center justify-center rounded-lg text-white" style={{ background: "#A8823C" }}>
                  <Phone className="h-3.5 w-3.5" />
                </button>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

export function Dashboard() {
  return (
    <section id="platform" className="relative mx-auto max-w-7xl px-6 py-24">
      <div className="animate-on-scroll mx-auto max-w-2xl text-center">
        <span className="text-xs font-medium uppercase tracking-[0.2em] text-amber-400">The Nirman Console</span>
        <h2 className="mt-4 font-display text-4xl font-light tracking-tight text-white sm:text-5xl">
          Your whole sales floor, on one screen.
        </h2>
        <p className="mt-4 text-neutral-400">
          The same admin dashboard your team logs into every day. Leads, pipeline, follow-ups, and
          site visits, all in one place, all in real time.
        </p>
      </div>

      <div className="animate-on-scroll relative mt-16">
        {/* App frame */}
        <div className="relative z-10 overflow-hidden rounded-[24px] border border-white/10 bg-neutral-900/80 shadow-[0_0_80px_rgba(201,163,84,0.15)] ring-1 ring-white/10 backdrop-blur-sm">
          {/* Browser chrome */}
          <div className="flex items-center gap-2 border-b border-white/10 px-4 py-3">
            <span className="h-3 w-3 rounded-full bg-red-500/70" />
            <span className="h-3 w-3 rounded-full bg-yellow-500/70" />
            <span className="h-3 w-3 rounded-full bg-green-500/70" />
            <div className="ml-4 flex-1">
              <div className="mx-auto w-fit rounded-md bg-white/5 px-3 py-1 text-xs text-neutral-400">
                crm.nirmanmedia.com
              </div>
            </div>
          </div>
          <AdminMock />
        </div>
      </div>
    </section>
  );
}
