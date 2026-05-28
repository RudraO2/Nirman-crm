---
story_key: 2-3-employee-creates-lead-quick-capture-status-first
epic: 2
story: 3
story_id: 2.3
supabase_project_id: vhgruadourflpxuzuxfn
github_repo: https://github.com/RudraO2/Nirman-crm
---

# Story 2.3: Employee creates a Lead with Quick-Capture and status-first entry

Status: ready-for-dev

## Story

As an Employee,
I want to create a new Lead by tapping a Status first and entering only Phone Number to save,
So that I capture a walk-in customer before the moment is lost and finish the form later.

## Acceptance Criteria

1. **AC-1 — Status-first entry.** Given I am on the lead list screen, when I tap the "New Lead" FAB, then the form opens with a 6-option Status selector (warm / cold / hot / dead / sold / future) as the FIRST rendered element before any other field.

2. **AC-2 — Fields visible after status selection.** Given I tap a Status, then the remaining fields become visible: Source, Name, Phone, Project (multi-select), Property Type, Location, Budget (min/max), Ticket Size, Remarks, Visit Date, Next Follow-up.

3. **AC-3 — Quick-Capture save (Phone only).** Given I enter only Phone Number (with a status already selected) and tap "Save Incomplete", then:
   - `POST /functions/v1/create-lead` is called with `{status, phone}`
   - Lead is created with `is_incomplete = true`
   - Phone is normalized via `normalize_phone()` DB function
   - `phone_hash = encode(sha256(normalize_phone(phone)::bytea), 'hex')` — computed in Edge Function
   - `phone_encrypted` = `encrypt_pii(normalize_phone(phone))` — bytea via DB function
   - `name_encrypted` = NULL (no name provided)
   - `name_search` = NULL
   - Lead is returned with its `id` and `is_incomplete = true`
   - Timeline records `lead_created` event via `log_timeline_event(lead_id, 'lead_created', {...})`

4. **AC-4 — Incomplete badge on lead card.** The newly created lead appears in the lead list screen with a red "Incomplete" badge. The badge is shown whenever `is_incomplete = true`.

5. **AC-5 — Duplicate phone blocked.** Given I enter a Phone Number whose `normalize_phone()` value already exists in any lead in my tenant (including Archived leads), then save is blocked and the error "This lead already exists under [Employee Name]" is shown. The Edge Function returns HTTP 409 `duplicate_lead` with `{existing_lead_id, assigned_to_name}` in details.

6. **AC-6 — Admin duplicate override.** Given I am an Admin and I see the duplicate error, when I tap the override button and enter a reason, then `POST /functions/v1/duplicate-check-override` is called with `{...lead_data, override_reason}`, the lead is created, and Timeline records both `lead_created` and `duplicate_override` (with payload `{reason: override_reason}`) events.

7. **AC-7 — Invalid phone rejected.** Given `normalize_phone(raw_phone)` returns NULL (phone not parseable to 10 digits), the Edge Function returns HTTP 400 `validation_error` and save is blocked before any DB write.

8. **AC-8 — Full form save (all fields).** Given I fill all visible fields and tap "Save Incomplete", the same `create-lead` Edge Function is called with all optional fields. `is_incomplete` is computed by the Edge Function: false only when source, name, property_type, location, budget_min, budget_max, ticket_size are all present AND (if status=future) interest_type is present AND project_ids is non-empty.

9. **AC-9 — Drift local draft buffer (NFR-15).** Before the Edge Function is called, the lead draft is written to a local Drift table. On Edge Function success, the local row is marked synced with the server-assigned `lead_id`. On Edge Function failure, the local draft is retained and an error toast is shown.

10. **AC-10 — Security: employee-only creates own leads.** The `create-lead` Edge Function always sets `assigned_to_user_id = actorId` (from JWT) for employee callers. Admin callers may optionally pass `assigned_to_user_id`.

## Tasks / Subtasks

- [ ] **T-0 — Confirm migration number**
  - [ ] T-0.1 List `nirman-crm/supabase/migrations/` — confirm last is `0015_cr_patch_lead_timeline.sql`. Next = **0016**.

- [ ] **T-1 (AC: 3, 5, 6) — Migration `0016_create_encrypt_pii_fn.sql`**
  - [ ] T-1.1 Create `encrypt_pii(plaintext text) RETURNS bytea` SECURITY DEFINER function.
    - Reads `lead_pii_key` from `vault.decrypted_secrets WHERE name = 'lead_pii_key'`.
    - Raises `P0001 'pii_key_missing'` if secret not found.
    - Returns `extensions.pgp_sym_encrypt(plaintext, pii_key)`.
    - `SET search_path = ''`.
  - [ ] T-1.2 Use `extensions.pgp_sym_encrypt(plaintext, pii_key)` — pgcrypto is installed under the `extensions` schema on this project (consistent with `extensions.gen_random_uuid()`, `extensions.gin_trgm_ops` in migrations 0001–0015). With `SET search_path = ''`, always schema-qualify.
  - [ ] T-1.3 `REVOKE EXECUTE ON FUNCTION public.encrypt_pii(text) FROM PUBLIC;`
  - [ ] T-1.4 `GRANT EXECUTE ON FUNCTION public.encrypt_pii(text) TO service_role;`
    - Only service_role (Edge Function service key) should call this. Never authenticated.
  - [ ] T-1.5 Apply via `mcp__supabase__apply_migration` (project: `vhgruadourflpxuzuxfn`).
  - [ ] T-1.6 Verify via `execute_sql`: `SELECT encrypt_pii('test')` as service_role → should return bytea. If vault secret not yet seeded, expect `pii_key_missing` error (acceptable at migration time — seed vault before E2E test).

