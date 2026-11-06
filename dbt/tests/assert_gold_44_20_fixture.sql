{{ config(tags=['gold_44_20_fixture']) }}
{% set fixture = {'build_id':'fixture','snapshot_at':'2026-12-01T00:00:00Z','computed_at':'2026-12-01T00:00:00Z','logging_start_dt':'2026-10-01','event_complete_start_dt':'2026-10-01','event_complete_dt':'2026-11-30','metric_start_dt':'2026-10-01','metric_end_dt':'2026-11-30','coverage_verified':true,'signup_verified':true,'mapping_verified':true,'session_verified':true,'session_inactivity_minutes':30,'late_arrival_hours':0} %}
with {{ gold_fixture_ctes() }},
u as ({{ gold_user_query('fixture_events','fixture_users',false,fixture) }}),
m as ({{ gold_metrics_query('fixture_events','fixture_users',false,fixture) }})
select 'signup_only_not_active' as violation from unnest([1]) where (select is_active_any_event from u where user_pseudo_id='signup_only') is distinct from 0
union all
select 'midnight_path' as violation from unnest([1]) where (select max(f.max_step_reached) from u cross join unnest(funnel_session_facts) f where user_pseudo_id='u4' and event_dt=date '2026-10-01' and f.funnel_id='shop') is distinct from 4
union all
select 'no_funnel_replication' as violation from unnest([1]) where (select sum(array_length(funnel_session_facts)) from u where user_pseudo_id='u4' and event_dt=date '2026-10-02') is distinct from 0
union all
select 'main_only_in_denominator' as violation from unnest([1]) where (select max(f.max_step_reached) from u cross join unnest(funnel_session_facts) f where user_pseudo_id='u2' and event_dt=date '2026-10-01' and f.funnel_id='shop') is distinct from 1
union all
select 'never_join_sessions' as violation from unnest([1]) where (select max(f.max_step_reached) from u cross join unnest(funnel_session_facts) f where user_pseudo_id='u5' and f.funnel_id='shop') is distinct from 1
union all
select 'tied_steps_pending' as violation from unnest([1]) where (select logical_or(f.is_complete) from u cross join unnest(funnel_session_facts) f where user_pseudo_id='u6' and f.funnel_id='shop') is distinct from false
union all
select 'repeat_after_reversal' as violation from unnest([1]) where (select max(f.max_step_reached) from u cross join unnest(funnel_session_facts) f where user_pseudo_id='u7' and f.funnel_id='shop') is distinct from 4
union all
select 'direct_entry_no_main' as violation from unnest([1]) where (select sum(array_length(funnel_session_facts)) from u where user_pseudo_id='u8') is distinct from 0
union all
select 'session_not_closed' as violation from unnest([1]) where (select logical_or(f.is_complete) from u cross join unnest(funnel_session_facts) f where user_pseudo_id='u13') is distinct from false
union all
select 'signup_d1' as violation from unnest([1]) where (select is_signup_retained_d1 from u where user_pseudo_id='u3' and event_dt=date '2026-11-28') is distinct from 1
union all
select 'signup_d7_pending' as violation from unnest([1]) where (select is_signup_retained_d7 from u where user_pseudo_id='u3' and event_dt=date '2026-11-28') is not null
union all
select 'range_deduplicated' as violation from unnest([1]) where (select numerator_users from m where metric_type='first_seen_range_entry_d1_d7' and metric_dt=date '2026-10-01') is distinct from 2
union all
select 'range_denominator_preserved' as violation from unnest([1]) where (select denominator_users from m where metric_type='first_seen_range_entry_d1_d7' and metric_dt=date '2026-10-01') is distinct from 8
union all
select 'early_return_not_mature' as violation from unnest([1]) where (select numerator_users from m where metric_type='first_seen_range_entry_d1_d7' and metric_dt=date '2026-11-28') is not null
union all
select 'weekly_or' as violation from unnest([1]) where (select numerator_users from m where metric_type='retention_weekly' and metric_dt=date '2026-10-01' and service_name='bus' and period_n=1) is distinct from 1
union all
select 'churn_55_not_56' as violation from unnest([1]) where (select numerator_users from m where metric_type='churn_56d' and metric_dt=date '2026-11-25' and service_name='bus') is distinct from 0
union all
select 'churn_56_boundary' as violation from unnest([1]) where (select numerator_users from m where metric_type='churn_56d' and metric_dt=date '2026-11-26' and service_name='bus') is distinct from 1
union all
select 'weekly_distinct_denominator' as violation from unnest([1]) where (select denominator_users from m where metric_type='app_weekly_nonreturn' and metric_dt=date '2026-10-05') is distinct from 3
union all
select 'weekly_other_service_is_return' as violation from unnest([1]) where (select numerator_users from m where metric_type='app_weekly_nonreturn' and metric_dt=date '2026-10-05') is distinct from 2
union all
select 'null_dimensions_preserved' as violation from unnest([1]) where exists(select 1 from m where gender is not null or major is not null or entry_year is not null or user_type is not null)

union all
select 'signup_five_steps' as violation from unnest([1]) where (select max(f.max_step_reached) from u cross join unnest(funnel_session_facts) f where user_pseudo_id='signup_path' and f.funnel_id='signup') is distinct from 5
union all
select 'signup_across_sessions' as violation from unnest([1]) where (select max(f.max_step_reached) from u cross join unnest(funnel_session_facts) f where user_pseudo_id='signup_cross' and f.funnel_id='signup') is distinct from 1
