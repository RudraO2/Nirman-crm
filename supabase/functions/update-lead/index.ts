// Story 2.4 — Lead edit: full-replacement update with PII re-encryption
// FRs: FR-1 (14-field edit), FR-3 (duplicate phone on update), FR-19 (field_updated timeline)
//
// Flow:
//   1. Validate JWT → extract tenantId, actorId, role
//   2. Validate + normalize new phone
//   3. Compute new phone_hash
//   4. Fetch current lead (get_lead_by_id) for change-diff + old hash comparison
//   5. Duplicate check if phone_hash changed
//   6. Validate interest_type required when status=future
//   7. Compute is_incomplete + changed_fields list
//   8. Call update_lead_with_pii() DB function
//   9. Sync lead_projects (delete all + re-insert)

import { z } from "npm:zod";
import { errorResponse, successResponse } from "./_shared/errors.ts";
import { verifyJwtAndScope, isAuthFailure } from "./_shared/auth.ts";

// ---------------------------------------------------------------------------
// Reuse from create-lead
// ---------------------------------------------------------------------------
function normalizePhone(raw: string): string | null {
  if (!raw) return null;
  let cleaned = raw.replace(/[^\d]/g, "");
  if (cleaned.length === 12 && cleaned.startsWith("91")) cleaned = cleaned.slice(2);
  if (cleaned.length === 11 && cleaned.startsWith("0")) cleaned = cleaned.slice(1);
  return cleaned.length === 10 ? cleaned : null;
}

