{% macro gold_user_query(event_relation=none, user_relation=none, frozen=true, overrides={}) %}
with {{ gold_common_ctes(event_relation, user_relation, frozen, overrides) }},
user_days as (
  select event_dt, user_pseudo_id from event_user_days
  union distinct
  select first_signup_dt, user_pseudo_id from user_snapshot where first_signup_dt is not null
),
{% for dim in ['platform','device_category','device_os'] %}
dominant_{{ dim }} as (
  select event_dt, user_pseudo_id, {{ dim }} from silver_events where {{ dim }} is not null
  group by 1,2,3 qualify row_number() over(partition by event_dt,user_pseudo_id
    order by count(*) desc,max(event_time) desc,{{ dim }})=1
),
{% endfor %}
session_events as (
  select *,lag(event_time) over(partition by user_pseudo_id,ga_session_id
    order by event_time,event_id) as previous_time
  from silver_events where safe_cast(ga_session_id as int64)>0
),
session_quality as (
  select user_pseudo_id,ga_session_id,min(event_time) as first_time,max(event_time) as last_time,
    count(distinct platform) as platform_count,
    max(platform) as session_platform,
    max(timestamp_diff(event_time,previous_time,second)) as max_gap_seconds
  from session_events group by 1,2
),
funnel_support as ({{ gold_funnel_support() }}),
funnel_definitions as (
  select 'signup' as funnel_id,'account' as service_name,5 as total_steps
  {% for s in ['shop','bus','cafeteria','timetable','board'] %}
  union all select '{{ s }}','{{ s }}',4
  {% endfor %}
),
funnel_steps as (
  select e.user_pseudo_id,e.ga_session_id,d.funnel_id,d.total_steps,e.event_time,
    case when e.service_name='main' and e.funnel_stage='main' then 1
      when d.funnel_id='signup' then e.service_step_order
      else e.service_step_order+1 end as step_no
  from session_events e join funnel_definitions d on
    (d.funnel_id!='signup' and e.service_name='main' and e.funnel_stage='main')
    or (e.service_name=d.service_name and (
      (d.funnel_id='signup' and e.funnel_stage in
        ('signup_start','terms_agreement','identity_verification','form_entry','signup_complete'))
      or (d.funnel_id!='signup' and e.service_step_order between 1 and 3)))
),
funnel_ties as (
  select user_pseudo_id,ga_session_id,funnel_id from funnel_steps
  group by 1,2,3,event_time having count(distinct step_no)>1
),
path_1 as (
  select user_pseudo_id,ga_session_id,funnel_id,total_steps,min(event_time) as t1
  from funnel_steps where step_no=1 group by 1,2,3,4
),
{% for n in range(2,6) %}
path_{{ n }} as (
  select p.*,(select min(s.event_time) from funnel_steps s
    where s.user_pseudo_id=p.user_pseudo_id and s.ga_session_id=p.ga_session_id
      and s.funnel_id=p.funnel_id and s.step_no={{ n }} and s.event_time>p.t{{ n-1 }}) as t{{ n }}
  from path_{{ n-1 }} p
),
{% endfor %}
session_facts as (
  select p.user_pseudo_id,date(p.t1,'Asia/Seoul') as anchor_dt,
    struct(p.funnel_id as funnel_id,b.funnel_version as funnel_version,
      to_hex(sha256(to_json_string(struct(p.user_pseudo_id,p.ga_session_id)))) as session_key,
      date(p.t1,'Asia/Seoul') as anchor_dt,
      (b.coverage_verified and b.mapping_verified and b.session_verified
        and b.funnel_support_verified and coalesce(s.supported,false)
        and (p.funnel_id='signup' or (b.main_visit_verified and q.session_platform in unnest(b.main_visit_platforms)))
        and b.inactivity_minutes>0 and b.late_arrival_hours>=0 and q.platform_count=1
        and date(q.first_time,'Asia/Seoul')>=b.complete_start_dt
        and timestamp_add(timestamp_add(q.last_time,interval b.inactivity_minutes minute),
          interval b.late_arrival_hours hour)<timestamp(date_add(b.complete_dt,interval 1 day),'Asia/Seoul')
        and coalesce(q.max_gap_seconds,0)<=b.inactivity_minutes*60
        and not exists(select 1 from funnel_ties t where t.user_pseudo_id=p.user_pseudo_id
          and t.ga_session_id=p.ga_session_id and t.funnel_id=p.funnel_id)) as is_complete,
      array_length(array(select t from unnest([p.t1,p.t2,p.t3,p.t4,p.t5]) t
        where t is not null)) as max_step_reached,p.total_steps as total_steps,
      array(select t from unnest([p.t1,p.t2,p.t3,p.t4,p.t5]) t with offset o
        where t is not null order by o) as step_reached_at) as fact
  from path_5 p join session_quality q using(user_pseudo_id,ga_session_id)
  left join funnel_support s on s.funnel_id=p.funnel_id and s.platform=q.session_platform
  cross join gold_parameters b
),
daily_funnels as (
  select anchor_dt as event_dt,user_pseudo_id,
    array_agg(fact order by fact.funnel_id,fact.funnel_version,fact.session_key) as facts
  from session_facts group by 1,2
),
joined as (
  select d.event_dt,d.user_pseudo_id,u.* except(user_pseudo_id),
    {% for dim in ['platform','device_category','device_os'] %}
    coalesce(p{{ loop.index }}.{{ dim }},'unknown') as {{ dim }}_dominant,
    {% endfor %}
    {% for c in ['event_cnt_day','entry_event_cnt_day','core_action_cnt_day','session_cnt_day','engagement_msec_day'] %}
    coalesce(a.{{ c }},0) as {{ c }},
    {% endfor %}
    if(prev.entry_event_cnt_day>0,1,0) as had_entry_prev_day,
    {% for n in [1,7,14,30] %}
    case when d.event_dt=u.first_signup_dt and b.coverage_verified and b.signup_verified
      and date_add(u.first_signup_dt,interval {{ n }} day) between b.complete_start_dt and b.complete_dt
    then if(exists(select 1 from event_user_days r where r.user_pseudo_id=d.user_pseudo_id
      and r.event_dt=date_add(u.first_signup_dt,interval {{ n }} day)
      and r.entry_event_cnt_day>0),1,0) end as is_signup_retained_d{{ n }},
    {% endfor %}
    {% for s in ['shop','cafeteria','bus','board','facility','timetable','account','main'] %}
    coalesce(a.used_{{ s }}_flg,0) as used_{{ s }}_flg,
    {% endfor %}
    coalesce(f.facts,[]) as funnel_session_facts,
    b.complete_start_dt as event_complete_start_dt,b.complete_dt as event_complete_dt,
    b.snapshot_at as user_snapshot_at,b.build_id,b.computed_at
  from user_days d join user_snapshot u using(user_pseudo_id) cross join gold_parameters b
  left join event_user_days a using(event_dt,user_pseudo_id)
  left join event_user_days prev on prev.user_pseudo_id=d.user_pseudo_id
    and prev.event_dt=date_sub(d.event_dt,interval 1 day)
  {% for dim in ['platform','device_category','device_os'] %}
  left join dominant_{{ dim }} p{{ loop.index }} on p{{ loop.index }}.event_dt=d.event_dt
    and p{{ loop.index }}.user_pseudo_id=d.user_pseudo_id
  {% endfor %}
  left join daily_funnels f on f.event_dt=d.event_dt and f.user_pseudo_id=d.user_pseudo_id
)
select event_dt,user_pseudo_id,user_id,gender,major,entry_year,user_type,is_deleted,is_mysql_mapped,
  platform_dominant,device_category_dominant,device_os_dominant,
  event_cnt_day,entry_event_cnt_day,core_action_cnt_day,session_cnt_day,engagement_msec_day,
  if(session_cnt_day>=2,1,0) as is_multi_session_user,first_seen_dt,first_signup_dt,
  if(event_dt=first_seen_dt,1,0) as is_new_user,if(event_dt=first_signup_dt,1,0) as is_new_signup,
  had_entry_prev_day,is_signup_retained_d1,is_signup_retained_d7,is_signup_retained_d14,is_signup_retained_d30,
  used_shop_flg,used_cafeteria_flg,used_bus_flg,used_board_flg,used_facility_flg,used_timetable_flg,used_account_flg,
  if(entry_event_cnt_day>0,1,0) as is_active_entry,if(event_cnt_day>0,1,0) as is_active_any_event,
  if(core_action_cnt_day>0,1,0) as has_core_action,used_main_flg,
  event_complete_start_dt,event_complete_dt,user_snapshot_at,build_id,computed_at,funnel_session_facts
from joined
{% endmacro %}
