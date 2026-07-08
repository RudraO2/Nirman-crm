// Story 2.3 — Lead creation: Quick-Capture and status-first entry
// FRs: FR-1 (14-field lead form), FR-2 (Quick-Capture min Status+Phone),
//      FR-3 (duplicate phone prevention, admin override), FR-4 (status-first)
// NFRs: NFR-8 (PII encrypted via create_lead_with_pii SECURITY DEFINER DB fn),
//       NFR-11 (tenant_id isolation via JWT + RLS)
//
// Flow:
//   1. Validate JWT → extract tenantId, actorId, role
//   2. Validate + normalize phone (replicate DB normalize_phone() logic)
//   3. Compute phone_hash (SHA-256 of normalized phone, hex-encoded)
//   4. Duplicate check via authenticated client (RLS scopes to caller's tenant)
//   5. Admin override: allowed only for role=admin
//   6. Compute is_incomplete server-side from field presence
//   7. Call create_lead_with_pii() DB function (SECURITY DEFINER handles Vault + pgcrypto)
//   8. Insert lead_projects associations
//   9. If admin override: log duplicate_override timeline event

import { z } from "npm:zod";
import { errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

// ---------------------------------------------------------------------------
// Phone normalization — mirrors public.normalize_phone() SQL function
// Returns null if phone cannot be reduced to exactly 10 digits.
// ---------------------------------------------------------------------------
function normalizePhone(raw: string): string | null {
  if (!raw) return null;
  let cleaned = raw.replace(/[^\d]/g, "");
  // Strip 91 country code prefix on 12-digit string
  if (cleaned.length === 12 && cleaned.startsWith("91")) {
    cleaned = cleaned.slice(2);
  }
  // Strip leading 0 on 11-digit string
  if (cleaned.length === 11 && cleaned.startsWith("0")) {
    cleaned = cleaned.slice(1);
  }
  return cleaned.length === 10 ? cleaned : null;
}

// ---------------------------------------------------------------------------
// Phone hash — encode(sha256(normalized_phone::bytea), 'hex')
// Must match the DB expression used for duplicate lookup.
// ---------------------------------------------------------------------------
async function computePhoneHash(normalized: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(normalized);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ---------------------------------------------------------------------------
// Input schema
// ---------------------------------------------------------------------------
const LeadStatus = z.enum(["warm", "cold", "hot", "dead", "sold", "future"]);
// Story 13.1 — source enum extended to 6 values.
const LeadSource = z.enum(["walk_in", "referral", "associate", "ad", "cold_call", "employee_referral"]);

const CreateLeadInput = z.object({
  status: LeadStatus,
  phone: z.string().min(1, "Phone is required"),
  // Story 13.2 — secondary phone: optional at quick-capture, required for Complete.
  secondary_phone: z.string().optional().nullable(),
  source: LeadSource.optional().nullable(),
  name: z.string().max(255).optional().nullable(),
  property_type: z.string().max(100).optional().nullable(),
  location: z.string().max(255).optional().nullable(),
  budget_min: z.number().int().positive().optional().nullable(),
  budget_max: z.number().int().positive().optional().nullable(),
  ticket_size: z.string().max(50).optional().nullable(),
  remarks: z.string().max(2000).optional().nullable(),
  visit_date: z.string().datetime().optional().nullable(),
  next_followup_at: z.string().datetime().optional().nullable(),
  interest_type: z.string().max(100).optional().nullable(),
  project_ids: z.array(z.string().uuid()).optional().default([]),
  override_duplicate: z.boolean().optional().default(false),
});

// ---------------------------------------------------------------------------
// is_incomplete: true if any non-optional field is absent
// Non-optional fields (from Story 2.4 AC): name, source, property_type,
// location, ticket_size, budget (min or max), at least 1 project,
// AND interest_type when status=future
// ---------------------------------------------------------------------------
function computeIsIncomplete(
  input: z.infer<typeof CreateLeadInput>,
): boolean {
  const hasBudget = (input.budget_min ?? 0) > 0 || (input.budget_max ?? 0) > 0;
  return (
    !input.name?.trim() ||
    !input.source ||
    !input.secondary_phone?.trim() || // Story 13.2 — secondary phone required for Complete (FR-42)
    !input.property_type?.trim() ||
    !input.location?.trim() ||
    !input.ticket_size?.trim() ||
    !hasBudget ||
    !input.project_ids?.length ||
    (input.status === "future" && !input.interest_type?.trim())
  );
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------
Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") {
    return errorResponse("validation_error", "Use POST");
  }

  const authResult = await verifyJwtAndScope(req);
  if (isAuthFailure(authResult)) return authResult.response;
  const { supabase, actorId, tenantId, role } = authResult;

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }

  const parsed = CreateLeadInput.safeParse(body);
  if (!parsed.success) {
    return errorResponse(
      "validation_error",
      "Invalid input",
      parsed.error.flatten().fieldErrors,
    );
  }
  const input = parsed.data;

  // Normalize phone
  const normalizedPhone = normalizePhone(input.phone);
  if (!normalizedPhone) {
    return errorResponse(
      "validation_error",
      "Invalid phone number. Enter a valid 10-digit Indian mobile number.",
      { phone: ["Must be a valid 10-digit Indian mobile number"] },
    );
  }

  // Compute phone hash (mirrors DB encode(sha256(...), 'hex') expression)
  const hash = await computePhoneHash(normalizedPhone);

  // Story 13.2 — secondary phone: optional, but if provided must be a valid 10-digit mobile.
  // Stored encrypted + hashed (hash NOT used for dedup — A-11). Absence => Incomplete.
  let secondaryNormalized: string | null = null;
  let secondaryHash: string | null = null;
  if (input.secondary_phone && input.secondary_phone.trim()) {
    secondaryNormalized = normalizePhone(input.secondary_phone);
    if (!secondaryNormalized) {
      return errorResponse(
        "validation_error",
        "Invalid secondary phone. Enter a valid 10-digit Indian mobile number.",
        { secondary_phone: ["Must be a valid 10-digit Indian mobile number"] },
      );
    }
    secondaryHash = await computePhoneHash(secondaryNormalized);
  }

  // Story 13.5 — dedup/reclaim is enforced atomically inside create_lead_with_pii (FOR UPDATE):
  // a locked duplicate (≤90d & owner active ≤30d) raises duplicate_lead; an expired/inactive
  // duplicate is reclaimed in place (same row reassigned + lead_reclaimed logged); otherwise a
  // new lead is inserted. We only gate a non-admin override attempt here with a clear message.
  if (input.override_duplicate && role !== "admin") {
    const { data: lockedExisting } = await supabase
      .from("leads").select("id").eq("phone_hash", hash).maybeSingle();
    if (lockedExisting) {
      return errorResponse("forbidden_role", "Only admins can override a locked duplicate lead");
    }
  }

  const isIncomplete = computeIsIncomplete(input);

  // create_lead_with_pii is SECURITY DEFINER (postgres) — reads Vault,
  // encrypts PII via pgcrypto, inserts lead, calls log_timeline_event.
  // Calling via user-scoped client preserves auth.uid() / auth.jwt() at session level.
  const { data: leadId, error: insertErr } = await supabase.rpc(
    "create_lead_with_pii",
    {
      p_status:           input.status,
      p_source:           input.source ?? null,
      p_phone_raw:        normalizedPhone,
      p_phone_hash:       hash,
      p_name:             input.name?.trim() ?? null,
      p_property_type:    input.property_type?.trim() ?? null,
      p_location:         input.location?.trim() ?? null,
      p_budget_min:       input.budget_min ?? null,
      p_budget_max:       input.budget_max ?? null,
      p_ticket_size:      input.ticket_size?.trim() ?? null,
      p_remarks:          input.remarks?.trim() ?? null,
      p_visit_date:       input.visit_date ?? null,
      p_next_followup_at: input.next_followup_at ?? null,
      p_interest_type:    input.interest_type?.trim() ?? null,
      p_is_incomplete:    isIncomplete,
      p_secondary_phone_raw:  secondaryNormalized,
      p_secondary_phone_hash: secondaryHash,
      p_force_reclaim:        input.override_duplicate && role === "admin", // Story 13.5
    },
  );

  if (insertErr || !leadId) {
    const msg = insertErr?.message ?? "";
    if (msg.includes("duplicate_lead")) {
      // Story 13.5 — locked phone. Look up the owner for a friendly message.
      const { data: lockRow } = await supabase
        .from("leads").select("assigned_to_user_id").eq("phone_hash", hash).maybeSingle();
      let ownerName = "another employee";
      if (lockRow?.assigned_to_user_id) {
        const { data: u } = await supabase
          .from("users").select("email_or_username").eq("id", lockRow.assigned_to_user_id).maybeSingle();
        ownerName = u?.email_or_username ?? ownerName;
      }
      return errorResponse(
        "duplicate_lead",
        `This lead is locked under ${ownerName}. It can be re-claimed after the 90-day lock or 30 days of owner inactivity.`,
      );
    }
    if (msg.includes("pii_key_missing")) {
      console.error(
        JSON.stringify({
          ts: new Date().toISOString(),
          level: "error",
          event: "vault_key_missing",
          tenant_id: tenantId,
        }),
      );
      return errorResponse("internal_error", "PII encryption key not configured. Contact your system administrator.");
    }
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "lead_insert_failed",
        error: insertErr?.message,
        tenant_id: tenantId,
        actor_id: actorId,
      }),
    );
    return errorResponse("internal_error", "Failed to create lead");
  }

  // Insert project associations (non-fatal: lead exists even if this fails)
  if (input.project_ids.length > 0) {
    const projectRows = input.project_ids.map((pid) => ({
      lead_id: leadId as string,
      project_id: pid,
      tenant_id: tenantId,
    }));
    const { error: projErr } = await supabase
      .from("lead_projects")
      .insert(projectRows);
    if (projErr) {
      console.error(
        JSON.stringify({
          ts: new Date().toISOString(),
          level: "warn",
          event: "lead_projects_insert_failed",
          lead_id: leadId,
          error: projErr.message,
        }),
      );
    }
  }

  // Story 13.5 — reclaim (if it happened) is logged as lead_reclaimed inside the DB function;
  // no duplicate_override event is emitted (no duplicate row is ever created).

  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level: "info",
      event: "lead_created",
      tenant_id: tenantId,
      actor_id: actorId,
      lead_id: leadId,
      is_incomplete: isIncomplete,
    }),
  );

  // Story 13.3 — fetch the generated customer code + build a free WhatsApp delivery link.
  // SMS is a deferred paid adapter; default delivery is wa.me + on-screen display.
  let customerCode: string | null = null;
  let whatsappLink: string | null = null;
  const { data: codeRow } = await supabase
    .from("leads")
    .select("customer_code")
    .eq("id", leadId as string)
    .maybeSingle();
  customerCode = (codeRow?.customer_code as string | null) ?? null;
  if (customerCode) {
    const msg = `Your visit code is ${customerCode}. Show it at our reception to verify your visit.`;
    whatsappLink = `https://wa.me/91${normalizedPhone}?text=${encodeURIComponent(msg)}`;
  }

  return successResponse(
    { lead_id: leadId as string, is_incomplete: isIncomplete, customer_code: customerCode, whatsapp_link: whatsappLink },
    201,
  );
});
