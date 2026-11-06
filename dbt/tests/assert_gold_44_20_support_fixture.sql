{{ config(tags=['gold_44_20_fixture']) }}
{% set fixture={'build_id':'support_fixture','snapshot_at':'2026-12-01T00:00:00Z','computed_at':'2026-12-01T00:00:00Z','logging_start_dt':'2026-10-01','event_complete_start_dt':'2026-10-01','event_complete_dt':'2026-11-30','metric_start_dt':'2026-10-01','metric_end_dt':'2026-11-30','coverage_verified':true,'signup_verified':true,'mapping_verified':true,'session_verified':true,'main_visit_platforms':['WEB','ANDROID','IOS'],'main_visit_verified':true,'funnel_support_verified':true,'session_inactivity_minutes':30,'late_arrival_hours':0} %}
{% set no_main=fixture.copy() %}{% do no_main.update({'main_visit_verified':false}) %}
with {{ gold_fixture_ctes() }},
support as ({{ gold_funnel_support() }}),
unsupported_events as (
 select e.* replace(
   x.pseudo as user_pseudo_id,x.platform as platform,
   if(e.service_name='shop',x.service,e.service_name) as service_name,
   case when e.funnel_stage='shop_view' then 'explore' when e.funnel_stage='call'
     then x.last_stage else e.funnel_stage end as funnel_stage)
 from fixture_events e cross join unnest([
   struct('u4' as pseudo,'WEB' as platform,'cafeteria' as service,'share' as last_stage),
   struct('u5','ANDROID','timetable','save'),struct('u6','WEB','board','read')]) x
 where e.user_pseudo_id='u4'
),
u as ({{ gold_user_query('unsupported_events','fixture_users',false,fixture) }}),
no_main_users as ({{ gold_user_query('fixture_events','fixture_users',false,no_main) }})
select 'support_inventory' as violation from unnest([1]) where (select count(*) from support)!=18
union all
select 'signup_must_remain_unsupported' from unnest([1]) where exists(
 select 1 from support where funnel_id='signup' and supported)
union all
select 'unsupported_session_accepted' from unnest([1]) where exists(
 select 1 from u cross join unnest(funnel_session_facts) f where f.is_complete and f.funnel_id=case user_pseudo_id
   when 'u4' then 'cafeteria' when 'u5' then 'timetable' when 'u6' then 'board' end)
union all
select 'missing_main_gate_bypassed' from unnest([1]) where exists(
 select 1 from no_main_users cross join unnest(funnel_session_facts) f
 where f.funnel_id!='signup' and f.is_complete)
union all
select 'unsupported_should_be_na' from unnest([1]) where (
 select case when countif(f.is_complete)=0 then cast(null as int64)
 else count(distinct if(f.is_complete,user_pseudo_id,null)) end
 from u cross join unnest(funnel_session_facts) f
 where f.funnel_id=case user_pseudo_id when 'u4' then 'cafeteria'
 when 'u5' then 'timetable' when 'u6' then 'board' end) is not null
