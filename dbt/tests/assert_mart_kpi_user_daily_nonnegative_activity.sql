{{ config(tags=['gold_44_20']) }}
select event_dt, user_pseudo_id
from {{ ref('mart_kpi_user_daily') }}
where event_cnt_day < 0
   or entry_event_cnt_day < 0
   or core_action_cnt_day < 0
   or session_cnt_day < 0
   or engagement_msec_day < 0
