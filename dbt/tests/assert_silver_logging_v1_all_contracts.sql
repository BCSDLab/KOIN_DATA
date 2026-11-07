{{ config(enabled=(var('silver_logging_validation_enabled', false) is sameas true), tags=['silver_logging_v1_fixture']) }}
{% if var('silver_logging_validation_enabled', false) is sameas true %}
{% set scopes=[] %}
{% for p in ['WEB','ANDROID','IOS'] %}{% for n in ['DA1','DA2'] %}
{% do scopes.append({'platform':p,'event_name':n,'start_dt':'2026-10-01','end_dt':'2026-11-30','evidence':'SYNTHETIC ONLY'}) %}
{% endfor %}{% endfor %}
with {{ gold_fixture_ctes() }},
expected as (
 select c.*,n from unnest(array<struct<label string,owner string,category string,platform string,
 service string,stage string,step int64,entry bool,core bool,route string,source string>>[
 {% for r in silver_logging_v1_expected_contracts() %}
 struct('{{ r[0] }}','{{ r[1] }}','{{ r[2] }}','{{ r[3] }}','{{ r[4] }}',
  {{ "'"~r[5]~"'" if r[5] is not none else 'cast(null as string)' }},
  {{ r[6] if r[6] is not none else 'cast(null as int64)' }},
  {{ 'true' if r[7] else 'false' }},{{ 'true' if r[8] else 'false' }},'{{ r[9] }}','{{ r[10] }}'){% if not loop.last %},{% endif %}
 {% endfor %}]) c with offset n
),
inputs as (
 select e.* replace('contract_'||cast(c.n as string) as event_id,c.label as event_label,
 c.owner as event_name,c.category as event_category,c.platform as platform,
 'main' as service_name,'main' as funnel_stage,cast(null as int64) as service_step_order,
 false as is_entry_event,false as is_core_action),
 0 as step_order,'global' as stage_scope,
 if(c.route='mobile_web_category','https://stage.koreatech.in/category',cast(null as string)) as page_location,
 c.n as contract_n
 from fixture_events e cross join expected c where e.event_id='e1'
),
actual as ({{ silver_logging_v1_classify('inputs',scopes) }}),
days as (with {{ gold_common_ctes('actual','fixture_users',false) }} select * from event_user_days)
select 'contract_'||cast(e.n as string) as violation from expected e left join actual a on e.n=a.contract_n
where a.event_id is null or a.service_name is distinct from e.service
 or a.funnel_stage is distinct from e.stage or a.step_order is distinct from e.step
 or a.service_step_order is distinct from e.step or a.is_entry_event is distinct from e.entry
 or a.is_core_action is distinct from e.core or a.stage_scope is distinct from 'service'
 or a.event_label is distinct from e.label or a.event_name is distinct from e.owner
 or a.event_category is distinct from e.category or a.platform is distinct from e.platform
union all
select 'contract_row_count' from unnest([1]) where (select count(*) from actual)!=(select count(*) from expected)
union all
select 'duplicate_contract_event' from unnest([1]) where exists(select event_id from actual group by 1 having count(*)!=1)
union all
select 'nonfunnel_account_dropped' from unnest([1]) where (
 select count(*) from actual where service_name='account' and funnel_stage is null) is distinct from 13
union all
select 'account_any_event_missing' from unnest([1]) where (select max(used_account_flg) from days) is distinct from 1

{% endif %}
