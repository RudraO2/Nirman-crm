BEGIN;
INSERT INTO public.users (id,tenant_id,role,role_tier,email_or_username,bcrypt_password_hash,is_active) VALUES
 ('00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-000000000001','admin','builder_head','h','x',true),
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-000000000001','employee','front_line_rep','r','x',true),
 ('00000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-000000000001','employee','receptionist','rec','x',true),
 ('00000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-000000000001','employee','front_line_rep','exec','x',true)
ON CONFLICT (id) DO NOTHING;

DO $do$
DECLARE
  v_proj uuid; v_u1 uuid; v_u2 uuid; v_lead uuid; v_code text; v_hold uuid; v_amd uuid; v_n int;
  H_ADMIN text := $j${"sub":"00000000-0000-0000-0000-0000000000e2","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"admin","role_tier":"builder_head"}}$j$;
  H_REP   text := $j${"sub":"00000000-0000-0000-0000-0000000000e1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"front_line_rep"}}$j$;
  H_REC   text := $j${"sub":"00000000-0000-0000-0000-0000000000c1","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"receptionist"}}$j$;
  H_EXEC  text := $j${"sub":"00000000-0000-0000-0000-0000000000d2","app_metadata":{"tenant_id":"00000000-0000-0000-0000-000000000001","role":"employee","role_tier":"front_line_rep"}}$j$;
BEGIN
  SELECT id INTO v_proj FROM public.projects WHERE name='The Velocity' AND tenant_id='00000000-0000-0000-0000-000000000001';
  PERFORM set_config('request.jwt.claims',H_ADMIN,true);
  PERFORM public.generate_unit_grid(v_proj,NULL,1,2,'{"1":"2BHK","2":"3BHK"}',24,650.0,6500000000,4000000000);
  SELECT id INTO v_u1 FROM public.units WHERE project_id=v_proj AND unit_no='101';
  SELECT id INTO v_u2 FROM public.units WHERE project_id=v_proj AND unit_no='102';
  PERFORM public.add_execution_member('00000000-0000-0000-0000-0000000000d2');

  RAISE NOTICE '===== LIFECYCLE A: register -> verify -> hold -> confirm -> amend -> execute =====';
  -- 1 register (rep) with customer code
  PERFORM set_config('request.jwt.claims',H_REP,true);
  v_lead := public.create_lead_with_pii('warm'::lead_status,'walk_in'::lead_source,'9879000001',encode(extensions.digest(public.normalize_phone('9879000001'),'sha256'),'hex'),'Buyer','flat','Pune',5000000,7000000,'2BHK','i',NULL,NULL,'buy',false,NULL,NULL,false);
  SELECT customer_code INTO v_code FROM public.leads WHERE id=v_lead;
  RAISE NOTICE 'A1 registered lead, code=%', v_code;
  -- 2 reception verifies visit
  PERFORM set_config('request.jwt.claims',H_REC,true);
  PERFORM public.verify_visit(v_code);
  RAISE NOTICE 'A2 visit verified, visit_count=%(exp 1)', (SELECT visit_count FROM public.leads WHERE id=v_lead);
  -- 3 rep holds unit
  PERFORM set_config('request.jwt.claims',H_REP,true);
  v_hold := (public.hold_unit(v_u1, v_lead))->>'hold_id';
  RAISE NOTICE 'A3 unit held, unit_status=%(exp hold)', (SELECT status FROM public.units WHERE id=v_u1);
  -- 4 head confirms booking
  PERFORM set_config('request.jwt.claims',H_ADMIN,true);
  PERFORM public.confirm_booking(v_hold, true);
  RAISE NOTICE 'A4 booking confirmed, unit=%(exp sold) lead=%(exp sold)',
    (SELECT status FROM public.units WHERE id=v_u1), (SELECT status FROM public.leads WHERE id=v_lead);
  -- 5 rep logs amendment on sold unit
  PERFORM set_config('request.jwt.claims',H_REP,true);
  v_amd := public.log_amendment(v_u1, v_lead, 'Upgrade to imported marble');
  RAISE NOTICE 'A5 amendment logged status=%(exp requested)', (SELECT status FROM public.amendments WHERE id=v_amd);
  -- 6 execution member walks the lifecycle to done
  PERFORM set_config('request.jwt.claims',H_EXEC,true);
  PERFORM public.set_amendment_status(v_amd,'acknowledged');
  PERFORM public.set_amendment_status(v_amd,'in_progress');
  PERFORM public.set_amendment_status(v_amd,'done');
  RAISE NOTICE 'A6 amendment final status=%(exp done) status_events=%(exp 3)',
    (SELECT status FROM public.amendments WHERE id=v_amd),
    (SELECT count(*) FROM public.amendment_events WHERE amendment_id=v_amd AND event_type='status_changed');
  -- 7 audit trail across epics (domain_events)
  RAISE NOTICE 'A7 domain_events: code_generated=% visit_verified=% status_changed(sold via timeline)=% amendment_logged=% amendment_status_changed=%',
    (SELECT count(*) FROM public.domain_events WHERE event_type='code_generated' AND payload->>'lead_id'=v_lead::text),
    (SELECT count(*) FROM public.domain_events WHERE event_type='visit_verified' AND payload->>'lead_id'=v_lead::text),
    (SELECT count(*) FROM public.lead_timeline WHERE lead_id=v_lead AND event_type='status_changed' AND payload->>'to'='sold'),
    (SELECT count(*) FROM public.domain_events WHERE event_type='amendment_logged' AND payload->>'amendment_id'=v_amd::text),
    (SELECT count(*) FROM public.domain_events WHERE event_type='amendment_status_changed' AND payload->>'amendment_id'=v_amd::text);

  RAISE NOTICE '===== LIFECYCLE B: hold -> expire (cron) -> release -> re-hold =====';
  PERFORM set_config('request.jwt.claims',H_REP,true);
  PERFORM public.hold_unit(v_u2, v_lead);
  UPDATE public.unit_holds SET expires_at=now()-interval '1 min' WHERE unit_id=v_u2 AND released_at IS NULL;
  v_n := public.release_expired_holds();
  RAISE NOTICE 'B1 released=%(exp>=1) unit2=%(exp available) hold_outcome=%(exp expired)',
    v_n, (SELECT status FROM public.units WHERE id=v_u2), (SELECT outcome FROM public.unit_holds WHERE unit_id=v_u2 ORDER BY held_at DESC LIMIT 1);
  PERFORM public.hold_unit(v_u2, v_lead);
  RAISE NOTICE 'B2 re-hold after expiry, unit2=%(exp hold)', (SELECT status FROM public.units WHERE id=v_u2);
END
$do$;
ROLLBACK;
