import type { Metadata } from "next";
import { DemoShell } from "@/components/demo/demo-shell";

export const metadata: Metadata = {
  title: "See Nirman in action — interactive demo",
  description:
    "Click through the real Nirman CRM — the admin dashboard and the mobile field app — right in your browser. No signup.",
};

export default function DemoPage() {
  return <DemoShell />;
}