async function computePhoneHash(normalized: string): Promise<string> {
  const data = new TextEncoder().encode(normalized);
  const buf  = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function computeIsIncomplete(input: z.infer<typeof UpdateLeadInput>): boolean {
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
// Input schema
// ---------------------------------------------------------------------------
const LeadStatus = z.enum(["warm", "cold", "hot", "dead", "sold", "future"]);
// Story 13.1 — source enum extended to 6 values.
const LeadSource = z.enum(["walk_in", "referral", "associate", "ad", "cold_call", "employee_referral"]);

const UpdateLeadInput = z.object({
  lead_id:           z.string().uuid(),
  status:            LeadStatus,
  phone:             z.string().min(1, "Phone is required"),
  secondary_phone:   z.string().optional().nullable(), // Story 13.2
  source:            LeadSource.optional().nullable(),
  name:              z.string().max(255).optional().nullable(),
  property_type:     z.string().max(100).optional().nullable(),
  location:          z.string().max(255).optional().nullable(),
  budget_min:        z.number().int().positive().optional().nullable(),
  budget_max:        z.number().int().positive().optional().nullable(),
  ticket_size:       z.string().max(50).optional().nullable(),
  remarks:           z.string().max(2000).optional().nullable(),
  visit_date:        z.string().datetime().optional().nullable(),
  next_followup_at:  z.string().datetime().optional().nullable(),
  interest_type:     z.string().max(100).optional().nullable(),
  project_ids:       z.array(z.string().uuid()).optional().default([]),
});

// ---------------------------------------------------------------------------
// Compute changed fields list for timeline (non-PII field names)
// PII fields (name, phone) tracked as opaque "changed" — no value logged.
// ---------------------------------------------------------------------------
function changedFields(
  input: z.infer<typeof UpdateLeadInput>,
  old: Record<string, unknown>,
  oldProjectIds: string[],
): string[] {
  const fields: string[] = [];

  if (input.status !== old["status"]) fields.push("status");
  if ((input.source ?? null) !== (old["source"] ?? null)) fields.push("source");
  if ((input.property_type ?? null) !== (old["property_type"] ?? null)) fields.push("property_type");
  if ((input.location ?? null) !== (old["location"] ?? null)) fields.push("location");
  if ((input.budget_min ?? null) !== (old["budget_min"] ?? null)) fields.push("budget_min");
  if ((input.budget_max ?? null) !== (old["budget_max"] ?? null)) fields.push("budget_max");
  if ((input.ticket_size ?? null) !== (old["ticket_size"] ?? null)) fields.push("ticket_size");
  if ((input.remarks ?? null) !== (old["remarks"] ?? null)) fields.push("remarks");
  if ((input.visit_date ?? null) !== (old["visit_date"] ?? null)) fields.push("visit_date");
  if ((input.next_followup_at ?? null) !== (old["next_followup_at"] ?? null)) fields.push("next_followup_at");
  if ((input.interest_type ?? null) !== (old["interest_type"] ?? null)) fields.push("interest_type");

  // PII fields — compare by hash/presence, not value
  const oldPhone = old["phone"] as string | null;
  if (normalizePhone(input.phone) !== (oldPhone ? normalizePhone(oldPhone) : null)) {
    fields.push("phone");
  }
  const oldName = (old["name"] as string | null)?.trim() ?? null;
  const newName = input.name?.trim() ?? null;
  if (newName !== oldName) fields.push("name");

  // Projects
  const newPids = [...(input.project_ids ?? [])].sort();
  const oldPids = [...oldProjectIds].sort();
  if (JSON.stringify(newPids) !== JSON.stringify(oldPids)) fields.push("project_ids");

  return fields;
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
  const { supabase, actorId, tenantId } = authResult;

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return errorResponse("validation_error", "Body must be valid JSON");
  }

  const parsed = UpdateLeadInput.safeParse(body);
  if (!parsed.success) {
    return errorResponse("validation_error", "Invalid input", parsed.error.flatten().fieldErrors);
  }
  const input = parsed.data;

  // interest_type required when status=future
  if (input.status === "future" && !input.interest_type?.trim()) {
    return errorResponse(
      "interest_type_required",
      "Interest Type is required when status is Future",
      { interest_type: ["Required for Future status"] },
    );
  }

  // Normalize phone
  const normalizedPhone = normalizePhone(input.phone);
  if (!normalizedPhone) {
    return errorResponse("validation_error", "Invalid phone number. Enter a valid 10-digit Indian mobile number.");
  }
  const newHash = await computePhoneHash(normalizedPhone);

  // Story 13.2 — secondary phone: optional, but if provided must be valid. Absence => Incomplete.
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

  // Fetch current lead (ownership verified inside get_lead_by_id)
  const { data: currentRows, error: fetchErr } = await supabase.rpc("get_lead_by_id", {
    p_lead_id: input.lead_id,
  });

  if (fetchErr) {
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "fetch_lead_failed", error: fetchErr.message }));
    return errorResponse("internal_error", "Failed to fetch lead");
  }

  const currentLead = (currentRows as unknown[])?.[0] as Record<string, unknown> | undefined;
  if (!currentLead) {
    return errorResponse("not_found", "Lead not found in your queue");
  }

  // Duplicate check only if phone hash changed
  // 0098: via definer RPC — authenticated has no phone_hash SELECT.
  if (newHash !== currentLead["phone_hash"]) {
    const { data: dupe } = await supabase.rpc("check_phone_duplicate", {
      p_phone_hash: newHash,
      p_exclude_lead_id: input.lead_id,
    });
    const existing = dupe as { found?: boolean; lead_id?: string; owner_name?: string } | null;

    if (existing?.found) {
      const ownerName = existing.owner_name ?? "another employee";
      return errorResponse("duplicate_lead", `This phone number is already linked to a lead under ${ownerName}`, {
        existing_lead_id: existing.lead_id,
        owner: ownerName,
      });
    }
  }

  const isIncomplete  = computeIsIncomplete(input);
  const oldProjectIds = (currentLead["project_ids"] as string[]) ?? [];
  const changed       = changedFields(input, currentLead, oldProjectIds);

  // Call update_lead_with_pii DB function
  const { data: updateResult, error: updateErr } = await supabase.rpc("update_lead_with_pii", {
    p_lead_id:          input.lead_id,
    p_status:           input.status,
    p_source:           input.source ?? null,
    p_phone_raw:        normalizedPhone,
    p_phone_hash:       newHash,
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
    p_changed_fields:   changed,
    p_secondary_phone_raw:  secondaryNormalized,
    p_secondary_phone_hash: secondaryHash,
  });

  if (updateErr) {
    const msg = updateErr.message ?? "";
    if (msg.includes("lead_not_found_or_forbidden")) {
      return errorResponse("not_found", "Lead not found in your queue");
    }
    if (msg.includes("pii_key_missing")) {
      return errorResponse("internal_error", "PII encryption key not configured. Contact your system administrator.");
    }
    console.error(JSON.stringify({ ts: new Date().toISOString(), level: "error", event: "lead_update_failed", error: msg, lead_id: input.lead_id }));
    return errorResponse("internal_error", "Failed to update lead");
  }

  // Sync lead_projects: delete all existing, insert new set
  if (changed.includes("project_ids")) {
    await supabase.from("lead_projects").delete().eq("lead_id", input.lead_id);
    if (input.project_ids.length > 0) {
      const rows = input.project_ids.map((pid) => ({ lead_id: input.lead_id, project_id: pid, tenant_id: tenantId }));
      const { error: projErr } = await supabase.from("lead_projects").insert(rows);
      if (projErr) {
        console.error(JSON.stringify({ ts: new Date().toISOString(), level: "warn", event: "lead_projects_sync_failed", lead_id: input.lead_id, error: projErr.message }));
      }
    }
  }

  console.log(JSON.stringify({
    ts: new Date().toISOString(), level: "info", event: "lead_updated",
    tenant_id: tenantId, actor_id: actorId, lead_id: input.lead_id,
    is_incomplete: isIncomplete, changed_fields: changed,
  }));

  return successResponse({
    lead_id: input.lead_id,
    is_incomplete: isIncomplete,
    status: input.status,
    changed_fields: changed,
  });
});
