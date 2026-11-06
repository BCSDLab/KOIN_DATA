{{ config(tags=['gold_44_20']) }}
{% set r=ref('mart_service_metrics_daily') %}
with expected as (select column_name from unnest(['metric_row_id', 'metric_type', 'metric_dt', 'service_name', 'period_n', 'window_start_dt', 'window_end_dt', 'gender', 'major', 'entry_year', 'user_type', 'cohort_user_segment', 'denominator_users', 'numerator_users', 'is_complete', 'event_complete_start_dt', 'event_complete_dt', 'user_snapshot_at', 'build_id', 'computed_at']) column_name), actual as (select column_name from `{{ r.database }}.{{ r.schema }}.INFORMATION_SCHEMA.COLUMNS` where table_name='{{ r.identifier }}')
select coalesce(e.column_name,a.column_name) as column_name from expected e full join actual a using(column_name) where e.column_name is null or a.column_name is null
