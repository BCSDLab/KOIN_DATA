{{ config(enabled=(var('silver_logging_validation_enabled', false) is sameas true), tags=['silver_logging_v1_fixture']) }}
{% if var('silver_logging_validation_enabled', false) is sameas true %}
{% set scopes=[] %}
{% for p in ['WEB','ANDROID','IOS'] %}{% for n in ['DA1','DA2'] %}
{% do scopes.append({'platform':p,'event_name':n,'start_dt':'2026-10-01','end_dt':'2026-11-30','evidence':'SYNTHETIC ONLY'}) %}
{% endfor %}{% endfor %}
with {{ gold_fixture_ctes() }},
catalog as (
 select c.*,n from unnest(array<struct<label string,owner string,category string,
 service string,platform string,entry_flag bool,source_page string>>[
 {% for r in silver_logging_v1_service_catalog() %}
 struct('{{ r[0] }}','{{ r[1] }}','{{ r[2] }}','{{ r[3] }}','{{ r[4] }}',
 {{ 'true' if r[5] else 'false' }},'{{ r[6] }}'){% if not loop.last %},{% endif %}
 {% endfor %}]) c with offset n
),
inputs as (
 select e.* replace('new_'||cast(c.n as string) as event_id,c.label as event_label,
 c.owner as event_name,c.category as event_category,c.platform as platform,
 'unmapped' as service_name,cast(null as string) as funnel_stage,
 cast(null as int64) as service_step_order,false as is_entry_event,false as is_core_action),
 cast(null as int64) as step_order,'service' as stage_scope,
 cast(null as string) as page_location,c.n as contract_n
 from fixture_events e cross join catalog c where e.event_id='e1'
),
mapped as ({{ silver_logging_v1_classify('inputs',scopes) }}),
outside_inputs as (select * replace(date '2026-09-30' as event_dt) from inputs),
outside_mapped as ({{ silver_logging_v1_classify('outside_inputs',scopes) }})
select 'missing_or_wrong_service_'||cast(c.n as string) as violation
from catalog c left join mapped m on c.n=m.contract_n
where m.event_id is null or m.service_name is distinct from c.service
 or m.is_entry_event is distinct from c.entry_flag
 or m.funnel_stage is not null or m.step_order is not null or m.service_step_order is not null
 or m.is_core_action is distinct from false
union all
select 'duplicate_or_dropped_event' from unnest([1]) where
 (select count(*) from mapped)!=(select count(*) from inputs)
 or exists(select event_id from mapped group by 1 having count(*)!=1)
union all
select 'original_fields_changed' from mapped m join inputs e using(event_id)
where to_json_string((select as struct m.* except(service_name,funnel_stage,step_order,
 is_entry_event,is_core_action,stage_scope,service_step_order))) is distinct from
 to_json_string((select as struct e.* except(service_name,funnel_stage,step_order,
 is_entry_event,is_core_action,stage_scope,service_step_order)))
union all
select 'outside_scope_changed' from outside_mapped m join outside_inputs e using(event_id)
where to_json_string(m) is distinct from to_json_string(e)
union all
select 'duplicate_contract' from catalog group by label,owner,category,platform having count(*)!=1
union all
select 'invalid_contract' from catalog where source_page is null
 or not regexp_contains(source_page,r'^[0-9a-f]{32}$')
 or split(label,'__')[safe_offset(array_length(split(label,'__'))-1)]!=category
 or label in ({% for label in silver_logging_v1_frozen_labels() %}'{{ label }}'{% if not loop.last %},{% endif %}{% endfor %})
 or starts_with(label,'team_recruit__') or starts_with(label,'club__') or starts_with(label,'grad_calc__')
{% endif %}
