{{
    config(
        materialized='incremental',
        incremental_strategy='insert_overwrite',
        partition_by={
            'field': 'event_dt',
            'data_type': 'date',
            'granularity': 'day'
        },
        cluster_by=['event_id', 'user_pseudo_id', 'event_name'],
        on_schema_change='fail'
    )
}}

-- 처리 기준
--   * 전체 적재: batch_* 필드가 안정적으로 존재하는 2024-07-11부터 어제까지
--   * 증분 적재: 완료된 최근 3일 파티션을 다시 계산해 원자적으로 교체
--   * Android 가입 세션: 대상 시작 시각보다 15분 앞선 이벤트까지 읽되 최종 출력에서 제외

with date_window as (

    select
        {% if is_incremental() %}
            date_sub(current_date('Asia/Seoul'), interval 3 day) as target_start_dt,
        {% else %}
            date '2024-07-11' as target_start_dt,
        {% endif %}
        date_sub(current_date('Asia/Seoul'), interval 1 day) as target_end_dt

),

input_window as (

    select
        target_start_dt,
        target_end_dt,
        datetime_sub(
            datetime(target_start_dt, time '00:00:00'),
            interval 15 minute
        ) as input_start_at,
        datetime(
            date_add(target_end_dt, interval 1 day),
            time '00:00:00'
        ) as input_end_at
    from date_window

),

-- 확정 일별 테이블만 읽는다. intraday 테이블은 별도의 실시간 요구가 생길 때 분리한다.
source_filtered as (

    select
        e as raw_event,
        _table_suffix as source_table_suffix
    from {{ source('ga4', 'events') }} as e
    cross join input_window as window
    where regexp_contains(_table_suffix, r'^\d{8}$')
      {% if is_incremental() %}
      -- target_start_dt의 15분 lookback이 전날로 넘어갈 수 있어 하루를 더 스캔한다.
      and _table_suffix between
          format_date('%Y%m%d', date_sub(current_date('Asia/Seoul'), interval 4 day))
          and format_date('%Y%m%d', date_sub(current_date('Asia/Seoul'), interval 1 day))
      {% else %}
      and _table_suffix between
          '20240710'
          and format_date('%Y%m%d', date_sub(current_date('Asia/Seoul'), interval 1 day))
      {% endif %}
      and datetime(timestamp_micros(e.event_timestamp), 'Asia/Seoul') >= window.input_start_at
      and datetime(timestamp_micros(e.event_timestamp), 'Asia/Seoul') < window.input_end_at

),

-- event_id 해시에서는 값 타입과 무관한 문자열 변환을 하지 않는다.
source_canonicalized as (

    select
        source_filtered.*,
        array(
            select as struct
                param.key,
                param.value
            from unnest(source_filtered.raw_event.event_params) as param
            order by
                param.key,
                to_json_string(param.value)
        ) as canonical_event_params
    from source_filtered

),

raw_keyed as (

    select
        source_canonicalized.*,
        to_hex(
            sha256(
                to_json_string(
                    struct(
                        raw_event.stream_id as stream_id,
                        raw_event.user_pseudo_id as user_pseudo_id,
                        raw_event.event_bundle_sequence_id as event_bundle_sequence_id,
                        raw_event.event_server_timestamp_offset as event_server_timestamp_offset,
                        raw_event.batch_page_id as batch_page_id,
                        raw_event.batch_ordering_id as batch_ordering_id,
                        raw_event.batch_event_index as batch_event_index
                    )
                )
            )
        ) as raw_event_id,
        to_hex(sha256(to_json_string(raw_event))) as canonical_payload_hash
    from source_canonicalized

),

raw_key_stats as (

    select
        raw_event_id,
        count(distinct canonical_payload_hash) as payload_variant_count
    from raw_keyed
    group by raw_event_id

),

-- 같은 raw_event_id가 서로 다른 payload를 가리키면 제거하지 않고 모델을 실패시킨다.
raw_validated as (

    select raw_keyed.*
    from raw_keyed
    inner join raw_key_stats using (raw_event_id)
    where if(
        payload_variant_count = 1,
        true,
        error(format('raw_event_id %s maps to multiple payloads', raw_event_id))
    )

),

-- 물리 Bronze 테이블을 만들지 않는 대신 이 CTE에서 원천 물리 중복을 제거한다.
bronze_deduped as (

    select *
    from raw_validated
    qualify row_number() over (
        partition by raw_event_id
        order by
            canonical_payload_hash,
            to_json_string(raw_event),
            source_table_suffix
    ) = 1

),

