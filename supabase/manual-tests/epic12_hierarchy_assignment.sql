BEGIN;
INSERT INTO public.agencies (id,tenant_id,name) VALUES ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-000000000001','PCo') ON CONFLICT DO NOTHING;
INSERT INTO public.users (id,tenant_id,role,role_tier,email_or_username,bcrypt_password_hash,is_active) VALUES
 ('00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-000000000001','admin','builder_head','h','x',true),
 ('00000000-0000-0000-0000-0000000000e4','00000000-0000-0000-0000-000000000001','employee','team_leader','l','x',true),
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000001','employee','front_line_rep','r1','x',true)
ON CONFLICT (id) DO NOTHING;

-- T1 auth_role_tier fallback (claim absent -> derive from coarse role)
SELECT set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"admin"}}$j$,true);
SELECT 'T1a admin->'||public.auth_role_tier()||' (exp builder_head)';
SELECT set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee"}}$j$,true);
SELECT 'T1b employee->'||public.auth_role_tier()||' (exp front_line_rep)';
SELECT set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"team_leader"}}$j$,true);
SELECT 'T1c explicit claim->'||public.auth_role_tier()||' (exp team_leader, claim overrides)';

DO $do$
DECLARE v_lead uuid;
BEGIN
  -- admin context
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"admin","role_tier":"builder_head"}}$j$,true);

  -- T2 partner without agency -> agency_required_for_partner
  BEGIN PERFORM public.set_user_hierarchy('00000000-0000-0000-0000-0000000000e1','partner_agency',NULL,NULL);
    RAISE NOTICE 'T2 FAIL: partner set without agency';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'T2 PASS: partner-needs-agency [%] %', SQLSTATE, SQLERRM; END;

  -- T3 valid: rep e1 reports_to leader e4
  PERFORM public.set_user_hierarchy('00000000-0000-0000-0000-0000000000e1','front_line_rep','00000000-0000-0000-0000-0000000000e4',NULL);
  RAISE NOTICE 'T3 PASS: rep reports_to leader set; reports_to=%', (SELECT reports_to_user_id FROM public.users WHERE id='00000000-0000-0000-0000-0000000000e1');

  -- T4 cycle: leader e4 reports_to rep e1 (who reports to e4) -> cycle
  BEGIN PERFORM public.set_user_hierarchy('00000000-0000-0000-0000-0000000000e4','team_leader','00000000-0000-0000-0000-0000000000e1',NULL);
    RAISE NOTICE 'T4 FAIL: cycle allowed';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'T4 PASS: cycle rejected [%] %', SQLSTATE, SQLERRM; END;

  -- T5 non-admin caller denied
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"team_leader"}}$j$,true);
  BEGIN PERFORM public.set_user_hierarchy('00000000-0000-0000-0000-0000000000e1','front_line_rep','00000000-0000-0000-0000-0000000000e4',NULL);
    RAISE NOTICE 'T5 FAIL: non-admin set hierarchy';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'T5 PASS: non-admin denied [%]', SQLSTATE; END;

  -- T6 assign_lead: target must be front_line_rep
  PERFORM set_config('request.jwt.claims',$j${"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"admin","role_tier":"builder_head"}}$j$,true);
  v_lead := public.create_lead_with_pii('warm'::lead_status,'walk_in'::lead_source,'9872000001',encode(extensions.digest(public.normalize_phone('9872000001'),'sha256'),'hex'),'X','flat','P',1,2,'2BHK','i',NULL,NULL,'buy',false,NULL,NULL,false);
  BEGIN PERFORM public.assign_lead(v_lead,'00000000-0000-0000-0000-0000000000e4',NULL);
    RAISE NOTICE 'T6a FAIL: assigned to a team_leader';
  EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'T6a PASS: assign to non-rep rejected [%] %', SQLSTATE, SQLERRM; END;
  PERFORM public.assign_lead(v_lead,'00000000-0000-0000-0000-0000000000e1',NULL);
  RAISE NOTICE 'T6b PASS: assigned to front_line_rep; owner=%', (SELECT assigned_to_user_id FROM public.leads WHERE id=v_lead);

  -- T7 list_employees_for_assignment returns only front_line_reps
  RAISE NOTICE 'T7 assignable list size=% all_rep=%',
    (SELECT count(*) FROM public.list_employees_for_assignment()),
    (SELECT bool_and(u.role_tier='front_line_rep') FROM public.list_employees_for_assignment() le JOIN public.users u ON u.id=le.id);
END
$do$;
ROLLBACK;
