import type { Metadata } from "next";
import { LegalPage } from "@/components/luminous/legal-page";

export const metadata: Metadata = { title: "Privacy · Nirman CRM" };

// ⚠️ Draft baseline so the footer's Privacy link resolves to a real page
// (audit medium: it was a dead #top anchor). Rudra must review/replace this
// copy before public launch — it is intentionally short and factual.
const sections: [string, string][] = [
  [
    "What we store",
    "Nirman CRM stores the data a builder's team enters to run their sales pipeline: lead names and phone numbers, visit and follow-up history, unit inventory, and booking records. Each builder's data is isolated to their own workspace.",
  ],
  [
    "How it is protected",
    "Customer phone numbers are encrypted at rest. Access is scoped by role — an agent sees only their own leads, and margin data is visible only to the builder head. All access requires an authenticated login.",
  ],
  [
    "What we do NOT do",
    "We do not sell or share lead data with third parties, other builders, or advertisers. Data entered by a builder's team belongs to that builder.",
  ],
  [
    "Demo requests",
    "If you submit the book-a-demo form, we store the contact details you provide and use them only to reach you about Nirman CRM.",
  ],
  [
    "Questions or deletion requests",
    "Contact your Nirman operator, or reach us through the book-a-demo form on the home page, to ask about or delete your data.",
  ],
];

export default function PrivacyPage() {
  return <LegalPage title="Privacy Policy" sections={sections} />;
}
