BEGIN;
-- two tenants
INSERT INTO public.tenants (id,name,timezone) VALUES ('00000000-0000-0000-0000-000000000002','T2','Asia/Kolkata') ON CONFLICT DO NOTHING;
INSERT INTO public.projects (tenant_id,name) VALUES ('00000000-0000-0000-0000-000000000002','T2 Project') ON CONFLICT DO NOTHING;
INSERT INTO public.agencies (id,tenant_id,name) VALUES ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000001','PCo') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id,tenant_id,role,role_tier,email_or_username,bcrypt_password_hash,is_active,is_external,agency_id) VALUES
 ('00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-000000000001','admin','builder_head','h1','x',true,false,NULL),
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000001','employee','front_line_rep','r1','x',true,false,NULL),
 ('00000000-0000-0000-0000-00000000f1f1','00000000-0000-0000-0000-000000000001','employee','partner_agency','p1','x',true,true,'00000000-0000-0000-0000-0000000000a1')
ON CONFLICT (id) DO NOTHING;

DO $do$
DECLARE
  v_proj uuid; v_proj2 uuid; v_u1 uuid; v_lead uuid; v_lead_p uuid; v_res jsonb; v_err text; v_status text;
BEGIN
  SELECT id INTO v_proj  FROM public.projects WHERE name='The Velocity' AND tenant_id='00000000-0000-0000-0000-000000000001';
  SELECT id INTO v_proj2 FROM public.projects WHERE name='T2 Project'   AND tenant_id='00000000-0000-0000-0000-000000000002';
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"admin","role_tier":"builder_head"}}$j$,true);
  PERFORM public.generate_unit_grid(v_proj, NULL, 1, 2, '{"1":"2BHK","2":"2BHK"}', 24, 650.0, 6500000000, 4000000000);
  SELECT id INTO v_u1 FROM public.units WHERE project_id=v_proj AND unit_no='101';

  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"front_line_rep"}}$j$,true);
  v_lead := public.create_lead_with_pii('warm'::lead_status,'walk_in'::lead_source,'9870000001',encode(extensions.digest(public.normalize_phone('9870000001'),'sha256'),'hex'),'L','flat','P',1,2,'2BHK','i',NULL,NULL,'buy',false,NULL,NULL,false);

  -- ===== BUG1: force_release of a HELD unit — does it orphan the hold row? =====
  PERFORM public.hold_unit(v_u1, v_lead);                       -- unit hold, active hold row
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"admin","role_tier":"builder_head"}}$j$,true);
  PERFORM public.change_unit_inventory_state(v_u1,'force_release',NULL);  -- unit -> available
  RAISE NOTICE 'BUG1 after force_release: unit_status=% active_holds_on_unit=%(BUG if >0 while available)',
    (SELECT status FROM public.units WHERE id=v_u1),
    (SELECT count(*) FROM public.unit_holds WHERE unit_id=v_u1 AND released_at IS NULL);
  -- try to re-hold the now-"available" unit
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"front_line_rep"}}$j$,true);
  BEGIN
    PERFORM public.hold_unit(v_u1, v_lead);
    RAISE NOTICE 'BUG1 re-hold: SUCCEEDED (good — no orphan)';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'BUG1 re-hold: FAILED [%] % <-- ORPHAN HOLD BUG (unit available but unholdable)', SQLSTATE, SQLERRM; END;

  -- ===== cross-tenant: rep of T1 holds a unit in T2 =====
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"front_line_rep"}}$j$,true);
  BEGIN
    PERFORM public.get_project_units(v_proj2);
    RAISE NOTICE 'XT1 FAIL: saw other-tenant project units';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'XT1 PASS: cross-tenant get_project_units denied [%]', SQLSTATE; END;

  -- ===== partner holds a unit in a project NOT shared to their agency =====
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-00000000f1f1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"partner_agency"}}$j$,true);
  v_lead_p := public.create_lead_with_pii('warm'::lead_status,'walk_in'::lead_source,'9870000009',encode(extensions.digest(public.normalize_phone('9870000009'),'sha256'),'hex'),'PL','flat','P',1,2,'2BHK','i',NULL,NULL,'buy',false,NULL,NULL,false);
  SELECT id INTO v_u1 FROM public.units WHERE project_id=v_proj AND unit_no='102';
  BEGIN
    PERFORM public.hold_unit(v_u1, v_lead_p);  -- project NOT shared to agency a1
    RAISE NOTICE 'PScope: partner HELD a unit in a NON-shared project (status=%) <-- review: should partner holds be gated to shared projects?', (SELECT status FROM public.units WHERE id=v_u1);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'PScope: partner hold in non-shared project denied [%] %', SQLSTATE, SQLERRM; END;

  -- ===== amendment for a lead that does NOT hold the unit =====
  -- u101 currently held by v_lead (re-held above, if bug fixed) OR available. Make a clean held unit by lead e1:
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"front_line_rep"}}$j$,true);
  -- e1 logs amendment against u102 (held/attempted by partner) for e1's OWN lead (e1 lead does NOT hold u102)
  BEGIN
    PERFORM public.log_amendment(v_u1, v_lead, 'grill');
    RAISE NOTICE 'AmdLink: amendment logged for a lead NOT linked to the unit hold (status=%) <-- review: should amendment require the lead actually holds/booked the unit?', (SELECT status FROM public.units WHERE id=v_u1);
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'AmdLink: rejected [%] %', SQLSTATE, SQLERRM; END;
END
$do$;
ROLLBACK;
