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
const LeadSource = z.enum(["walk_in", "referral", "associate", "ad"]);

const CreateLeadInput = z.object({
  status: LeadStatus,
  phone: z.string().min(1, "Phone is required"),
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

  // Duplicate check (RLS ensures we only see leads in caller's tenant)
  const { data: existing, error: dupCheckErr } = await supabase
    .from("leads")
    .select("id, assigned_to_user_id")
    .eq("phone_hash", hash)
    .maybeSingle();

  if (dupCheckErr) {
    console.error(
      JSON.stringify({
        ts: new Date().toISOString(),
        level: "error",
        event: "duplicate_check_failed",
        error: dupCheckErr.message,
        tenant_id: tenantId,
      }),
    );
    return errorResponse("internal_error", "Failed to check for duplicate lead");
  }

  if (existing && !input.override_duplicate) {
    // Look up the owning employee's username for the error message
    const { data: ownerData } = await supabase
      .from("users")
      .select("email_or_username")
      .eq("id", existing.assigned_to_user_id)
      .maybeSingle();

    const ownerName = ownerData?.email_or_username ?? "another employee";
    return errorResponse(
      "duplicate_lead",
      `This lead already exists under ${ownerName}`,
      { existing_lead_id: existing.id, owner: ownerName },
    );
  }

  if (existing && input.override_duplicate && role !== "admin") {
    return errorResponse("forbidden_role", "Only admins can override duplicate leads");
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
    },
  );

  if (insertErr || !leadId) {
    const msg = insertErr?.message ?? "";
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

  // Admin override: log duplicate_override event on the newly created lead
  if (existing && input.override_duplicate) {
    const { error: overrideErr } = await supabase.rpc("log_timeline_event", {
      p_lead_id: leadId as string,
      p_event_type: "duplicate_override",
      p_payload: {
        original_lead_id: existing.id,
        overridden_by_role: role,
      },
    });
    if (overrideErr) {
      console.error(
        JSON.stringify({
          ts: new Date().toISOString(),
          level: "warn",
          event: "duplicate_override_log_failed",
          lead_id: leadId,
          error: overrideErr.message,
        }),
      );
    }
  }

  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level: "info",
      event: "lead_created",
      tenant_id: tenantId,
      actor_id: actorId,
      lead_id: leadId,
      is_incomplete: isIncomplete,
      override: existing != null,
    }),
  );

  return successResponse({ lead_id: leadId as string, is_incomplete: isIncomplete }, 201);
});