- [ ] **T-2 (AC: 3, 5, 7, 8, 9, 10) — Edge Function `supabase/functions/create-lead/index.ts`**
  - [ ] T-2.1 Create `supabase/functions/create-lead/index.ts`.
  - [ ] T-2.2 Import from `../_shared/errors.ts` and `../_shared/auth.ts` (these exist — do NOT copy).
  - [ ] T-2.3 Zod input schema `CreateLeadInput`:
    ```typescript
    status: z.enum(['warm','cold','hot','dead','sold','future'])
    phone: z.string().min(1).max(20)
    name: z.string().trim().max(200).optional()
    source: z.enum(['walk_in','referral','associate','ad']).optional()
    property_type: z.string().max(100).optional()
    location: z.string().max(200).optional()
    budget_min: z.number().int().nonnegative().optional()
    budget_max: z.number().int().nonnegative().optional()
    ticket_size: z.string().max(50).optional()
    remarks: z.string().max(2000).optional()
    visit_date: z.string().datetime().optional()
    next_followup_at: z.string().datetime().optional()
    interest_type: z.string().max(100).optional()
    project_ids: z.array(z.string().uuid()).max(10).optional()
    assigned_to_user_id: z.string().uuid().optional()  // admin-only override
    ```
  - [ ] T-2.4 `Deno.serve(async (req) => ...)` — reject non-POST.
  - [ ] T-2.5 `verifyJwtAndScope(req)` — reject if auth failure.
  - [ ] T-2.6 Zod parse body — return 400 `validation_error` on failure.
  - [ ] T-2.7 Service-role client for privileged DB operations:
    ```typescript
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    );
    ```
  - [ ] T-2.8 Normalize phone:
    ```typescript
    const { data: normalized, error: normErr } = await serviceClient
      .rpc('normalize_phone', { raw: input.phone });
    if (normErr || !normalized) return errorResponse('validation_error', 'Invalid phone number format');
    ```
  - [ ] T-2.9 Compute phone_hash in Edge Function (NOT in DB):
    ```typescript
    const encoder = new TextEncoder();
    const hashBuf = await crypto.subtle.digest('SHA-256', encoder.encode(normalized));
    const phoneHash = Array.from(new Uint8Array(hashBuf))
      .map(b => b.toString(16).padStart(2, '0')).join('');
    ```
  - [ ] T-2.10 Duplicate check — query `leads` using service_role (sees all tenant leads including archived):
    ```typescript
    const { data: existing } = await serviceClient
      .from('leads')
      .select('id, assigned_to_user_id, users!assigned_to_user_id(email_or_username)')
      .eq('tenant_id', tenantId)
      .eq('phone_hash', phoneHash)
      .maybeSingle();
    if (existing) {
      const assignedTo = (existing.users as any)?.email_or_username ?? 'another employee';
      return errorResponse('duplicate_lead',
        `This lead already exists under ${assignedTo}`,
        { existing_lead_id: existing.id, assigned_to_name: assignedTo }
      );
    }
    ```
  - [ ] T-2.11 Encrypt PII via `encrypt_pii` DB function:
    ```typescript
    const { data: encPhone } = await serviceClient.rpc('encrypt_pii', { plaintext: normalized });
    // encPhone is returned as "\\xHEX..." string — pass as-is; PostgREST stores it as bytea
    let encName: string | null = null;
    if (input.name?.trim()) {
      const { data: en } = await serviceClient.rpc('encrypt_pii', { plaintext: input.name.trim() });
      encName = en;
    }
    ```
  - [ ] T-2.12 Compute `is_incomplete`:
    ```typescript
    const isIncomplete = !input.source
      || !input.name?.trim()
      || !input.property_type
      || !input.location
      || input.budget_min === undefined
      || input.budget_max === undefined
      || !input.ticket_size
      || !input.project_ids?.length
      || (input.status === 'future' && !input.interest_type);
    ```
  - [ ] T-2.13 Determine `assigned_to_user_id`:
    - If caller is `'employee'` → always `actorId` (ignore any input value)
    - If caller is `'admin'` → use `input.assigned_to_user_id ?? actorId`
  - [ ] T-2.14 Insert into `public.leads` using user-JWT scoped client (RLS enforced):
    ```typescript
    // Use the user-scoped supabase client from verifyJwtAndScope
    const { data: lead, error: insertErr } = await supabase
      .from('leads')
      .insert({
        tenant_id: tenantId,
        assigned_to_user_id: assignedTo,
        status: input.status,
        source: input.source ?? null,
        name_encrypted: encName,      // "\\xHEX..." or null — PostgREST handles bytea encoding
        phone_encrypted: encPhone,    // "\\xHEX..."
        phone_hash: phoneHash,
        name_search: input.name?.trim().toLowerCase() ?? null,
        property_type: input.property_type ?? null,
        location: input.location ?? null,
        budget_min: input.budget_min ?? null,
        budget_max: input.budget_max ?? null,
        ticket_size: input.ticket_size ?? null,
        remarks: input.remarks ?? null,
        visit_date: input.visit_date ?? null,
        next_followup_at: input.next_followup_at ?? null,
        interest_type: input.interest_type ?? null,
        is_incomplete: isIncomplete,
        last_action_at: new Date().toISOString(),
      })
      .select('id, is_incomplete, status, created_at')
      .single();
    if (insertErr) {
      if (insertErr.code === '23505') {
        // Race condition: duplicate slipped past the check above
        return errorResponse('duplicate_lead', 'Phone number already exists in a concurrent submission');
      }
      throw insertErr;
    }
    ```
  - [ ] T-2.15 Insert `lead_projects` rows if `project_ids` provided (use service_role for cross-tenant consistency trigger):
    ```typescript
    if (input.project_ids?.length) {
      const rows = input.project_ids.map(pid => ({
        lead_id: lead.id, project_id: pid, tenant_id: tenantId
      }));
      const { error: lpErr } = await serviceClient.from('lead_projects').insert(rows);
      if (lpErr) throw lpErr;
    }
    ```
  - [ ] T-2.16 Call `log_timeline_event` via user-scoped RPC:
    ```typescript
    const { error: tlErr } = await supabase.rpc('log_timeline_event', {
      p_lead_id: lead.id,
      p_event_type: 'lead_created',
      p_payload: {
        status: input.status,
        is_incomplete: isIncomplete,
        has_name: !!input.name?.trim(),
      },
    });
    if (tlErr) throw tlErr;
    ```
  - [ ] T-2.17 Structured log + return `successResponse({lead_id: lead.id, is_incomplete: isIncomplete, status: lead.status, created_at: lead.created_at}, 201)`.
  - [ ] T-2.18 Wrap entire handler in try/catch → `errorResponse('internal_error', ...)` on uncaught throw.
  - [ ] T-2.19 Deploy via `mcp__supabase__deploy_edge_function` (name: `create-lead`).
  - [ ] T-2.20 Smoke test: call `create-lead` with a valid employee JWT and `{status:'hot', phone:'9876543210'}` → expect 201 with `is_incomplete: true`. Verify `lead_timeline` row created via `execute_sql`.

