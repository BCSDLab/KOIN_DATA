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

{#-
  처리 범위는 호출자(Airflow 또는 사람)가 정한다.

    * 기본     : vars 없이 실행하면 최근 3일(어제 기준)을 다시 계산해 교체
    * 범위 지정: dbt run --vars '{"start_date":"YYYYMMDD","end_date":"YYYYMMDD"}'
    * 전체 적재: 분석 시작일을 명시한다
                 --vars '{"start_date":"20240711","end_date":"YYYYMMDD"}'

  전체 적재는 2년치를 스캔하므로 실수로 발생하지 않도록 항상 명시를 요구한다.
-#}
{% set ANALYSIS_START_DATE = '20240711' %}
{% set LOOKBACK_DAYS = 3 %}
{% set SIGNUP_LOOKBACK_MINUTES = 15 %}

{% set start_date_var = var('start_date', none) %}
{% set end_date_var = var('end_date', none) %}
{% set start_date = start_date_var | string if start_date_var is not none else none %}
{% set end_date = end_date_var | string if end_date_var is not none else none %}

{% if (start_date and not end_date) or (end_date and not start_date) %}
    {{ exceptions.raise_compiler_error('start_date와 end_date는 반드시 함께 지정해야 합니다.') }}
{% endif %}

{#-
  두 값은 SQL 리터럴로 직접 삽입되므로 숫자 8자리만 허용한다.
  길이만 검사하면 `1' or '1` 처럼 8자짜리 문자열이 통과해 SQL을 벗어난다.
-#}
{% if start_date and end_date %}
    {% for value in [start_date, end_date] %}
        {% if not modules.re.match('^\d{8}$', value) %}
            {{ exceptions.raise_compiler_error(
                "start_date와 end_date는 숫자 8자리(YYYYMMDD)여야 합니다. 받은 값: '" ~ value ~ "'"
            ) }}
        {% endif %}
    {% endfor %}
    {% if start_date > end_date %}
        {{ exceptions.raise_compiler_error('start_date가 end_date보다 늦을 수 없습니다.') }}
    {% endif %}
{% endif %}

{#-
  교체할 파티션 범위. vars가 없으면 최근 LOOKBACK_DAYS일.
-#}
{% if start_date and end_date %}
    {% set target_start_sql = "parse_date('%Y%m%d', '" ~ start_date ~ "')" %}
    {% set target_end_sql = "parse_date('%Y%m%d', '" ~ end_date ~ "')" %}
{% else %}
    {% set target_start_sql = "date_sub(current_date('Asia/Seoul'), interval " ~ LOOKBACK_DAYS ~ " day)" %}
    {% set target_end_sql = "date_sub(current_date('Asia/Seoul'), interval 1 day)" %}
{% endif %}

{#-
  Android 가입 세션은 시작 시각보다 앞선 이벤트를 상속해야 하므로 범위 앞쪽을
  SIGNUP_LOOKBACK_MINUTES만큼 더 읽는다. 그 lookback이 자정을 넘어 전날 테이블로
  넘어갈 수 있어 스캔 범위도 하루 더 넓힌다.
  분석 시작일에는 앞선 데이터 자체가 없으므로 둘 다 적용하지 않는다.
-#}
{% set apply_signup_lookback = start_date != ANALYSIS_START_DATE %}

{% if apply_signup_lookback %}
    {% set scan_start_sql = "format_date('%Y%m%d', date_sub(" ~ target_start_sql ~ ", interval 1 day))" %}
{% else %}
    {% set scan_start_sql = "'" ~ ANALYSIS_START_DATE ~ "'" %}
{% endif %}

{#- 날짜를 명시받았으면 리터럴로 둔다. BigQuery가 스캔할 테이블을 더 확실히 줄인다. -#}
{% if end_date %}
    {% set scan_end_sql = "'" ~ end_date ~ "'" %}
{% else %}
    {% set scan_end_sql = "format_date('%Y%m%d', " ~ target_end_sql ~ ")" %}
{% endif %}

with date_window as (

    select
        {{ target_start_sql }} as target_start_dt,
        {{ target_end_sql }} as target_end_dt

),

input_window as (

    select
        target_start_dt,
        target_end_dt,
        {% if apply_signup_lookback %}
        datetime_sub(
            datetime(target_start_dt, time '00:00:00'),
            interval {{ SIGNUP_LOOKBACK_MINUTES }} minute
        ) as input_start_at,
        {% else %}
        datetime(target_start_dt, time '00:00:00') as input_start_at,
        {% endif %}
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
    cross join input_window as input_range
    -- _table_suffix 조건은 BigQuery가 스캔할 테이블을 미리 줄이도록
    -- CTE 값이 아닌 상수 식으로 직접 쓴다.
    where regexp_contains(_table_suffix, r'^\d{8}$')
      and _table_suffix between {{ scan_start_sql }} and {{ scan_end_sql }}
      and datetime(timestamp_micros(e.event_timestamp), 'Asia/Seoul') >= input_range.input_start_at
      and datetime(timestamp_micros(e.event_timestamp), 'Asia/Seoul') < input_range.input_end_at

),

-- raw_event_id와 event_id 해시에서는 값 타입과 무관한 문자열 변환을 하지 않는다.
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

-- event_params 배열 순서만 다른 동일 raw row를 같은 payload로 취급한다.
source_payload_canonicalized as (

    select
        source_canonicalized.*,
        to_json_string(
            struct(
                to_json_string(
                    (select as struct raw_event.* except (event_params))
                ) as non_param_payload,
                canonical_event_params as event_params
            )
        ) as canonical_payload_json
    from source_canonicalized

),

-- 전송·배치 위치와 canonical event_params를 raw event의 물리 식별 정보로 사용한다.
raw_identity_prepared as (

    select
        source_payload_canonicalized.*,
        to_json_string(
            struct(
                raw_event.stream_id as stream_id,
                raw_event.user_pseudo_id as user_pseudo_id,
                raw_event.event_bundle_sequence_id as event_bundle_sequence_id,
                raw_event.event_server_timestamp_offset as event_server_timestamp_offset,
                raw_event.batch_page_id as batch_page_id,
                raw_event.batch_ordering_id as batch_ordering_id,
                raw_event.batch_event_index as batch_event_index,
                canonical_event_params as event_params
            )
        ) as raw_identity_json
    from source_payload_canonicalized

),

raw_keyed as (

    select
        raw_identity_prepared.*,
        to_hex(sha256(raw_identity_json)) as raw_event_id
    from raw_identity_prepared

),

raw_key_stats as (

    select
        raw_event_id,
        count(distinct raw_identity_json) as raw_identity_variant_count
    from raw_keyed
    group by raw_event_id

),

-- 같은 해시가 서로 다른 raw identity를 가리키면 제거하지 않고 모델을 실패시킨다.
raw_validated as (

    select raw_keyed.*
    from raw_keyed
    inner join raw_key_stats using (raw_event_id)
    where if(
        raw_identity_variant_count = 1,
        true,
        error(format('raw_event_id %s maps to multiple raw identities', raw_event_id))
    )

),

-- 물리 Bronze 테이블을 만들지 않는 대신 이 CTE에서 원천 물리 중복을 제거한다.
bronze_deduped as (

    select *
    from raw_validated
    qualify row_number() over (
        partition by raw_event_id
        order by
            canonical_payload_json,
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
    left join unnest(silver_deduped.canonical_event_params) as param
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

-- 같은 key가 반복되면 canonical 정렬 기준의 첫 번째 값을 결정적으로 사용한다.
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
        staged.*,
        last_value(
            if(
                staged.signup_stage = 'signup_start',
                struct(
                    staged.event_ts as anchor_event_ts,
                    staged.custom_session_id as anchor_custom_session_id
                ),
                null
            ) ignore nulls
        ) over (
            partition by staged.user_pseudo_id
            order by
                staged.event_ts,
                coalesce(staged.event_bundle_sequence_id, -1),
                coalesce(staged.batch_ordering_id, -1),
                coalesce(staged.batch_event_index, -1),
                staged.event_id
            rows between unbounded preceding and current row
        ) as anchor_start
    from signup_stage as staged
    where staged.platform = 'ANDROID'
      and staged.user_pseudo_id is not null
      and staged.signup_stage is not null

),

signup_candidates_localized as (

    select
        signup_candidates.* except (anchor_start),
        anchor_start.anchor_event_ts as anchor_start_event_ts,
        anchor_start.anchor_custom_session_id as anchor_custom_session_id,
        datetime(
            timestamp_micros(anchor_start.anchor_event_ts),
            'Asia/Seoul'
        ) as anchor_start_at
    from signup_candidates

),

-- 최신 가입 시작의 기존 ID를 우선 상속하고, 없을 때만 Dataform 호환 ID를 생성한다.
signup_session_fills as (

    select
        event_id,
        coalesce(
            anchor_custom_session_id,
            concat(
                'sign_up_strict_',
                cast(unix_seconds(timestamp(anchor_start_at)) as string),
                '_',
                upper(
                    substr(
                        to_hex(
                            md5(
                                concat(
                                    user_pseudo_id,
                                    cast(anchor_start_at as string)
                                )
                            )
                        ),
                        1,
                        5
                    )
                )
            )
        ) as filled_custom_session_id
    from signup_candidates_localized
    where custom_session_id is null
      and anchor_start_event_ts is not null
      and event_ts between anchor_start_event_ts and anchor_start_event_ts + (15 * 60 * 1000000)

),

signup_sessionized as (

    select
        staged.* except (
            custom_session_id,
            signup_stage,
            event_bundle_sequence_id,
            batch_ordering_id,
            batch_event_index
        ),
        coalesce(
            staged.custom_session_id,
            signup_session_fills.filled_custom_session_id
        ) as custom_session_id
    from signup_stage as staged
    left join signup_session_fills using (event_id)

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