event_identity_prepared as (

    select
        bronze_deduped.*,
        to_json_string(
            struct(
                raw_event.stream_id as stream_id,
                raw_event.user_pseudo_id as user_pseudo_id,
                raw_event.event_timestamp as event_timestamp,
                raw_event.event_name as event_name,
                raw_event.event_bundle_sequence_id as event_bundle_sequence_id,
                raw_event.batch_event_index as batch_event_index,
                canonical_event_params as event_params
            )
        ) as event_identity_json
    from bronze_deduped

),

event_keyed as (

    select
        event_identity_prepared.*,
        to_hex(
            sha256(event_identity_json)
        ) as event_id
    from event_identity_prepared

),

event_key_stats as (

    select
        event_id,
        count(distinct event_identity_json) as identity_variant_count
    from event_keyed
    group by event_id

),

-- 같은 해시가 서로 다른 event identity를 가리키면 논리 중복으로 축약하지 않는다.
event_validated as (

    select event_keyed.*
    from event_keyed
    inner join event_key_stats using (event_id)
    where if(
        identity_variant_count = 1,
        true,
        error(format('event_id %s maps to multiple event identities', event_id))
    )

),

-- 추후 event_id -> 전체 raw_event_id 계보 모델이 필요하면 이 CTE를 분기점으로 사용한다.
event_lineage_candidate as (

    select *
    from event_validated

),

silver_deduped as (

    select *
    from event_lineage_candidate
    qualify row_number() over (
        partition by event_id
        order by raw_event_id
    ) = 1

),

-- 중복 제거가 모두 끝난 뒤에만 event_params를 펼친다.
params_unnested as (

    select
        silver_deduped.raw_event_id,
        silver_deduped.event_id,
        silver_deduped.raw_event.event_timestamp as event_ts,
        datetime(
            timestamp_micros(silver_deduped.raw_event.event_timestamp),
            'Asia/Seoul'
        ) as event_at,
        date(
            timestamp_micros(silver_deduped.raw_event.event_timestamp),
            'Asia/Seoul'
        ) as event_dt,
        silver_deduped.raw_event.event_name as event_name,
        silver_deduped.raw_event.user_pseudo_id as user_pseudo_id,
        silver_deduped.raw_event.platform as platform,
        silver_deduped.raw_event.device.category as device_category,
        silver_deduped.raw_event.device.operating_system as device_os,
        silver_deduped.raw_event.device.operating_system_version as device_os_version,
        silver_deduped.raw_event.event_bundle_sequence_id as event_bundle_sequence_id,
        silver_deduped.raw_event.batch_ordering_id as batch_ordering_id,
        silver_deduped.raw_event.batch_event_index as batch_event_index,
        param.key as param_key,
        param.value as param_value,
        param_offset
    from silver_deduped
    left join unnest(silver_deduped.raw_event.event_params) as param
        with offset as param_offset
        on true

),

param_values as (

    select
        params_unnested.*,
        coalesce(
            param_value.string_value,
            cast(param_value.int_value as string),
            cast(param_value.float_value as string),
            cast(param_value.double_value as string)
        ) as param_value_as_string
    from params_unnested

),

-- 같은 key가 반복되면 원본 배열의 첫 번째 값을 결정적으로 사용한다.
params_first_occurrence as (

    select *
    from param_values
    qualify
        param_key is null
        or row_number() over (
            partition by event_id, param_key
            order by param_offset
        ) = 1

),

params_pivoted as (

    select
        raw_event_id,
        event_id,
        event_dt,
        event_at,
        event_ts,
        event_name,
        user_pseudo_id,
        platform,
        device_category,
        device_os,
        device_os_version,
        event_bundle_sequence_id,
        batch_ordering_id,
        batch_event_index,
        max(if(param_key = 'ga_session_id', param_value_as_string, null)) as ga_session_id,
        max(if(param_key = 'custom_session_id', param_value_as_string, null)) as custom_session_id,
        max(if(param_key = 'event_label', param_value_as_string, null)) as event_label,
        max(if(param_key = 'event_category', param_value_as_string, null)) as event_category,
        max(if(param_key = 'value', param_value_as_string, null)) as event_value,
        max(if(param_key = 'page_title', param_value_as_string, null)) as page_title,
        max(if(param_key = 'page_location', param_value_as_string, null)) as page_location,
        max(if(param_key = 'screen_name', param_value_as_string, null)) as raw_screen_name,
        max(if(param_key = 'firebase_screen_class', param_value_as_string, null)) as raw_firebase_screen_class,
        max(
            if(
                param_key = 'engagement_time_msec',
                safe_cast(param_value_as_string as int64),
                null
            )
        ) as engagement_time_msec
    from params_first_occurrence
    group by
        raw_event_id,
        event_id,
        event_dt,
        event_at,
        event_ts,
        event_name,
        user_pseudo_id,
        platform,
        device_category,
        device_os,
        device_os_version,
        event_bundle_sequence_id,
        batch_ordering_id,
        batch_event_index

),

