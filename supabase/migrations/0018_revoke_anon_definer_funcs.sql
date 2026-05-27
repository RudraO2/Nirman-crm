-- Story 2.5 — Lock SECURITY DEFINER RPCs to authenticated role only.
-- Advisor warned: anon role could call get_my_leads / create_lead_with_pii.
-- Bodies already raise 'not_authenticated' on null auth.uid(), but defense-in-depth.

REVOKE EXECUTE ON FUNCTION public.get_my_leads(int, int) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_lead_with_pii(
  public.lead_status,
  public.lead_source,
  text, text, text, text, text, bigint, bigint,
  text, text, timestamptz, timestamptz, text, boolean
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_my_leads(int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_lead_with_pii(
  public.lead_status,
  public.lead_source,
  text, text, text, text, text, bigint, bigint,
  text, text, timestamptz, timestamptz, text, boolean
) TO authenticated;
