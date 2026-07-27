{{
    config(
        materialized='incremental',
        incremental_strategy='insert_overwrite',
        partition_by={
            'field': 'event_dt',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by=['user_pseudo_id', 'uid_norm'],
        on_schema_change='fail'
    )
}}

{#-
  Dataform의 stg.incremental_stg_events_final 전처리를 이관한다.

  * start_date/end_date는 호출자(Airflow 또는 사람)가 항상 함께 전달한다.
  * 운영 스케줄은 Airflow가 최근 3일 범위를 계산해 전달한다.
  * Cosmos의 dbt ls에서는 execute=false이므로 날짜 검증을 수행하지 않는다.
  * 실제 dbt compile/run에서는 날짜 형식과 순서를 검증한다.
  * 지정된 event_dt 파티션만 insert_overwrite로 교체한다.
-#}
{% set start_date_var = var('start_date', none) %}
{% set end_date_var = var('end_date', none) %}
{% set start_date = start_date_var | string if start_date_var is not none else none %}
{% set end_date = end_date_var | string if end_date_var is not none else none %}

{% if execute %}
    {% if not start_date or not end_date %}
        {{ exceptions.raise_compiler_error(
            'silver__user_identity_events 실행에는 start_date와 end_date가 모두 필요합니다.'
        ) }}
    {% else %}
        {% for value in [start_date, end_date] %}
            {% if not modules.re.match('^\d{8}$', value) %}
                {{ exceptions.raise_compiler_error(
                    "start_date와 end_date는 숫자 8자리(YYYYMMDD)여야 합니다. 받은 값: '" ~ value ~ "'"
                ) }}
            {% endif %}
        {% endfor %}
        {% if start_date > end_date %}
            {{ exceptions.raise_compiler_error(
                'start_date가 end_date보다 늦을 수 없습니다.'
            ) }}
        {% endif %}
    {% endif %}
{% endif %}

{# dbt ls용 안전한 리터럴. 실제 실행에서는 위 검증을 통과한 값만 사용된다. #}
{% set render_start_date = start_date if start_date else '19700101' %}
{% set render_end_date = end_date if end_date else '19700101' %}

with raw_events as (

    select
        date(timestamp_micros(e.event_timestamp), 'Asia/Seoul') as event_dt,
        datetime(timestamp_micros(e.event_timestamp), 'Asia/Seoul') as event_at,
        e.event_name,
        e.event_timestamp as event_ts,
        e.user_pseudo_id,
        farm_fingerprint(to_json_string(e.event_params)) as event_fingerprint,
        e.user_id as top_user_id,
        e.platform,
        e.device.category as device_category,
        e.device.operating_system as device_os,
        e.device.operating_system_version as device_os_version,
        param.key as param_key,
        coalesce(
            param.value.string_value,
            cast(param.value.int_value as string),
            cast(param.value.float_value as string),
            cast(param.value.double_value as string)
        ) as param_value
    from {{ source('ga4', 'events') }} as e
    left join unnest(e.event_params) as param
        on true
    where regexp_contains(_table_suffix, r'^\d{8}$')
      and _table_suffix between
          format_date(
              '%Y%m%d',
              date_sub(
                  parse_date('%Y%m%d', '{{ render_start_date }}'),
                  interval 1 day
              )
          )
          and '{{ render_end_date }}'
      and date(timestamp_micros(e.event_timestamp), 'Asia/Seoul') between
          parse_date('%Y%m%d', '{{ render_start_date }}')
          and parse_date('%Y%m%d', '{{ render_end_date }}')

),

params_pivoted as (

    select
        event_dt,
        event_at,
        event_name,
        event_ts,
        user_pseudo_id,
        event_fingerprint,
        max(top_user_id) as top_user_id,
        max(if(param_key = 'user_id', param_value, null)) as param_user_id,
        max(if(param_key = 'gender', param_value, null)) as gender,
        max(if(param_key = 'major', param_value, null)) as major,
        max(if(param_key = 'ga_session_id', param_value, null)) as ga_session_id,
        max(platform) as platform,
        max(device_category) as device_category,
        max(device_os) as device_os,
        max(device_os_version) as device_os_version,
        max(if(param_key = 'event_label', param_value, null)) as event_label,
        max(if(param_key = 'event_category', param_value, null)) as event_category,
        max(if(param_key = 'value', param_value, null)) as event_value,
        max(if(param_key = 'page_title', param_value, null)) as page_title,
        max(if(param_key = 'screen_name', param_value, null)) as raw_screen_name,
        max(
            if(
                param_key = 'firebase_screen_class',
                case
                    when param_value like '%MainActivity%' then 'HomeActivity'
                    when param_value like '%StoreActivity%' then 'ShopActivity'
                    when param_value like '%StoreDetailActivity%' then 'ShopDetailActivity'
                    else param_value
                end,
                null
            )
        ) as raw_firebase_screen_class,
        max(
            if(
                param_key = 'engagement_time_msec',
                safe_cast(param_value as int64),
                null
            )
        ) as engagement_time_msec,
        max(if(param_key = 'custom_session_id', param_value, null))
            as custom_session_id
    from raw_events
    group by
        event_dt,
        event_at,
        event_name,
        event_ts,
        user_pseudo_id,
        event_fingerprint

),

identity_prepared as (

    select
        params_pivoted.*,
        coalesce(top_user_id, param_user_id) as raw_user_id,
        case
            when top_user_id is not null then 'header'
            when param_user_id is not null then 'param'
            else null
        end as user_id_source,
        top_user_id is not null as has_top_user_id_flg,
        param_user_id is not null as has_param_user_id_flg,
        case
            when raw_screen_name in (
                'HomeActivity',
                'ShopActivity',
                'ShopDetailActivity'
            )
                then raw_screen_name
            else raw_firebase_screen_class
        end as screen_class
    from params_pivoted

),

user_id_normalized as (

    select
        identity_prepared.*,
        lower(
            trim(
                regexp_replace(
                    regexp_replace(raw_user_id, '-', '_'),
                    r'(?i)_optional\(\s*(\d+)\s*\)\s*$',
                    r'_\1'
                )
            )
        ) as uid_clean
    from identity_prepared

),

final as (

    select
        event_dt,
        event_at,
        event_name,
        event_ts,
        user_pseudo_id,
        ga_session_id,
        case
            when regexp_contains(uid_clean, r'(?i)(_nil|_null|_0)\s*$')
                then null
            when regexp_contains(uid_clean, r'(?i)^anonymous(?:_\d+)?$')
                then uid_clean
            when regexp_contains(uid_clean, r'^\d{6}_\d+$')
                then uid_clean
            else null
        end as uid_norm,
        gender,
        major,
        user_id_source,
        has_top_user_id_flg,
        has_param_user_id_flg,
        platform,
        device_category,
        device_os,
        device_os_version,
        event_label,
        event_category,
        event_value,
        page_title,
        screen_class,
        engagement_time_msec,
        custom_session_id,
        current_timestamp() as _ingested_at
    from user_id_normalized

)

select *
from final
