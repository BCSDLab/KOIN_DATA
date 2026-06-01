select
  event_date,
  event_name,
  event_count,
  active_users
from {{ ref('silver_daily_events') }}
