{{ config(enabled=(var('silver_logging_validation_enabled', false) is sameas true), tags=['silver_logging_v1_fixture']) }}
{% if var('silver_logging_validation_enabled', false) is sameas true %}
{% set scopes=[] %}
{% for p in ['WEB','ANDROID','IOS'] %}{% for n in ['DA1','DA2'] %}
{% do scopes.append({'platform':p,'event_name':n,'start_dt':'2026-10-01','end_dt':'2026-11-30','evidence':'SYNTHETIC ONLY'}) %}
{% endfor %}{% endfor %}
with {{ silver_logging_v1_fixture_ctes() }},
mapped as ({{ silver_logging_v1_classify('mock_events',scopes,silver_logging_v1_fixture_legacy(),true) }})
select 'mapping_'||event_id as violation from mapped
where service_name is distinct from expected_service
  or funnel_stage is distinct from expected_stage or step_order is distinct from expected_order
union all
select 'row_count' from unnest([1]) where (select count(*) from mapped)!=(select count(*) from mock_events)
union all
select 'duplicate_event' from unnest([1]) where exists(
  select event_id from mapped group by 1 having count(*)!=1)
union all
select 'raw_label_changed' from unnest([1]) where exists(
 select 1 from mapped m join mock_events e using(event_id)
 where m.event_label is distinct from e.event_label or m.event_category is distinct from e.event_category
   or m.user_pseudo_id is distinct from e.user_pseudo_id or m.ga_session_id is distinct from e.ga_session_id)
union all
select 'frozen_or_legacy_changed' from unnest([1]) where exists(
 select 1 from mapped m join mock_events e using(event_id)
 where (regexp_contains(m.event_id,r'^frozen_[0-6]$') or m.event_id='legacy')
 and to_json_string(struct(m.service_name,m.funnel_stage,m.step_order,m.is_entry_event,
   m.is_core_action,m.stage_scope,m.service_step_order)) is distinct from
   to_json_string(struct(e.service_name,e.funnel_stage,e.step_order,e.is_entry_event,
   e.is_core_action,e.stage_scope,e.service_step_order)))

{% endif %}
