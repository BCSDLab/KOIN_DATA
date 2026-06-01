with source as (
  select *
  from {{ source('ga4', 'events') }}
)

select
  parse_date('%Y%m%d', event_date) as event_date,
  timestamp_micros(event_timestamp) as event_timestamp,
  event_name,
  user_pseudo_id,
  {{ ga4_event_param_int('ga_session_id') }} as ga_session_id,
  {{ ga4_event_param_string('page_location') }} as page_location,
  {{ ga4_event_param_string('page_title') }} as page_title,
  platform,
  device.category as device_category,
  geo.country as country,
  geo.region as region,
  traffic_source.source as traffic_source,
  traffic_source.medium as traffic_medium,
  traffic_source.name as traffic_campaign,
  ecommerce.purchase_revenue as purchase_revenue,
  event_params,
  items
from source
