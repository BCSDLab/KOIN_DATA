{{ config(tags=['gold_44_20']) }}
-- Verify facts against the frozen Silver evidence, not just array bounds.
with {{ gold_common_ctes() }},
definitions as (
  select 'signup' as funnel_id,'account' as service_name,5 as total_steps
  {% for s in ['shop','bus','cafeteria','timetable','board'] %}
  union all select '{{ s }}','{{ s }}',4
  {% endfor %}
),
steps as (
  select e.user_pseudo_id,e.event_time,d.funnel_id,d.total_steps,
    to_hex(sha256(to_json_string(struct(e.user_pseudo_id,e.ga_session_id)))) as session_key,
    case when e.service_name='main' and e.funnel_stage='main' then 1
      when d.funnel_id='signup' then e.service_step_order else e.service_step_order+1 end as step_no
  from silver_events e join definitions d on
    (d.funnel_id!='signup' and e.service_name='main' and e.funnel_stage='main')
    or (e.service_name=d.service_name and (
      (d.funnel_id='signup' and e.funnel_stage in
        ('signup_start','terms_agreement','identity_verification','form_entry','signup_complete'))
      or (d.funnel_id!='signup' and e.service_step_order between 1 and 3)))
  where safe_cast(e.ga_session_id as int64)>0
),
anchors as (
  select user_pseudo_id,session_key,funnel_id,min(event_time) as first_step_at
  from steps where step_no=1 group by 1,2,3
),
facts as (
  select u.user_pseudo_id,u.event_dt,f.*
  from {{ ref('mart_kpi_user_daily') }} u cross join unnest(u.funnel_session_facts) f
)
select 'funnel_definition_or_anchor' as violation,count(*) as failures
from facts f left join definitions d using(funnel_id) cross join gold_parameters p
where d.funnel_id is null or f.total_steps is distinct from d.total_steps
  or f.funnel_version is distinct from p.funnel_version
  or f.anchor_dt is distinct from date(f.step_reached_at[safe_offset(0)],'Asia/Seoul')
  or f.is_complete is null or f.session_key is null or f.max_step_reached is null
having count(*)>0
union all
select 'funnel_step_without_source',count(*)
from facts f cross join unnest(f.step_reached_at) t with offset n
where not exists(select 1 from steps s where s.user_pseudo_id=f.user_pseudo_id
  and s.session_key=f.session_key and s.funnel_id=f.funnel_id and s.step_no=n+1 and s.event_time=t)
having count(*)>0
union all
select 'funnel_first_stage_not_preserved',count(*) from anchors a
where not exists(select 1 from facts f where f.user_pseudo_id=a.user_pseudo_id
  and f.session_key=a.session_key and f.funnel_id=a.funnel_id
  and f.step_reached_at[safe_offset(0)]=a.first_step_at)
having count(*)>0
union all
select 'funnel_duplicate',count(*) from (
  select user_pseudo_id,session_key,funnel_id,funnel_version from facts
  group by 1,2,3,4 having count(*)!=1
) having count(*)>0
