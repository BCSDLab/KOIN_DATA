-- Virtual Dataset. Select exactly one full calendar month on metric_dt.
-- remove_filter prevents the month filter from deleting a baseline week in the prior month.
{% set time = get_time_filter('metric_dt', remove_filter=True) %}
{% if time.from_expr and time.to_expr %}
WITH batch AS (
  SELECT MAX(event_complete_dt) AS complete_dt,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(build_id,user_snapshot_at,
      event_complete_start_dt,event_complete_dt))) AS batches
  FROM `koin-stage-438512.gold.mart_kpi_user_daily`
), selection AS (
  SELECT CAST({{ time.from_expr }} AS DATE) AS start_dt,
    CAST({{ time.to_expr }} AS DATE) AS end_exclusive
), cutoff AS (
  SELECT LEAST(LAST_DAY(start_dt),complete_dt) AS cutoff_dt
  FROM batch CROSS JOIN selection
  WHERE batches=1 AND start_dt=DATE_TRUNC(start_dt,MONTH)
    AND end_exclusive=DATE_ADD(start_dt,INTERVAL 1 MONTH) AND start_dt<=complete_dt
), target AS (
  SELECT DATE_SUB(DATE_SUB(DATE_TRUNC(DATE_ADD(cutoff_dt,INTERVAL 1 DAY),WEEK(MONDAY)),
    INTERVAL 1 DAY),INTERVAL 13 DAY) AS base_week_start FROM cutoff
)
SELECT m.*
FROM `koin-stage-438512.gold.mart_service_metrics_daily` m
JOIN target ON m.metric_dt=target.base_week_start
WHERE m.metric_type='app_weekly_nonreturn' AND m.service_name='__all__'
  AND m.period_n=1 AND m.cohort_user_segment='not_applicable'
{% else %}
SELECT * FROM `koin-stage-438512.gold.mart_service_metrics_daily` WHERE FALSE
{% endif %}
