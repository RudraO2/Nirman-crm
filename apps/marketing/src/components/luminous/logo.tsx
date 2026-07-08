import { Asterisk } from "lucide-react";

export function Logo() {
  return (
    <a href="#top" className="flex items-center gap-2">
      <span className="relative flex h-8 w-8 items-center justify-center">
        <Asterisk className="absolute h-8 w-8 rotate-45 text-white" strokeWidth={2} />
        <Asterisk className="absolute h-[32px] w-[32px] text-amber-500" strokeWidth={1.5} />
      </span>
      <span className="flex items-baseline gap-1.5">
        <span className="text-lg font-medium tracking-tight text-white">Nirman</span>
        <span className="text-[11px] font-medium uppercase tracking-[0.16em] text-amber-400">CRM</span>
      </span>
    </a>
  );
}
