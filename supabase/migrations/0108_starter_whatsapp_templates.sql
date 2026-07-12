-- 0108_starter_whatsapp_templates.sql
-- Story 8.6 — starter WhatsApp templates on tenant create.
--
-- A freshly provisioned builder opened the template picker empty; the admin had
-- to author all 3 templates before reps could send anything. Seed 3 sensible
-- starters (intro / visit invite / follow-up) at tenant-creation time.
--
-- Implemented as an AFTER INSERT trigger on public.tenants (not a provision_tenant
-- edit) so EVERY creation path gets them — ops provisioning (0091) today, the
-- deferred self-serve signup (8.3) later — with zero coordination. The trigger fn:
--   * seeds only when the tenant has no templates yet (idempotent, never fights
--     the 0023 3-template cap);
--   * uses only tokens from the shipped catalog (lead_model.dart tokenCatalog /
--     admin /templates chips): name, project, followup_date, agent_name.
-- Existing tenants are deliberately untouched (they already authored their own).
-- File-based migration; never MCP apply.

BEGIN;

CREATE OR REPLACE FUNCTION public._seed_starter_whatsapp_templates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.whatsapp_templates WHERE tenant_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.whatsapp_templates (tenant_id, name, body) VALUES
    (NEW.id, 'Introduction',
     'Namaste {{name}} ji! Main {{agent_name}}, {{project}} se. Aapki enquiry mili — property ke baare mein baat karne ke liye kab call kar sakta/sakti hoon?'),
    (NEW.id, 'Site visit invite',
     'Namaste {{name}} ji! {{project}} ka site visit aapke liye schedule ho sakta hai. Aap kab aa sakte hain? Location aur timing main bhej dunga/dungi. — {{agent_name}}'),
    (NEW.id, 'Follow-up',
     'Namaste {{name}} ji, {{agent_name}} yahan. {{project}} ke baare mein aapse {{followup_date}} ko baat karni thi. Koi bhi sawaal ho toh zaroor bataiye!');

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._seed_starter_whatsapp_templates() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tenants_seed_starter_templates ON public.tenants;
CREATE TRIGGER tenants_seed_starter_templates
  AFTER INSERT ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public._seed_starter_whatsapp_templates();

COMMENT ON FUNCTION public._seed_starter_whatsapp_templates() IS
  'Story 8.6 — seeds 3 starter WhatsApp templates (intro/visit/follow-up, shipped-token catalog only) for every newly created tenant, on any creation path. No-op if the tenant already has templates.';

COMMIT;
