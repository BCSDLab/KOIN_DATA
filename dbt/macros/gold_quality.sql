{# Explicit deployment scopes, never inferred from observed MIN/MAX.
   No verified SDK-version field exists in Silver; mixed versions require exact
   evidence-backed legacy contracts. This does not classify services. #}
{% macro gold_naming_ctes(overrides={}) %}
{% set p = gold_settings(overrides) %}
naming_scopes as (
  select * from unnest(array<struct<platform string,event_name string,start_dt date,end_dt date>>[
  {% for s in p.get('naming_scopes', []) %}
    struct('{{ s.platform }}','{{ s.event_name }}',date('{{ s.start_dt }}'),date('{{ s.end_dt }}')){% if not loop.last %},{% endif %}
  {% endfor %}
  ])
),
approved_legacy_labels as (
  select * from unnest(array<struct<platform string,event_name string,event_label string,event_category string>>[
  {% for s in p.get('approved_legacy_labels', []) %}
    struct('{{ s.platform }}','{{ s.event_name }}','{{ s.event_label }}','{{ s.event_category }}'){% if not loop.last %},{% endif %}
  {% endfor %}
  ])
),
naming_audit as (
  select e.*,
    case
      when e.event_name not in ('DA1','DA2') then 'not_da'
      when not exists(select 1 from naming_scopes s where s.platform=e.platform
        and s.event_name=e.event_name and e.event_dt between s.start_dt and s.end_dt) then 'outside_scope'
      -- Notion naming v1 section 3-2: exact approved result exception only.
      when e.event_name='DA1' and e.event_label='cafeteria__cafeteria__soldout_submit'
        and e.event_category in ('submit','fail') then 'approved_frozen'
      when exists(select 1 from approved_legacy_labels a where a.platform=e.platform
        and a.event_name=e.event_name and a.event_label=e.event_label
        and a.event_category=e.event_category) then 'approved_legacy'
      when regexp_contains(e.event_label,
        r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*(?:__[a-z][a-z0-9]*(?:_[a-z0-9]+)*){3,4}$')
        and split(e.event_label,'__')[safe_offset(array_length(split(e.event_label,'__'))-1)]=e.event_category
        and e.event_category in ('click','select','scroll','swipe','submit','fail','exposure','toggle')
        then 'general'
      else 'invalid'
    end as naming_status
  from silver_events e
)
{% endmacro %}

{% macro gold_funnel_target(alias='e') %}
(
  ({{ alias }}.service_name='main' and {{ alias }}.funnel_stage='main')
  or ({{ alias }}.service_name='account' and {{ alias }}.funnel_stage in
    ('signup_start','terms_agreement','identity_verification','form_entry','signup_complete'))
  or ({{ alias }}.service_name in ('shop','bus','cafeteria','timetable','board')
    and {{ alias }}.service_step_order between 1 and 3)
)
{% endmacro %}

{% macro gold_input_quality(event_relation=none,user_relation=none,frozen=true,overrides={}) %}
with {{ gold_common_ctes(event_relation,user_relation,frozen,overrides) }},
{{ gold_naming_ctes(overrides) }},
reasons as (
  select e.event_dt,e.platform,e.user_pseudo_id,'naming_'||e.naming_status as reason
  from naming_audit e
  union all
  select e.event_dt,e.platform,e.user_pseudo_id,
    case when e.ga_session_id is null then 'funnel_session_key_missing'
      else 'funnel_session_key_invalid' end
  from silver_events e where {{ gold_funnel_target('e') }}
    and coalesce(safe_cast(e.ga_session_id as int64)>0,false)=false
  union all
  select e.event_dt,e.platform,e.user_pseudo_id,'funnel_unsupported__'||s.funnel_id
  from silver_events e join ({{ gold_funnel_support() }}) s on s.platform=e.platform and not s.supported
  where (s.funnel_id!='signup' and (e.service_name=s.funnel_id or
    (e.service_name='main' and e.funnel_stage='main')))
    or (s.funnel_id='signup' and e.service_name='account' and
      (e.label_feature='sign_up' or e.funnel_stage in
       ('signup_start','terms_agreement','identity_verification','form_entry','signup_complete')))
  union all
  select e.event_dt,e.platform,e.user_pseudo_id,'main_visit_unverified'
  from silver_events e cross join gold_parameters p
  where (not p.main_visit_verified or e.platform not in unnest(p.main_visit_platforms))
    and e.service_name='main' and e.funnel_stage='main'
  union all
  select e.event_dt,e.platform,e.user_pseudo_id,'funnel_entry_path_unverified__cafeteria'
  from silver_events e where e.platform='IOS' and e.event_name='DA1'
    and e.event_label='main__main__more__click'
  union all
  select e.event_dt,e.platform,e.user_pseudo_id,'funnel_session_key_excluded'
  from silver_events e where {{ gold_funnel_target('e') }}
    and coalesce(safe_cast(e.ga_session_id as int64)>0,false)=false
)
select p.build_id,p.snapshot_at as user_snapshot_at,r.event_dt,r.platform,r.reason,
  if(grouping(r.event_dt)=1,'whole_input','day_platform') as aggregation_level,
  count(*) as event_count,count(distinct r.user_pseudo_id) as distinct_users
from reasons r cross join gold_parameters p
group by grouping sets ((p.build_id,p.snapshot_at,r.event_dt,r.platform,r.reason),
  (p.build_id,p.snapshot_at,r.reason))
{% endmacro %}

{% macro gold_naming_validation() %}
with {{ gold_common_ctes() }}, {{ gold_naming_ctes() }}
select 'invalid_new_label' as violation,count(*) as failures from naming_audit
where naming_status='invalid' having count(*)>0
union all
select 'scoped_new_logging_absent',1 from unnest([1]) where not exists(
  select 1 from naming_audit where naming_status='general')
{% endmacro %}
