-- Virtual Dataset, ENABLE_TEMPLATE_PROCESSING required.
-- Period user segment is app first-seen, not first-ever use of this service.
{% set time = get_time_filter('event_dt', remove_filter=True) %}
SELECT g.event_dt, g.user_pseudo_id, g.gender, g.major, g.entry_year, g.user_type,
  g.first_seen_dt, g.event_complete_start_dt, g.event_complete_dt, g.build_id,
  s.service_name,
  CASE WHEN g.first_seen_dt = g.event_dt THEN 'new' ELSE 'existing' END AS daily_user_segment,
  {% if time.from_expr and time.to_expr %}
  CASE WHEN g.first_seen_dt >= CAST({{ time.from_expr }} AS DATE)
    AND g.first_seen_dt < CAST({{ time.to_expr }} AS DATE)
    THEN 'new' ELSE 'existing' END AS period_user_segment
  {% else %}
  CAST(NULL AS STRING) AS period_user_segment
  {% endif %}
FROM `koin-stage-438512.gold.mart_kpi_user_daily` g
CROSS JOIN UNNEST([
  STRUCT('shop' AS service_name,g.used_shop_flg AS used),
  STRUCT('bus',g.used_bus_flg),STRUCT('cafeteria',g.used_cafeteria_flg),
  STRUCT('board',g.used_board_flg),STRUCT('facility',g.used_facility_flg),
  STRUCT('timetable',g.used_timetable_flg),STRUCT('main',g.used_main_flg),
  STRUCT('account',g.used_account_flg)
]) s
WHERE s.used=1
{% if time.from_expr and time.to_expr %}
  AND g.event_dt >= CAST({{ time.from_expr }} AS DATE)
  AND g.event_dt < CAST({{ time.to_expr }} AS DATE)
{% else %}
  AND FALSE
{% endif %}
