{{ config(enabled=(var('silver_logging_validation_enabled', false) is sameas true), tags=['silver_logging_v1_fixture']) }}
{% if var('silver_logging_validation_enabled', false) is sameas true %}
{% set scopes=[] %}
{% for p in ['WEB','ANDROID','IOS'] %}{% for n in ['DA1','DA2'] %}
{% do scopes.append({'platform':p,'event_name':n,'start_dt':'2026-10-01','end_dt':'2026-11-30','evidence':'SYNTHETIC ONLY'}) %}
{% endfor %}{% endfor %}
{# True flags below are confined to this synthetic calculation, not deployment approval. #}
{% set fixture={'build_id':'silver_to_gold_fixture','snapshot_at':'2026-12-01T00:00:00Z','computed_at':'2026-12-01T00:00:00Z','logging_start_dt':'2026-10-01','event_complete_start_dt':'2026-10-01','event_complete_dt':'2026-11-30','metric_start_dt':'2026-10-01','metric_end_dt':'2026-11-30','funnel_version':'synthetic_v1','coverage_verified':true,'signup_verified':true,'mapping_verified':true,'main_visit_platforms':['WEB','ANDROID','IOS'],'main_visit_verified':true,'funnel_support_verified':true,'session_verified':true,'session_inactivity_minutes':30,'late_arrival_hours':0} %}
CREATE TEMP TABLE path_events AS (
with {{ silver_logging_v1_fixture_ctes() }},
path_raw as (select * from mock_events where test_group='path'),
mapped as ({{ silver_logging_v1_classify('path_raw',scopes,silver_logging_v1_fixture_legacy()) }})
select * from mapped where test_group='path'
);
CREATE TEMP TABLE mock_users AS (
with {{ gold_fixture_ctes() }} select * from fixture_users
);
CREATE TEMP TABLE u AS (
{{ gold_user_query('path_events','mock_users',false,fixture) }}
);
CREATE TEMP TABLE m AS (
{{ gold_metrics_query('path_events','mock_users',false,fixture) }}
);
with
invariants as ({{ gold_invariants_query('u','m') }}),
retention_grid as ({{ gold_retention_grid_query('u','m') }})
select 'event_total' as violation from unnest([1]) where (select sum(event_cnt_day) from u) is distinct from 27
union all
select 'active_users' from unnest([1]) where
 (select count(distinct user_pseudo_id) from u where event_dt=date '2026-10-01' and is_active_any_event=1) is distinct from 6
{% for service,pseudo in [('shop','u1'),('bus','u2'),('cafeteria','u4'),('timetable','u5'),('board','u6')] %}
union all
select 'funnel_{{ service }}' from unnest([1]) where (
 select max(f.max_step_reached) from u cross join unnest(funnel_session_facts) f
 where user_pseudo_id='{{ pseudo }}' and event_dt=date '2026-10-01' and f.funnel_id='{{ service }}') is distinct from 4
{% endfor %}
union all
select 'signup_unknown_steps_fabricated' from unnest([1]) where (
 select max(f.max_step_reached) from u cross join unnest(funnel_session_facts) f
 where user_pseudo_id='u7' and f.funnel_id='signup') is distinct from 3
union all
select 'signup_d1' from unnest([1]) where (
 select is_signup_retained_d1 from u where user_pseudo_id='u7' and event_dt=date '2026-10-01') is distinct from 1
union all
select 'service_retention_d1' from unnest([1]) where (
 select numerator_users from m where metric_type='retention_daily' and service_name='bus'
 and metric_dt=date '2026-10-01' and period_n=1) is distinct from 1
union all
select 'range_retention' from unnest([1]) where (
 select numerator_users from m where metric_type='first_seen_range_entry_d1_d7' and metric_dt=date '2026-10-01') is distinct from 2
union all
select 'invariants' from unnest([1]) where exists(select 1 from invariants)
union all
select 'retention_grid' from unnest([1]) where exists(select 1 from retention_grid)

{% endif %}
