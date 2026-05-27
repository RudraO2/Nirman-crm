-- Story 2.1 (review patches P1+P2) — Lead integrity constraints
-- P1: lead_projects cross-tenant consistency trigger (code review finding)
-- P2: budget_min/budget_max non-negative and ordered CHECK constraints (code review finding)
--
-- Roll-forward only. Never edit after apply.

-- ────────────────────────────────────────────────────────────────────────────
-- P2: Budget CHECK constraints on leads
-- Enforces non-negative values and min ≤ max at DB layer.
-- Edge Function Zod is the primary guard; these are last-resort DB safety nets.
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.leads
  ADD CONSTRAINT leads_budget_min_nonneg
    CHECK (budget_min IS NULL OR budget_min >= 0),
  ADD CONSTRAINT leads_budget_max_nonneg
    CHECK (budget_max IS NULL OR budget_max >= 0),
  ADD CONSTRAINT leads_budget_range
    CHECK (budget_min IS NULL OR budget_max IS NULL OR budget_min <= budget_max);

COMMENT ON CONSTRAINT leads_budget_min_nonneg ON public.leads IS
  'Story 2.1 review — Budget stored in paise; must be non-negative.';
COMMENT ON CONSTRAINT leads_budget_range ON public.leads IS
  'Story 2.1 review — budget_min must not exceed budget_max.';

-- ────────────────────────────────────────────────────────────────────────────
-- P1: lead_projects cross-tenant consistency trigger
-- Validates that the referenced lead and project both belong to the same tenant
-- as lead_projects.tenant_id. RLS alone cannot enforce this because FK resolution
-- does not apply RLS on the parent table during INSERT.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_lead_projects_tenant_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  lead_tenant   uuid;
  project_tenant uuid;
BEGIN
  SELECT tenant_id INTO lead_tenant
    FROM public.leads WHERE id = NEW.lead_id;

  SELECT tenant_id INTO project_tenant
    FROM public.projects WHERE id = NEW.project_id;

  IF lead_tenant IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'lead_projects: lead tenant_id mismatch (expected %, got %)',
      NEW.tenant_id, lead_tenant
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF project_tenant IS DISTINCT FROM NEW.tenant_id THEN
    RAISE EXCEPTION 'lead_projects: project tenant_id mismatch (expected %, got %)',
      NEW.tenant_id, project_tenant
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.check_lead_projects_tenant_consistency() IS
  'Story 2.1 review — BEFORE INSERT/UPDATE trigger on lead_projects: asserts that referenced lead and project belong to the same tenant as lead_projects.tenant_id.';

CREATE TRIGGER lead_projects_check_tenant_consistency
  BEFORE INSERT OR UPDATE ON public.lead_projects
  FOR EACH ROW EXECUTE FUNCTION public.check_lead_projects_tenant_consistency();
