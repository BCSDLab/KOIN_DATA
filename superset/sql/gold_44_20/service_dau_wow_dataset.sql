-- Virtual Dataset. Group by event_dt and service_name. User dimensions may be filtered.
-- Read 7 extra days before the display interval; do not LAG over missing calendar dates.
{% set time = get_time_filter('event_dt', remove_filter=True) %}
WITH batch AS (
  SELECT MIN(event_complete_start_dt) AS complete_start_dt,MAX(event_complete_dt) AS complete_dt,
    COUNT(DISTINCT TO_JSON_STRING(STRUCT(build_id,user_snapshot_at,event_complete_start_dt,event_complete_dt))) AS batches
  FROM `koin-stage-438512.gold.mart_kpi_user_daily`
), daily AS (
  SELECT g.event_dt,s.service_name,g.gender,g.major,g.entry_year,g.user_type,
    COUNT(DISTINCT g.user_pseudo_id) AS users
  FROM `koin-stage-438512.gold.mart_kpi_user_daily` g
  CROSS JOIN UNNEST([
    STRUCT('shop' AS service_name,g.used_shop_flg AS used),STRUCT('bus',g.used_bus_flg),
    STRUCT('cafeteria',g.used_cafeteria_flg),STRUCT('board',g.used_board_flg),
    STRUCT('facility',g.used_facility_flg),STRUCT('timetable',g.used_timetable_flg),
    STRUCT('main',g.used_main_flg),STRUCT('account',g.used_account_flg)
  ]) s
  WHERE s.used=1
  {% if time.from_expr and time.to_expr %}
    AND g.event_dt>=DATE_SUB(CAST({{ time.from_expr }} AS DATE),INTERVAL 7 DAY)
    AND g.event_dt<CAST({{ time.to_expr }} AS DATE)
  {% else %}
    AND FALSE
  {% endif %}
  GROUP BY 1,2,3,4,5,6
), aligned AS (
  SELECT event_dt,service_name,gender,major,entry_year,user_type,users AS today,0 AS previous FROM daily
  UNION ALL
  SELECT DATE_ADD(event_dt,INTERVAL 7 DAY),service_name,gender,major,entry_year,user_type,0,users FROM daily
), counts AS (
  SELECT event_dt,service_name,gender,major,entry_year,user_type,SUM(today) AS today,SUM(previous) AS previous
  FROM aligned GROUP BY 1,2,3,4,5,6
)
SELECT c.event_dt,c.service_name,c.gender,c.major,c.entry_year,c.user_type,
  IF(b.batches=1 AND c.event_dt BETWEEN b.complete_start_dt AND b.complete_dt,c.today,NULL) AS dau_users,
  IF(b.batches=1 AND DATE_SUB(c.event_dt,INTERVAL 7 DAY)>=b.complete_start_dt
    AND c.event_dt<=b.complete_dt,c.previous,NULL) AS previous_dau_users,
  (b.batches=1 AND DATE_SUB(c.event_dt,INTERVAL 7 DAY)>=b.complete_start_dt
    AND c.event_dt<=b.complete_dt) AS is_complete_pair
FROM counts c CROSS JOIN batch b
{% if time.from_expr and time.to_expr %}
WHERE c.event_dt>=CAST({{ time.from_expr }} AS DATE) AND c.event_dt<CAST({{ time.to_expr }} AS DATE)
{% else %}
WHERE FALSE
{% endif %}