- [ ] **T-3 (AC: 6) — Edge Function `supabase/functions/duplicate-check-override/index.ts`**
  - [ ] T-3.1 Admin-only endpoint for overriding duplicate detection.
  - [ ] T-3.2 Same Zod schema as `create-lead` PLUS `override_reason: z.string().min(1).max(500)`.
  - [ ] T-3.3 After `verifyJwtAndScope`: if `role !== 'admin'` → return 403 `forbidden_role`.
  - [ ] T-3.4 Same phone normalization + phone_hash computation as `create-lead`.
  - [ ] T-3.5 Skip duplicate check (override path — the existing duplicate is intentional).
  - [ ] T-3.6 Same PII encryption + is_incomplete + insert + lead_projects logic as `create-lead`.
  - [ ] T-3.7 Call `log_timeline_event` twice:
    ```typescript
    // First: lead_created
    await supabase.rpc('log_timeline_event', {
      p_lead_id: lead.id, p_event_type: 'lead_created',
      p_payload: { status: input.status, is_incomplete: isIncomplete, override: true },
    });
    // Second: duplicate_override
    await supabase.rpc('log_timeline_event', {
      p_lead_id: lead.id, p_event_type: 'duplicate_override',
      p_payload: { reason: input.override_reason },
    });
    ```
  - [ ] T-3.8 Deploy via `mcp__supabase__deploy_edge_function` (name: `duplicate-check-override`).

- [ ] **T-3b — `pubspec.yaml` update + `result.dart` shared utility**
  - [ ] T-3b.1 Add `uuid: ^4.4.0` to `dependencies` in `apps/mobile/pubspec.yaml`. Used in `lead_repository.dart` for generating `tempId` for Drift drafts. Run `flutter pub get`.
  - [ ] T-3b.2 Create `apps/mobile/lib/shared/error/result.dart` — sealed `Result<T, E>` class (architecture `§Async & Error Patterns`):
    ```dart
    sealed class Result<T, E> {
      const Result();
    }
    final class Ok<T, E> extends Result<T, E> {
      final T value;
      const Ok(this.value);
    }
    final class Err<T, E> extends Result<T, E> {
      final E error;
      const Err(this.error);
    }
    extension ResultX<T, E> on Result<T, E> {
      bool get isOk => this is Ok<T, E>;
      T get unwrap => (this as Ok<T, E>).value;
      E get unwrapErr => (this as Err<T, E>).error;
    }
    ```
  - [ ] T-3b.3 Create `apps/mobile/lib/shared/error/app_error.dart`:
    ```dart
    class AppError {
      final String code;
      final String message;
      final Object? details;
      const AppError({required this.code, required this.message, this.details});
      factory AppError.fromFunctionResponse(FunctionResponse response) {
        final err = (response.data as Map<String, dynamic>?)?['error'] as Map<String, dynamic>?;
        return AppError(
          code: err?['code'] as String? ?? 'internal_error',
          message: err?['message'] as String? ?? 'Unknown error',
          details: err?['details'],
        );
      }
      bool get isDuplicateLead => code == 'duplicate_lead';
    }
    ```

