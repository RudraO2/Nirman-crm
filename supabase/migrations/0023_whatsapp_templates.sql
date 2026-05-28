-- Story 3.3 / 3.4 — WhatsApp templates (admin-managed, max 3 per tenant)
-- Admin writes via authenticated role + role='admin' JWT check.
-- Employees read to populate the WhatsApp template picker.
-- Roll-forward only. Never edit after apply.

CREATE TABLE IF NOT EXISTS public.whatsapp_templates (
  id         uuid        PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  tenant_id  uuid        NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  name       text        NOT NULL,
  body       text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.whatsapp_templates IS
  'Story 3.3 — Admin-managed WhatsApp message templates. Max 3 per tenant enforced by trigger.';

CREATE TRIGGER whatsapp_templates_set_updated_at
  BEFORE UPDATE ON public.whatsapp_templates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 3-template limit ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._check_whatsapp_template_limit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF (
    SELECT COUNT(*)
      FROM public.whatsapp_templates
     WHERE tenant_id = NEW.tenant_id
  ) >= 3 THEN
    RAISE EXCEPTION 'template_limit_exceeded'
      USING HINT = 'Maximum 3 templates allowed per tenant.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER whatsapp_templates_limit_check
  BEFORE INSERT ON public.whatsapp_templates
  FOR EACH ROW EXECUTE FUNCTION public._check_whatsapp_template_limit();

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE public.whatsapp_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.whatsapp_templates FORCE  ROW LEVEL SECURITY;

-- Employees and admins can read their tenant's templates
CREATE POLICY whatsapp_templates_select
  ON public.whatsapp_templates
  FOR SELECT TO authenticated
  USING (tenant_id = public.auth_tenant_id());

-- Only admins can write
CREATE POLICY whatsapp_templates_admin_write
  ON public.whatsapp_templates
  FOR ALL TO authenticated
  USING      (tenant_id = public.auth_tenant_id() AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin')
  WITH CHECK (tenant_id = public.auth_tenant_id() AND (auth.jwt() -> 'app_metadata') ->> 'role' = 'admin');

GRANT SELECT ON public.whatsapp_templates TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.whatsapp_templates TO authenticated;

-- ── Index ─────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS whatsapp_templates_tenant_id_idx
  ON public.whatsapp_templates (tenant_id);
