select
  *
from {{ ref('stg_ga4_events') }}