- [ ] **T-4 (domain models) — Flutter `apps/mobile/lib/features/leads/domain/`**
  - [ ] T-4.1 Create `lead_status.dart`:
    ```dart
    enum LeadStatus { warm, cold, hot, dead, sold, future;
      String get label => switch(this) {
        warm => 'Warm', cold => 'Cold', hot => 'Hot',
        dead => 'Dead', sold => 'Sold', future => 'Future',
      };
      bool get isArchived => this == dead || this == sold || this == future;
    }
    ```
  - [ ] T-4.2 Create `lead.dart` — plain Dart class (NOT freezed — no code-gen in this story to keep scope tight):
    ```dart
    class Lead {
      final String id;
      final String tenantId;
      final String? assignedToUserId;
      final LeadStatus status;
      final bool isIncomplete;
      final String? source;
      final String? propertyType;
      final String? location;
      final int? budgetMin;  // paise
      final int? budgetMax;  // paise
      final String? ticketSize;
      final String? remarks;
      final DateTime? visitDate;
      final DateTime? nextFollowupAt;
      final String? interestType;
      final DateTime? lastActionAt;
      final DateTime createdAt;
      final DateTime updatedAt;
      // Note: name_encrypted and phone_encrypted are bytea — decrypted server-side
      // For display, the Edge Function for Story 2.4 will return plaintext name/phone
      final String? displayName;   // decrypted name — null until decrypted by server
      final String? displayPhone;  // decrypted phone — null until decrypted by server
      const Lead({required this.id, required this.tenantId, ...});
      factory Lead.fromJson(Map<String, dynamic> json) { ... }
    }
    ```
    Keep it simple — plain JSON parsing. Freezed code-gen can be added in a later story.

- [ ] **T-5 (AC: 9) — Drift draft table `apps/mobile/lib/features/leads/data/lead_local_db.dart`**
  - [ ] T-5.1 Create Drift database class `LeadLocalDb` with a `LeadDrafts` table:
    ```dart
    class LeadDrafts extends Table {
      IntColumn get localId => integer().autoIncrement()();
      TextColumn get tempId => text().unique()();        // client UUID for correlation
      TextColumn get statusValue => text()();             // LeadStatus.name
      TextColumn get phoneRaw => text()();               // raw phone as entered
      TextColumn get nameRaw => text().nullable()();
      TextColumn get sourceValue => text().nullable()();
      TextColumn get propertyType => text().nullable()();
      TextColumn get locationValue => text().nullable()();
      IntColumn get budgetMin => integer().nullable()();
      IntColumn get budgetMax => integer().nullable()();
      TextColumn get ticketSize => text().nullable()();
      TextColumn get remarks => text().nullable()();
      DateTimeColumn get visitDate => dateTime().nullable()();
      DateTimeColumn get nextFollowupAt => dateTime().nullable()();
      TextColumn get interestType => text().nullable()();
      TextColumn get projectIds => text().nullable()();  // JSON array of UUIDs
      DateTimeColumn get createdLocally => dateTime().withDefault(currentDateAndTime)();
      BoolColumn get synced => boolean().withDefault(const Constant(false))();
      TextColumn get syncedLeadId => text().nullable()();  // server UUID after sync
      TextColumn get syncError => text().nullable()();     // last error message
    }
    ```
  - [ ] T-5.2 `@DriftDatabase(tables: [LeadDrafts])` annotation.
  - [ ] T-5.3 Run `flutter pub run build_runner build --delete-conflicting-outputs` (or note in task that dev agent must run this after file creation).
  - [ ] T-5.4 Wire up in `main.dart` — open database instance, provide via Riverpod.

- [ ] **T-6 (AC: 3, 5, 6, 9, 10) — Lead Repository `apps/mobile/lib/features/leads/data/lead_repository.dart`**
  - [ ] T-6.1 Create `LeadRepository` class:
    ```dart
    class LeadRepository {
      final SupabaseClient _supabase;
      final LeadLocalDb _localDb;
      LeadRepository(this._supabase, this._localDb);
    ```
  - [ ] T-6.2 `createLead({...params}) → Future<Result<Lead, AppError>>`:
    - Write draft to Drift first (NFR-15):
      ```dart
      final tempId = const Uuid().v4();
      await _localDb.into(_localDb.leadDrafts).insert(
        LeadDraftsCompanion.insert(tempId: tempId, statusValue: status.name, phoneRaw: phone, ...),
      );
      ```
    - Call `_supabase.functions.invoke('create-lead', body: {...})`.
    - On success: mark draft synced (`UPDATE leadDrafts SET synced=true, syncedLeadId=leadId WHERE tempId=tempId`).
    - On failure: update `syncError` in draft; return `Result.err(AppError.fromFunctionResponse(response))`.
    - Return `Result.ok(Lead.fromJson(responseData['data']))` on success.
  - [ ] T-6.3 `createLeadWithOverride({...params, required String overrideReason}) → Future<Result<Lead, AppError>>`:
    - Same Drift draft write, then calls `duplicate-check-override` function.
  - [ ] T-6.4 `fetchLeads() → Future<Result<List<Lead>, AppError>>`:
    - Calls `_supabase.from('leads').select('id, status, is_incomplete, last_action_at, created_at').order('created_at', ascending: false)`.
    - Returns list of `Lead` objects. (Minimal — full visibility isolation in Story 2.5.)
  - [ ] T-6.5 `AppError` sealed class (or simple data class) — `{code, message, details}`.
  - [ ] T-6.6 `@riverpod LeadRepository leadRepository(LeadRepositoryRef ref)` — provider at bottom of file.

