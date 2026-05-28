-- Story 4.3 — Admin global search by name and phone.
-- Adds: search_leads_global RPC.
-- Phone path: normalize_phone → sha256 hash → phone_hash index (O(1)).
-- Name path: pgp_sym_decrypt + ILIKE, LIMIT p_limit.
-- Branches are EXCLUSIVE — phone branch skips full-table decrypt.
-- Includes archived leads (no status filter).
-- Roll-forward only. Never edit after apply.

CREATE OR REPLACE FUNCTION public.search_leads_global(
  p_q     text,
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  id                  uuid,
  name                text,
  phone_last4         text,
  status              text,
  assigned_to_user_id uuid,
  assignee_username   text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, vault
AS $$
DECLARE
  v_actor_role text := (auth.jwt() -> 'app_metadata') ->> 'role';
  v_tenant_id  uuid := public.auth_tenant_id();
  v_pii_key    text;
  v_q          text;
  v_q_escaped  text;
  v_phone      text;
  v_phone_hash text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF v_actor_role <> 'admin' THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_q := NULLIF(trim(COALESCE(p_q, '')), '');
  IF v_q IS NULL THEN
    RETURN;
  END IF;

  SELECT s.decrypted_secret INTO v_pii_key
    FROM vault.decrypted_secrets s
   WHERE s.name = 'lead_pii_key' LIMIT 1;
  IF v_pii_key IS NULL THEN
    RAISE EXCEPTION 'pii_key_missing';
  END IF;

  -- Determine branch: phone or name.
  v_phone := public.normalize_phone(v_q);
  IF v_phone IS NOT NULL THEN
    -- Phone branch: hash lookup, O(1), decrypt only matching rows.
    v_phone_hash := encode(extensions.digest(v_phone, 'sha256'), 'hex');
    RETURN QUERY
    SELECT
      l.id,
      CASE WHEN l.name_encrypted IS NOT NULL
           THEN extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
           ELSE NULL END                                                 AS name,
      right(extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key), 4) AS phone_last4,
      l.status::text                                                      AS status,
      l.assigned_to_user_id,
      u.email_or_username                                                 AS assignee_username
    FROM public.leads l
    LEFT JOIN public.users u ON u.id = l.assigned_to_user_id
    WHERE l.tenant_id  = v_tenant_id
      AND l.phone_hash = v_phone_hash
    LIMIT p_limit;
  ELSE
    -- Name branch: decrypt + ILIKE across all statuses including archived.
    v_q_escaped := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
    RETURN QUERY
    SELECT
      l.id,
      extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)              AS name,
      right(extensions.pgp_sym_decrypt(l.phone_encrypted, v_pii_key), 4)   AS phone_last4,
      l.status::text                                                         AS status,
      l.assigned_to_user_id,
      u.email_or_username                                                    AS assignee_username
    FROM public.leads l
    LEFT JOIN public.users u ON u.id = l.assigned_to_user_id
    WHERE l.tenant_id      = v_tenant_id
      AND l.name_encrypted IS NOT NULL
      AND extensions.pgp_sym_decrypt(l.name_encrypted, v_pii_key)
            ILIKE '%' || v_q_escaped || '%' ESCAPE '\'
    LIMIT p_limit;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.search_leads_global(text, int) IS
  'Story 4.3 — Admin-only global search. Phone input uses sha256 hash index (O(1)). Name input uses pgp_sym_decrypt + ILIKE. Includes archived leads. Max p_limit rows (default 50).';

REVOKE EXECUTE ON FUNCTION public.search_leads_global(text, int) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.search_leads_global(text, int) TO authenticated;
