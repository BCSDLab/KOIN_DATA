{{ config(tags=['gold_44_20_fixture']) }}
{% set fixture = {'build_id':'quality_fixture','snapshot_at':'2026-12-01T00:00:00Z','computed_at':'2026-12-01T00:00:00Z','logging_start_dt':'2026-10-01','event_complete_start_dt':'2026-10-01','event_complete_dt':'2026-11-30','metric_start_dt':'2026-10-01','metric_end_dt':'2026-11-30','naming_scopes':[{'platform':'WEB','event_name':'DA1','start_dt':'2026-10-01','end_dt':'2026-11-30'}],'approved_legacy_labels':[{'platform':'WEB','event_name':'DA1','event_label':'old_approved','event_category':'click'}]} %}
with {{ gold_fixture_ctes() }},
silver_events as (
  select 'general' as event_id,date '2026-10-01' as event_dt,'WEB' as platform,'DA1' as event_name,
    'bus__bus__search__click' as event_label,'click' as event_category
  union all select 'frozen',date '2026-10-01','WEB','DA1','cafeteria__cafeteria__soldout_submit','submit'
  union all select 'frozen_fail',date '2026-10-01','WEB','DA1','cafeteria__cafeteria__soldout_submit','fail'
  union all select 'wrong_frozen_category',date '2026-10-01','WEB','DA1','cafeteria__cafeteria__soldout_submit','click'
  union all select 'unknown',date '2026-10-01','WEB','DA1','old_unknown','click'
  union all select 'approved',date '2026-10-01','WEB','DA1','old_approved','click'
  union all select 'other_platform',date '2026-10-01','ANDROID','DA1','old_unknown','click'
  union all select 'before_scope',date '2026-09-30','WEB','DA1','old_unknown','click'
  union all select 'category_mismatch',date '2026-10-01','WEB','DA1','bus__bus__search__click','submit'
  union all select 'empty_token',date '2026-10-01','WEB','DA1','bus___bus__search__click','click'
  union all select 'bus_destination',date '2026-10-01','WEB','DA1','bus__header__timetable__click','click'
  union all select 'other_owner',date '2026-10-01','WEB','DA2','old_approved','click'
),
{{ gold_naming_ctes(fixture) }},
bad_key_events as (
  select e.* replace('bad_key_'||cast(n as string) as event_id,
    if(n=4,'u2','u1') as user_pseudo_id,
    case when n<=2 then cast(null as string) when n=3 then '0' else 'bad' end as ga_session_id)
  from fixture_events e cross join unnest([1,2,3,4]) n where e.event_id='e1'
),
quality as ({{ gold_input_quality('bad_key_events','fixture_users',false,fixture) }}),
expected as (
  select 'general' as event_id,'general' as expected
  union all select 'frozen','approved_frozen' union all select 'frozen_fail','approved_frozen'
  union all select 'wrong_frozen_category','invalid' union all select 'unknown','invalid'
  union all select 'approved','approved_legacy' union all select 'other_platform','outside_scope'
  union all select 'before_scope','outside_scope' union all select 'category_mismatch','invalid'
  union all select 'empty_token','invalid' union all select 'bus_destination','general'
  union all select 'other_owner','outside_scope'
)
select 'naming_'||e.event_id as violation from expected e join naming_audit a using(event_id)
where a.naming_status is distinct from e.expected
union all
select 'session_missing_count' from unnest([1]) where (select event_count from quality
  where reason='funnel_session_key_missing' and aggregation_level='whole_input') is distinct from 2
union all
select 'session_invalid_count' from unnest([1]) where (select event_count from quality
  where reason='funnel_session_key_invalid' and aggregation_level='whole_input') is distinct from 2
union all
select 'session_distinct_users' from unnest([1]) where (select distinct_users from quality
  where reason='funnel_session_key_excluded' and aggregation_level='whole_input') is distinct from 2
union all
select 'session_combined_events' from unnest([1]) where (select event_count from quality
  where reason='funnel_session_key_excluded' and aggregation_level='whole_input') is distinct from 4