- [ ] **T-7 (AC: 3, 4) — Providers `apps/mobile/lib/features/leads/providers/lead_list_provider.dart`**
  - [ ] T-7.1 `@riverpod Future<List<Lead>> leadList(LeadListRef ref)` — calls `ref.watch(leadRepositoryProvider).fetchLeads()`.
  - [ ] T-7.2 `@riverpod class CreateLeadNotifier extends _$CreateLeadNotifier` — `AsyncNotifier` that:
    - Exposes `createLead(...)` method.
    - On success: invalidates `leadListProvider`.
    - On error: exposes error state for UI.

- [ ] **T-8 (AC: 1, 2, 3, 4, 5, 6) — Flutter UI**
  - [ ] T-8.1 `apps/mobile/lib/features/leads/ui/status_picker_sheet.dart`
    - Bottom sheet showing 6 status tiles: warm (amber), cold (blue), hot (red), dead (grey), sold (green), future (purple).
    - Each tile: icon + label + color. Tapping → `Navigator.pop(context, selectedStatus)`.
  - [ ] T-8.2 `apps/mobile/lib/features/leads/ui/new_lead_sheet.dart`
    - `DraggableScrollableSheet` or `showModalBottomSheet` fullscreen.
    - **Step 1** (default state): shows `StatusPickerSheet` or inline 6-tile status grid. No other fields rendered until status selected.
    - **Step 2** (status selected): status chip at top (tappable to change) + remaining fields scroll below:
      - Phone (TextFormField, required, keyboard: phone)
      - Name (TextFormField, optional)
      - Source (DropdownButtonFormField: walk_in, referral, associate, ad)
      - Project (multi-select chips — lists from `projects` table, optional)
      - Property Type (TextFormField, optional)
      - Location (TextFormField, optional)
      - Budget Min / Max (TextFormField, INR paise — display in ₹, store in paise)
      - Ticket Size (TextFormField, optional)
      - Remarks (TextFormField, optional, multiline)
      - Visit Date (date+time picker, optional)
      - Next Follow-up (date+time picker, optional)
    - "Save Incomplete" button (always available once status + phone filled).
    - On tap "Save Incomplete": call `ref.read(createLeadNotifierProvider.notifier).createLead(...)`.
    - On 409 `duplicate_lead`:
      - Show error banner: "This lead already exists under [name]"
      - If `role == 'admin'`: show "Override" button → `AlertDialog` for override reason → call `createLeadWithOverride`
      - If `role == 'employee'`: no override option
    - On success: `Navigator.pop(context)` + success SnackBar.
    - On other error: error SnackBar with message.
  - [ ] T-8.3 `apps/mobile/lib/features/leads/ui/lead_card.dart`
    - `Card` widget showing: status pill (colored), display name / "Unnamed Lead", phone (masked or "—"), `isIncomplete` → red "Incomplete" `Chip` badge.
    - Status pill colors: warm=amber, cold=blue, hot=red, dead=grey, sold=green, future=purple.
  - [ ] T-8.4 `apps/mobile/lib/features/leads/ui/lead_list_screen.dart`
    - `Scaffold` with `AppBar("Leads")`.
    - `Consumer` watching `leadListProvider`:
      - Loading: `CircularProgressIndicator`
      - Error: error message with retry button
      - Data: `ListView.builder` of `LeadCard` widgets
    - `FloatingActionButton` with + icon → opens `NewLeadSheet` via `showModalBottomSheet`.
    - Pull-to-refresh: `RefreshIndicator` invalidating `leadListProvider`.

- [ ] **T-9 — Router update `apps/mobile/lib/router/app_router.dart`**
  - [ ] T-9.1 Add `/leads` route: `GoRoute(path: '/leads', builder: (_, __) => const LeadListScreen())`.
  - [ ] T-9.2 Update `HomePlaceholderScreen` to include a button/tile: "View Leads → /leads". (Minimal — home screen fully implemented in Story 3.8.)

- [ ] **T-10 — Smoke tests**
  - [ ] T-10.1 Verify `encrypt_pii('hello')` callable via service_role: `execute_sql` with `SELECT encode(encrypt_pii('hello'), 'hex')` (requires vault secret `lead_pii_key` to be seeded first — see Dev Notes).
  - [ ] T-10.2 Invoke `create-lead` with employee JWT + `{status:'hot', phone:'9876543210'}` → expect 201, `is_incomplete: true`.
  - [ ] T-10.3 Invoke `create-lead` again with same phone → expect 409 `duplicate_lead`.
  - [ ] T-10.4 Invoke `duplicate-check-override` with employee JWT → expect 403 `forbidden_role`.
  - [ ] T-10.5 Invoke `duplicate-check-override` with admin JWT + same phone data + `override_reason:'Client insists'` → expect 201. Verify `lead_timeline` has both `lead_created` and `duplicate_override` rows.
  - [ ] T-10.6 Invoke `create-lead` with `phone:'abc'` → expect 400 `validation_error`.