normalized as (

    select
        params_pivoted.* except (raw_screen_name, raw_firebase_screen_class),
        case
            when raw_screen_name in ('HomeActivity', 'ShopActivity', 'ShopDetailActivity')
                then raw_screen_name
            when raw_firebase_screen_class like '%MainActivity%'
                then 'HomeActivity'
            when raw_firebase_screen_class like '%StoreDetailActivity%'
                then 'ShopDetailActivity'
            when raw_firebase_screen_class like '%StoreActivity%'
                then 'ShopActivity'
            else raw_firebase_screen_class
        end as screen_class
    from params_pivoted

),

-- 전체 서비스/퍼널 매핑 대신 가입 세션 보정에 필요한 최소 단계만 계산한다.
signup_stage as (

    select
        normalized.*,
        case
            when lower(trim(coalesce(event_label, ''))) = 'sign_up_completed'
                then 'signup_complete'
            when lower(trim(coalesce(event_label, ''))) = 'create_account'
                then 'form_entry'
            when lower(trim(coalesce(event_label, ''))) = 'identity_verification'
                then 'identity_verification'
            when lower(trim(coalesce(event_label, ''))) = 'terms_agreement'
                then 'terms_agreement'
            when lower(trim(coalesce(event_value, ''))) = '회원가입 시작'
                then 'signup_start'
            else null
        end as signup_stage
    from normalized

),

signup_candidates as (

    select
        signup_stage.*,
        last_value(
            if(signup_stage = 'signup_start', event_ts, null) ignore nulls
        ) over (
            partition by user_pseudo_id
            order by
                event_ts,
                coalesce(event_bundle_sequence_id, -1),
                coalesce(batch_ordering_id, -1),
                coalesce(batch_event_index, -1),
                event_id
            rows between unbounded preceding and current row
        ) as anchor_start_event_ts
    from signup_stage
    where platform = 'ANDROID'
      and custom_session_id is null
      and user_pseudo_id is not null
      and signup_stage is not null

),

generated_signup_sessions as (

    select
        event_id,
        concat(
            'sign_up_strict_',
            cast(div(anchor_start_event_ts, 1000000) as string),
            '_',
            upper(
                substr(
                    to_hex(
                        md5(
                            concat(
                                user_pseudo_id,
                                cast(anchor_start_event_ts as string)
                            )
                        )
                    ),
                    1,
                    5
                )
            )
        ) as generated_custom_session_id
    from signup_candidates
    where anchor_start_event_ts is not null
      and event_ts between anchor_start_event_ts and anchor_start_event_ts + (15 * 60 * 1000000)

),

signup_sessionized as (

    select
        signup_stage.* except (
            custom_session_id,
            signup_stage,
            event_bundle_sequence_id,
            batch_ordering_id,
            batch_event_index
        ),
        coalesce(
            signup_stage.custom_session_id,
            generated_signup_sessions.generated_custom_session_id
        ) as custom_session_id
    from signup_stage
    left join generated_signup_sessions using (event_id)

),

final_target_dates as (

    select
        signup_sessionized.raw_event_id,
        signup_sessionized.event_id,
        signup_sessionized.event_dt,
        signup_sessionized.event_at,
        signup_sessionized.event_ts,
        signup_sessionized.event_name,
        signup_sessionized.user_pseudo_id,
        signup_sessionized.ga_session_id,
        signup_sessionized.custom_session_id,
        signup_sessionized.platform,
        signup_sessionized.device_category,
        signup_sessionized.device_os,
        signup_sessionized.device_os_version,
        signup_sessionized.event_label,
        signup_sessionized.event_category,
        signup_sessionized.event_value,
        signup_sessionized.page_title,
        signup_sessionized.screen_class,
        signup_sessionized.engagement_time_msec,
        signup_sessionized.page_location
    from signup_sessionized
    cross join date_window
    where signup_sessionized.event_dt between date_window.target_start_dt and date_window.target_end_dt

)

select *
from final_target_dates
