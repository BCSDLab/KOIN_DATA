{{ config(tags=['gold_44_20_fixture']) }}
{% set fixture = {'build_id':'candidate_fixture','snapshot_at':'2026-12-01T00:00:00Z','computed_at':'2026-12-01T00:00:00Z','logging_start_dt':'2026-10-01','event_complete_start_dt':'2026-10-01','event_complete_dt':'2026-11-30','metric_start_dt':'2026-10-01','metric_end_dt':'2026-11-30','coverage_verified':true,'signup_verified':true,'mapping_verified':true,'main_visit_platforms':['WEB','ANDROID','IOS'],'main_visit_verified':true,'funnel_support_verified':true,'session_verified':true,'session_inactivity_minutes':30,'late_arrival_hours':0} %}
with {{ gold_fixture_ctes() }},
u as ({{ gold_user_query('fixture_events','fixture_users',false,fixture) }}),
m as ({{ gold_metrics_query('fixture_events','fixture_users',false,fixture) }}),
bad_users as (
  select u.* replace(array(select as struct f.* replace(
    array(select if(n=1,timestamp_sub(f.step_reached_at[0],interval 1 second),t)
      from unnest(f.step_reached_at) t with offset n order by n) as step_reached_at)
    from unnest(u.funnel_session_facts) f) as funnel_session_facts)
  from u
),
missing_period as (select * from m where not(metric_type='retention_daily' and period_n=7)),
good_invariants as ({{ gold_invariants_query('u','m') }}),
bad_invariants as ({{ gold_invariants_query('bad_users','m') }}),
good_grid as ({{ gold_retention_grid_query('u','m') }}),
bad_grid as ({{ gold_retention_grid_query('u','missing_period') }})
select 'good_candidates_rejected' as violation from unnest([1])
where exists(select 1 from good_invariants) or exists(select 1 from good_grid)
union all
select 'reversed_funnel_accepted' from unnest([1])
where not exists(select 1 from bad_invariants where violation='funnel_evidence')
union all
select 'missing_retention_period_accepted' from unnest([1])
where not exists(select 1 from bad_grid)