- [ ] **T-11 — Commit + PR**
  - [ ] T-11.1 Branch: `feat/2.3-employee-creates-lead-quick-capture`.
  - [ ] T-11.2 Stage all new/modified files (see File List in Dev Agent Record).
  - [ ] T-11.3 Commit: `feat(2.3): status-first lead creation with PII encryption and duplicate detection`.
  - [ ] T-11.4 Push + open PR to main.
  - [ ] T-11.5 Update sprint-status.yaml in BOTH locations: `2-3-employee-creates-lead-quick-capture-status-first: review`.

---

## Dev Notes

### Migration Number

**0016** — confirmed: last applied is `0015_cr_patch_lead_timeline.sql`. Do NOT assume 0016 doesn't exist — verify via `Get-ChildItem nirman-crm/supabase/migrations | Sort-Object Name` before writing.

### RLS Pattern — CRITICAL

**IGNORE** the `current_setting('app.current_tenant')` pattern in architecture.md and epics.md AC. This was retired in migration `0003_cr_patch_jwt_only_rls.sql`. All RLS policies since Story 2.1 use:

```sql
USING (tenant_id = public.auth_tenant_id())
WITH CHECK (tenant_id = public.auth_tenant_id())
```

`auth_tenant_id()` reads `auth.jwt() -> 'app_metadata' ->> 'tenant_id'` as UUID.

### UUID Pattern

Architecture says `uuidv7()`. **IGNORE.** Not installed on this project. Use `extensions.gen_random_uuid()` — consistent with all migrations 0001–0015.

### pgcrypto Schema — extensions.pgp_sym_encrypt

All Postgres extensions on this project are installed in the `extensions` schema (see `CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions` in migration 0009). Always call `extensions.pgp_sym_encrypt(...)` not `pgp_sym_encrypt(...)`. With `SET search_path = ''` in the function, schema prefix is mandatory. Same for `extensions.gen_random_uuid()`.

### PII Encryption Design

The `encrypt_pii` DB function in migration 0016 is the encryption boundary. The key (`lead_pii_key`) never leaves the DB/Vault. The Edge Function passes plaintext and receives `bytea`.

**Vault pre-requisite:** The vault secret `lead_pii_key` must be seeded before the first lead can be created. Seeding instruction (run once in Supabase Studio SQL editor or via MCP execute_sql with service role):
```sql
SELECT vault.create_secret('YOUR_AES_PASSPHRASE_HERE', 'lead_pii_key', 'PII encryption key for lead name and phone');
```
If T-10.1 returns `pii_key_missing`, the vault secret is not yet seeded.

**bytea round-trip via PostgREST:** `encrypt_pii()` returns `bytea`. Supabase RPC returns it as `"\\xHEX..."` (hex-prefixed string). When this string is passed back to PostgREST in a `.insert({phone_encrypted: "\\xHEX..."})`, PostgREST correctly stores it as bytea. Do NOT hex-decode or re-encode in TypeScript — pass the string as-is.

### phone_hash Computation

Computed in the Edge Function (not DB). Formula: SHA-256 of the normalized 10-digit phone string, hex-encoded.

```typescript
const encoder = new TextEncoder();
const hashBuf = await crypto.subtle.digest('SHA-256', encoder.encode(normalized));
const phoneHash = Array.from(new Uint8Array(hashBuf))
  .map(b => b.toString(16).padStart(2, '0')).join('');
```

This MUST match `encode(sha256(normalize_phone(raw)::bytea), 'hex')` computed in Postgres. They are equivalent: both SHA-256 of the UTF-8 bytes of the 10-digit string.

### Unique Constraint on phone_hash

Migration `0010_add_phone_hash_unique.sql` added `UNIQUE (tenant_id, phone_hash)`. The duplicate check in T-2.10 is a pre-flight check with better error messages. But the DB constraint is the final guard — if two concurrent requests pass the pre-flight check, one will get `PGCODE 23505` which the Edge Function catches (T-2.14) and re-maps to `duplicate_lead`.

### log_timeline_event Calling Pattern

From Story 2.2 Dev Notes (use user-scoped supabase client so JWT context is preserved):

```typescript
const { error } = await supabase.rpc('log_timeline_event', {
  p_lead_id: leadId,
  p_event_type: 'lead_created',
  p_payload: { status: 'hot', is_incomplete: true }
});
if (error) throw error;
```

The function extracts `tenant_id`, `actor_user_id`, `actor_role` from the JWT automatically. Do NOT pass these as parameters.

### leads Table RLS Policy

Migration 0009 uses `FOR ALL` policy (not separate FOR SELECT/INSERT like lead_timeline). This is correct for leads — employees need SELECT, INSERT, UPDATE on their own leads. The `assigned_to_user_id` filter for visibility isolation is added in Story 2.5.

For the Edge Function, the user-scoped client (from `verifyJwtAndScope`) is used for INSERT into `leads`. RLS checks `tenant_id = auth_tenant_id()`. The service_role client is used for:
- `normalize_phone()` RPC
- `encrypt_pii()` RPC
- `lead_projects` INSERT (to bypass cross-tenant consistency trigger needing to see referenced tables)
- Duplicate check query (must see ALL tenant leads, not just own)

### Riverpod Version — v2, NOT v3

