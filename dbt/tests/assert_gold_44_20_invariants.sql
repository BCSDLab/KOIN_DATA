{{ config(tags=['gold_44_20']) }}
with users as (select * from {{ ref('mart_kpi_user_daily') }}),
metrics as (select * from {{ ref('mart_service_metrics_daily') }})
select 'user_flags' as violation,count(*) as failures from users
where is_active_any_event is distinct from if(event_cnt_day>0,1,0)
  or is_active_entry is distinct from if(entry_event_cnt_day>0,1,0)
  or has_core_action is distinct from if(core_action_cnt_day>0,1,0)
  or is_new_user is distinct from if(first_seen_dt=event_dt,1,0)
  or is_new_signup is distinct from if(first_signup_dt=event_dt,1,0)
having failures>0
union all
select 'signup_anchor',count(*) from users
where (first_signup_dt is distinct from event_dt) and
  (is_signup_retained_d1 is not null or is_signup_retained_d7 is not null
    or is_signup_retained_d14 is not null or is_signup_retained_d30 is not null)
having count(*)>0
union all
select 'metric_bounds',count(*) from metrics
where denominator_users is null or denominator_users<=0 or is_complete is null
  or (is_complete and (numerator_users is null or numerator_users<0 or numerator_users>denominator_users))
  or (not is_complete and numerator_users is not null)
having count(*)>0
union all
select 'funnel_evidence',count(*) from users cross join unnest(funnel_session_facts) f
where f.anchor_dt is distinct from event_dt or f.max_step_reached<1 or f.max_step_reached>f.total_steps
  or array_length(f.step_reached_at)!=f.max_step_reached
  or exists(select 1 from unnest(f.step_reached_at) t with offset o
    where o>0 and t<=f.step_reached_at[safe_offset(o-1)])
having count(*)>0
