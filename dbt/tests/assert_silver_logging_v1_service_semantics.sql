{{ config(enabled=(var('silver_logging_validation_enabled', false) is sameas true), tags=['silver_logging_v1_fixture']) }}
{% if var('silver_logging_validation_enabled', false) is sameas true %}
{% set scopes=[] %}
{% for p in ['WEB','ANDROID','IOS'] %}{% for n in ['DA1','DA2'] %}
{% do scopes.append({'platform':p,'event_name':n,'start_dt':'2026-10-01','end_dt':'2026-11-30','evidence':'SYNTHETIC ONLY'}) %}
{% endfor %}{% endfor %}
with {{ gold_fixture_ctes() }},
-- Independently selected source-spec boundary cases, not inferred from token suffixes.
cases as (
 select * from unnest(array<struct<label string,owner string,platform string,category string,service string,entry_flag bool>>[
 ('main__main__bus_entry__timetable_entry__click','DA1','ANDROID','click','bus',true),
 ('main__main__bus_entry__ticket_entry__click','DA1','IOS','click','bus',true),
 ('main__main__corner__select','DA1','WEB','select','cafeteria',false),
 ('cafeteria__cafeteria__photo_view__open__click','DA1','ANDROID','click','cafeteria',false),
 ('bus__bus_timetable__shuttle_route__entry__click','DA1','IOS','click','bus',false),
 ('main__main__navigation__main_entry__click','DA2','WEB','click','main',false),
 ('facility__main_category__category_navigation__facility_entry__click','DA2','ANDROID','click','facility',true),
 ('board__notice_search__notice_detail__entry__click','DA2','ANDROID','click','board',false),
 ('course_practice__timetable__course_application__entry__click','DA2','WEB','click','course_practice',true),
 ('shop__footer__shop_entry__footer_entry__click','DA1','WEB','click','shop',true)
 ])
),
inputs as (
 select e.* replace(c.label as event_id,c.label as event_label,c.owner as event_name,
 c.platform as platform,c.category as event_category,'unmapped' as service_name,
 cast(null as string) as funnel_stage,cast(null as int64) as service_step_order,
 false as is_entry_event,false as is_core_action),
 cast(null as int64) as step_order,'service' as stage_scope,cast(null as string) as page_location
 from fixture_events e cross join cases c where e.event_id='e1'
),
mapped as ({{ silver_logging_v1_classify('inputs',scopes) }})
select c.label as violation from cases c left join mapped m on c.label=m.event_id
where m.event_id is null or m.service_name is distinct from c.service
 or m.is_entry_event is distinct from c.entry_flag or m.funnel_stage is not null
 or m.service_step_order is not null or m.is_core_action is distinct from false
{% endif %}
