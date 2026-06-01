select
  event_date,
  event_name,
  count(*) as event_count,
  count(distinct user_pseudo_id) as active_users
from {{ ref('bronze_ga4_events') }}
group by 1, 2
