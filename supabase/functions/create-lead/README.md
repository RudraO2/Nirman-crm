# create-lead Edge Function

Story 2.3 — Employee creates a Lead with Quick-Capture and status-first entry.

## Required setup before first use

### 1. Create the `lead_pii_key` Vault secret

The `create_lead_with_pii()` DB function reads this secret to encrypt PII
(name + phone) via pgcrypto. The function will throw `pii_key_missing` if the
secret is absent.

**Via Supabase CLI:**
```bash
# Generate a strong random key (32 bytes, base64)
openssl rand -base64 32

# Store it in Vault (replace <key> with the generated value)
supabase secrets set lead_pii_key=<key>
```

**Via Supabase MCP (SQL):**
```sql
SELECT vault.create_secret('<key>', 'lead_pii_key', 'AES-256 key for lead PII column encryption');
```

> Keep this key in a secure location. Loss of the key means encrypted PII
> cannot be decrypted. Rotation requires a migration to re-encrypt all rows.

### 2. Apply migration 0016

```bash
supabase db push
```

Or via Supabase MCP: `mcp__supabase__apply_migration` with the contents of
`supabase/migrations/0016_create_lead_with_pii.sql`.

## Request format

```json
POST /functions/v1/create-lead
Authorization: Bearer <employee-or-admin-jwt>

{
  "status": "hot",            // required: warm | cold | hot | dead | sold | future
  "phone": "98765 43210",     // required: normalized to 10-digit E.164 server-side
  "source": "walk_in",        // optional: walk_in | referral | associate | ad
  "name": "Anita Sharma",     // optional
  "property_type": "Flat",    // optional
  "location": "Bandra West",  // optional
  "budget_min": 5000000,      // optional: paise (₹50L = 5_000_000_00 paise)
  "budget_max": 8000000,      // optional: paise
  "ticket_size": "3BHK",      // optional
  "remarks": "Interested in...", // optional
  "visit_date": "2026-06-01T10:00:00+05:30",  // optional: ISO 8601
  "next_followup_at": "...",  // optional: ISO 8601
  "interest_type": null,      // required when status=future (else is_incomplete=true)
  "project_ids": ["<uuid>"],  // optional: array of project UUIDs
  "override_duplicate": false // optional: admin-only override for duplicate phone
}
```

## Response

**201 Created:**
```json
{ "data": { "lead_id": "<uuid>", "is_incomplete": true } }
```

**409 Conflict (duplicate phone):**
```json
{
  "error": {
    "code": "duplicate_lead",
    "message": "This lead already exists under Ravi Kumar",
    "details": { "existing_lead_id": "<uuid>", "owner": "Ravi Kumar" }
  }
}
```
