import type { Metadata } from "next";
import { LegalPage } from "@/components/luminous/legal-page";

export const metadata: Metadata = { title: "Terms · Nirman CRM" };

// ⚠️ Draft baseline so the footer's Terms link resolves to a real page
// (audit medium: it was a dead #top anchor). Rudra must review/replace this
// copy before public launch — it is intentionally short and factual.
const sections: [string, string][] = [
  [
    "The service",
    "Nirman CRM is a subscription service for real-estate builders and their sales teams: lead management, inventory, holds and bookings, on web and mobile.",
  ],
  [
    "Subscription and access",
    "Access is prepaid per project on a monthly basis, collected by your Nirman operator. If a subscription lapses, access is paused until it is recharged; your data is retained, not deleted.",
  ],
  [
    "Your data",
    "Data entered by your team remains yours. See the Privacy Policy for how it is stored and protected.",
  ],
  [
    "Acceptable use",
    "Accounts are for your own sales operation. Do not attempt to access another builder's workspace or another agent's leads outside the roles your builder head assigns.",
  ],
  [
    "Changes",
    "We may update these terms as the product evolves; material changes will be communicated to the builder's admin account.",
  ],
];

export default function TermsPage() {
  return <LegalPage title="Terms of Service" sections={sections} />;
}