`pubspec.yaml` has `flutter_riverpod: ^2.5.1`, `riverpod_annotation: ^2.3.5`. Architecture claims v3.3.1 — **IGNORE, v2 is what's installed.**

Use v2 syntax:
```dart
// Function-based provider (simple)
@riverpod
LeadRepository leadRepository(LeadRepositoryRef ref) { ... }

// Class-based AsyncNotifier
@riverpod
class CreateLeadNotifier extends _$CreateLeadNotifier {
  @override
  FutureOr<void> build() {}  // initial state
  Future<Result<Lead, AppError>> createLead(...) async { ... }
}
```

The `_$ClassName` base class and `.g.dart` part are generated by `build_runner`. Run `flutter pub run build_runner build --delete-conflicting-outputs` after adding new providers.

### build_runner — Run Once After All Dart Files Written

Drift, Riverpod code generation, and freezed (if used) all require `build_runner`. Run ONCE after all `.dart` files in this story are created (not after each file):

```
flutter pub run build_runner build --delete-conflicting-outputs
```

This generates: `lead_local_db.g.dart`, `lead_repository.g.dart`, `lead_list_provider.g.dart`. Commit generated files — they belong in source control for this project.

### Drift — Database Setup

Drift is already in `pubspec.yaml` (`drift: ^2.20.0`, `drift_flutter: ^0.1.0`). The `@DriftDatabase` annotation generates `lead_local_db.g.dart`. After writing `lead_local_db.dart`, run build_runner. The DB instance must be opened once at app start and provided via Riverpod. Add to `main.dart`:

```dart
final LeadLocalDb leadLocalDb = LeadLocalDb();
// Provide via Riverpod:
@riverpod
LeadLocalDb localDb(LocalDbRef ref) => leadLocalDb;
```

### budget_min / budget_max — Paise Units

