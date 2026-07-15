{{
  config(
    materialized='incremental',
    incremental_strategy='insert_overwrite',
    partition_by={'field': 'event_dt', 'data_type': 'date'},
    cluster_by=['event_name', 'user_pseudo_id']
  )
}}

{#
  GA4 이벤트 정제 (silver). event_params(배열)/device(레코드)를 컬럼으로 편다.

  날짜 범위 제어:
  - 기본(증분): 최근 3일 재처리 → GA4가 최근 ~3일 데이터를 갱신하므로
  - 백필/특정범위: dbt run --vars '{"start_date":"20260101","end_date":"20260131"}'
  - 첫 실행(full): 전체
#}
{% set start_date = var('start_date', none) %}
{% set end_date = var('end_date', none) %}

with source as (

    select *
    from {{ source('ga4', 'events') }}
    where _table_suffix not like '%intraday%'          -- 확정 테이블만
    {% if start_date and end_date %}
      and _table_suffix between '{{ start_date }}' and '{{ end_date }}'
    {% elif is_incremental() %}
      and _table_suffix >= format_date('%Y%m%d', date_sub(current_date(), interval 3 day))
    {% endif %}

),

renamed as (

    select
        -- 이벤트
        parse_date('%Y%m%d', event_date)                          as event_dt,
        datetime(timestamp_micros(event_timestamp), 'Asia/Seoul') as event_at,
        event_timestamp                                           as event_ts,
        event_name,

        -- 유저 / 세션
        user_pseudo_id,
        cast((select value.int_value from unnest(event_params) where key = 'ga_session_id') as string) as ga_session_id,

        -- 기기
        platform,
        device.category                  as device_category,
        device.operating_system          as device_os,
        device.operating_system_version  as device_os_version,

        -- 이벤트 파라미터
        (select value.string_value from unnest(event_params) where key = 'page_location')       as page_location,
        (select value.string_value from unnest(event_params) where key = 'page_title')          as page_title,
        (select value.int_value    from unnest(event_params) where key = 'engagement_time_msec') as engagement_time_msec

    from source

)

select * from renamed
