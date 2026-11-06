{{ config(tags=['gold_44_20']) }}
with batches as (
  select build_id,user_snapshot_at,event_complete_start_dt,event_complete_dt
  from {{ ref('mart_kpi_user_daily') }}
  union all
  select build_id,user_snapshot_at,event_complete_start_dt,event_complete_dt
  from {{ ref('mart_service_metrics_daily') }}
)
select count(distinct to_json_string(struct(build_id,user_snapshot_at,event_complete_start_dt,event_complete_dt))) as batches
from batches having batches!=1
