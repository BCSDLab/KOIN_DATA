-- 첫 silver 모델 (테스트): 오늘치 GA4 이벤트만 정제.
-- GA4 원본의 event_params(배열)를 컬럼으로 펴는 게 핵심.
-- TODO: 나중에 incremental + event_dt 파티션 table 로 확장.

with source as (

    select *
    from {{ source('ga4', 'events') }}
    where _table_suffix like '%' || format_date('%Y%m%d', current_date())   -- 오늘 (확정 + intraday)

)

select
    parse_date('%Y%m%d', event_date)                                                  as event_dt,
    timestamp_micros(event_timestamp)                                                 as event_at,
    event_name,
    user_pseudo_id,
    (select value.string_value from unnest(event_params) where key = 'page_location') as page_location
from source
