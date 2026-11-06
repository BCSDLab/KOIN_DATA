{{ config(tags=['gold_44_20']) }}
select event_dt, user_pseudo_id, count(*) as row_count
from {{ ref('mart_kpi_user_daily') }}
group by event_dt, user_pseudo_id
having count(*) > 1