Stored as `bigint` (paise). The architecture note (deferred-work.md): "PostgREST returns Postgres bigint as JS string to avoid precision loss". In Dart: the `supabase_flutter` client returns bigint columns as `int` (Dart's int is 64-bit on both Android/iOS). Display: divide by 100, format with `NumberFormat.currency(locale: 'en_IN', symbol: '₹')`.

### name_search — Plaintext (Deliberate)

`name_search` = `name.toLowerCase()` — plaintext stored for pg_trgm admin search (Architecture Decision 22). Set whenever name is provided. This is NOT encrypted by design — admin-only search endpoint (Story 4.3) guards access.

### is_incomplete Logic

A lead is `is_incomplete = false` (complete) only when ALL of these are present:
- `source` (non-null)
- `name` (non-empty after trim)
- `property_type`
- `location`
- `budget_min` (non-null)
- `budget_max` (non-null)
- `ticket_size`
- `project_ids` (at least one)
- `interest_type` — ONLY required if `status === 'future'`

Remarks, visit_date, next_followup_at are optional and do NOT affect `is_incomplete`. For Quick-Capture (just status + phone), is_incomplete = true.

### Edge Function _shared Imports

The `_shared/auth.ts` and `_shared/errors.ts` files already exist at `supabase/functions/_shared/`. Import relative path:
```typescript
import { verifyJwtAndScope, isAuthFailure } from "../_shared/auth.ts";
import { errorResponse, successResponse } from "../_shared/errors.ts";
```

Do NOT copy these files into `create-lead/_shared/` — use the canonical versions.

### duplicate-check-override — Shared Logic

Functions `create-lead` and `duplicate-check-override` share significant logic (normalize, hash, encrypt, insert, lead_projects, timeline). To avoid duplication, consider extracting shared helpers to `supabase/functions/_shared/lead-ops.ts`. If that adds complexity, inline repetition is acceptable for this story — do what's simpler to implement correctly.

### Flutter UI — No UX Document

No UX spec exists (epics.md line 92: "No UX document available at this stage"). Derive UI from PRD behavioral descriptions:
- Status-first: 6 tiles with status colors before any other field
- "Save Incomplete" always available once status + phone present
- Duplicate error: banner + admin-only override button
- Incomplete badge: red chip/badge on lead card
- Budget display: `₹{(paise/100).toStringAsFixed(0)}` with Indian locale thousands separator

Use Material 3 components (`FilledButton`, `OutlinedTextField`, `BottomSheet`, `Chip`, `SnackBar`). No custom design tokens yet (those are in Story design work — use default Material colors for status pills for now).

### Files NOT Touched (Regression Protection)

- All existing migrations 0001–0015
- `supabase/functions/login/`, `bootstrap-admin/`, `create-employee/`, `change-password/`
- `apps/mobile/lib/features/auth/` — no auth changes
- `apps/mobile/lib/features/settings/` — no settings changes
- Existing `app_router.dart` routes (only ADD `/leads` route)
- `packages/shared-types/index.ts` — no schema table change in this story (encrypt_pii is a function, not a table); no type regen needed

### Architecture References Consumed

| Decision | Applied How |
|----------|------------|
| 3 (pgcrypto column-level encryption) | encrypt_pii() SECURITY DEFINER via vault |
| 5 (SQL migrations, roll-forward only) | migration 0016 |
| 6 (Edge Functions for server logic) | create-lead, duplicate-check-override |
| 7 (supabase-js for CRUD + Edge Functions for logic) | lead insert via user-scoped supabase; encrypt/hash via serviceClient |
| 14 (domain_events same-TX via log_timeline_event) | log_timeline_event() RPC call |
| 22 (name_search pg_trgm) | name_search = name.toLowerCase() set at insert |
| 23 (phone_hash SHA-256) | sha256 in Edge Function via crypto.subtle |

### MCP Tools

| Operation | Tool |
|-----------|------|
| Apply migration | `mcp__supabase__apply_migration` (project: `vhgruadourflpxuzuxfn`) |
| Ad-hoc SQL | `mcp__supabase__execute_sql` |
| Deploy Edge Function | `mcp__supabase__deploy_edge_function` |
| Create PR | `mcp__github__create_pull_request` |
| Push files | `mcp__github__push_files` |

## Project Context Reference

- `_bmad-output/planning-artifacts/epics.md` — Story 2.3 AC (lines 352–372), FR-1, FR-2, FR-3, FR-4
- `_bmad-output/planning-artifacts/architecture.md` — Decisions 3, 5, 6, 7, 14, 22, 23; §Edge Function Patterns; §Client Patterns (Mobile)
- `_bmad-output/implementation-artifacts/2-2-lead-timeline-schema-write-helper.md` — log_timeline_event calling pattern, RLS settled pattern, UUID pattern
- `_bmad-output/implementation-artifacts/2-1-lead-schema-normalized-phone-encrypted-pii.md` — leads table schema, normalize_phone, phone_hash, name_search, is_incomplete, bytea columns
- `_bmad-output/implementation-artifacts/deferred-work.md` — bytea TS type deferred (\\x hex string), bigint as string deferred

## Latest Technical Information (verified 2026-05-27)

- `normalize_phone(text)` — live in DB, strips +91/0091/91 prefix + leading 0, returns 10-digit or NULL
- `log_timeline_event(uuid, timeline_event_type, jsonb)` — live in DB (migration 0015 final version), validates lead ownership, P-2 NULL guard, P-4 single timestamp
- `leads_tenant_phone_hash_unique UNIQUE (tenant_id, phone_hash)` — live from migration 0010
- `lead_status` enum: `warm`, `cold`, `hot`, `dead`, `sold`, `future` — live from migration 0009
- `lead_source` enum: `walk_in`, `referral`, `associate`, `ad` — live from migration 0009
- `timeline_event_type` enum includes `lead_created` and `duplicate_override` — live from migration 0012
- Riverpod installed: v2.5.1 (not v3 as in architecture)
- Drift installed: v2.20.0
- `flutter_riverpod` providers use `@riverpod` annotation + `.g.dart` code generation

## Story Completion Status

ready-for-dev — comprehensive developer guide created. Story 2.3 is unblocked.

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-05-27 | Claude (create-story workflow) | Story 2.3 spec created — encrypt_pii migration, create-lead + duplicate-check-override Edge Functions, Flutter status-first UI, Drift draft buffer |

## Dev Agent Record

### Agent Model Used

_to be filled by dev agent_

### Debug Log References

### Completion Notes List

### File List

**NEW:**
- `nirman-crm/apps/mobile/lib/shared/error/result.dart`
- `nirman-crm/apps/mobile/lib/shared/error/app_error.dart`
- `nirman-crm/supabase/migrations/0016_create_encrypt_pii_fn.sql`
- `nirman-crm/supabase/functions/create-lead/index.ts`
- `nirman-crm/supabase/functions/duplicate-check-override/index.ts`
- `nirman-crm/apps/mobile/lib/features/leads/domain/lead_status.dart`
- `nirman-crm/apps/mobile/lib/features/leads/domain/lead.dart`
- `nirman-crm/apps/mobile/lib/features/leads/data/lead_local_db.dart`
- `nirman-crm/apps/mobile/lib/features/leads/data/lead_local_db.g.dart` (generated)
- `nirman-crm/apps/mobile/lib/features/leads/data/lead_repository.dart`
- `nirman-crm/apps/mobile/lib/features/leads/data/lead_repository.g.dart` (generated)
- `nirman-crm/apps/mobile/lib/features/leads/providers/lead_list_provider.dart`
- `nirman-crm/apps/mobile/lib/features/leads/providers/lead_list_provider.g.dart` (generated)
- `nirman-crm/apps/mobile/lib/features/leads/ui/status_picker_sheet.dart`
- `nirman-crm/apps/mobile/lib/features/leads/ui/new_lead_sheet.dart`
- `nirman-crm/apps/mobile/lib/features/leads/ui/lead_card.dart`
- `nirman-crm/apps/mobile/lib/features/leads/ui/lead_list_screen.dart`

**UPDATED:**
- `nirman-crm/apps/mobile/pubspec.yaml` (add uuid: ^4.4.0)
- `nirman-crm/apps/mobile/lib/router/app_router.dart` (add /leads route)
- `nirman-crm/apps/mobile/lib/features/home/ui/home_placeholder_screen.dart` (add navigate-to-leads button)
- `nirman-crm/apps/mobile/lib/main.dart` (open Drift DB + provide via Riverpod)
- `nirman-crm/_bmad-output/implementation-artifacts/sprint-status.yaml`
- `CRM-LMS/_bmad-output/implementation-artifacts/sprint-status.yaml`
