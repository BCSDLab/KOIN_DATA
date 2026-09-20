{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='user_pseudo_id',
        cluster_by=['user_pseudo_id', 'user_id'],
        on_schema_change='fail'
    )
}}

{#-
  운영 전환 후보 사용자 Dimension.
  날짜 처리는 Lightsail 운영 silver_events와 같은 원본 흐름을 따른다.

    * 기본     : vars 없이 실행하면 최근 3일(어제 기준)의 관측값을 MERGE한다.
    * 범위 지정: dbt run --vars '{"start_date":"YYYYMMDD","end_date":"YYYYMMDD"}'
    * 최초 운영: 전체 GA4 이력을 명시 범위로 수동 실행해 Dimension을 만든다.

  개선 후보 (현재 동작을 유지하기 위해 적용하지 않음):

    * Airflow 실행은 항상 start_date/end_date를 넘겨 재시도·백필 범위를 고정한다.
    * user Dimension의 최초 Prod 적재는 최근 3일 기본값을 쓰면 불완전해진다.
      아래 보호막을 유지하고, 전체 이력을 명시한 수동 실행 뒤에만 일일 스케줄을 켠다.
    * user는 날짜 fact가 아니므로 events처럼 insert_overwrite 파티션 모델로 바꾸지 않고
      user_pseudo_id 기준 MERGE를 유지한다.
-#}
{% set LOOKBACK_DAYS = 3 %}

{% set start_date_var = var('start_date', none) %}
{% set end_date_var = var('end_date', none) %}
{% set start_date = start_date_var | string if start_date_var is not none else none %}
{% set end_date = end_date_var | string if end_date_var is not none else none %}
{% set reconcile_window = var('reconcile_window', false) %}
{# compile 시 존재하지 않는 대상 테이블을 참조하지 않도록 하는 전용 변수 #}
{% set incremental_mode = is_incremental() or var('_compile_incremental', false) %}

{#- SQL 리터럴에 직접 쓰는 날짜는 숫자 8자리만 허용한다. -#}
{% if (start_date and not end_date) or (end_date and not start_date) %}
    {{ exceptions.raise_compiler_error('start_date와 end_date는 반드시 함께 지정해야 합니다.') }}
{% endif %}

{% if start_date and end_date %}
    {% for value in [start_date, end_date] %}
        {% if not modules.re.match('^[0-9]{8}$', value) %}
            {{ exceptions.raise_compiler_error(
                "start_date와 end_date는 숫자 8자리(YYYYMMDD)여야 합니다. 받은 값: '" ~ value ~ "'"
            ) }}
        {% endif %}
    {% endfor %}
    {% if start_date > end_date %}
        {{ exceptions.raise_compiler_error('start_date가 end_date보다 늦을 수 없습니다.') }}
    {% endif %}
{% endif %}

{#- 월간 보정은 기존 누적 상태가 있어야만 안전하게 적용할 수 있다. -#}
{% if execute and reconcile_window and not incremental_mode %}
    {{ exceptions.raise_compiler_error(
        'silver__users 월간 보정은 최초 적재에 사용할 수 없습니다. '
        ~ '먼저 reconcile_window=false로 전체 GA4 이력을 적재하세요.'
    ) }}
{% endif %}

{#- Prod 최초 실행이 최근 3일 기본값으로 불완전하게 생성되는 것을 막는다. -#}
{% if execute and target.name == 'prod' and not is_incremental() %}
    {% if not start_date or not end_date %}
        {{ exceptions.raise_compiler_error(
            'silver__users 최초 운영 실행은 전체 GA4 이력의 '
            ~ 'start_date/end_date를 지정해 수동 실행해야 합니다.'
        ) }}
    {% else %}
        {% set initial_range_days = (
            modules.datetime.datetime.strptime(end_date, '%Y%m%d')
            - modules.datetime.datetime.strptime(start_date, '%Y%m%d')
        ).days + 1 %}
        {% if initial_range_days <= LOOKBACK_DAYS %}
            {{ exceptions.raise_compiler_error(
                'silver__users 최초 운영 실행은 3일 스케줄이 아니라 '
                ~ '전체 GA4 이력의 start_date/end_date로 수동 실행해야 합니다.'
            ) }}
        {% endif %}
    {% endif %}
{% endif %}

{% if start_date and end_date %}
    {% set target_start_sql = "parse_date('%Y%m%d', '" ~ start_date ~ "')" %}
    {% set target_end_sql = "parse_date('%Y%m%d', '" ~ end_date ~ "')" %}
{% else %}
    {% set target_start_sql = "date_sub(current_date('Asia/Seoul'), interval " ~ LOOKBACK_DAYS ~ " day)" %}
    {% set target_end_sql = "date_sub(current_date('Asia/Seoul'), interval 1 day)" %}
{% endif %}

{# KST 하루의 앞부분이 전날 UTC suffix에 있을 수 있어 하루 앞 테이블부터 읽는다. #}
{% set scan_start_sql = "format_date('%Y%m%d', date_sub(" ~ target_start_sql ~ ", interval 1 day))" %}
{% if end_date %}
    {% set scan_end_sql = "'" ~ end_date ~ "'" %}
{% else %}
    {% set scan_end_sql = "format_date('%Y%m%d', " ~ target_end_sql ~ ")" %}
{% endif %}

with existing_users as (

    {% if incremental_mode %}
    select
        user_pseudo_id,
        stream_id,
        user_id,
        user_id_source,
        top_user_id,
        property_user_id,
        param_user_id,
        gender,
        major,
        entry_year,
        first_seen_at,
        last_seen_at,
        user_id_support_count,
        source_event_count,
        property_user_id_set_ts,
        user_type,
        signup_completed_at,
        is_deleted,
        is_mysql_mapped
    from {{ this }}
    {% else %}
    select
        cast(null as string) as user_pseudo_id,
        cast(null as string) as stream_id,
        cast(null as string) as user_id,
        cast(null as string) as user_id_source,
        cast(null as string) as top_user_id,
        cast(null as string) as property_user_id,
        cast(null as string) as param_user_id,
        cast(null as string) as gender,
        cast(null as string) as major,
        cast(null as int64) as entry_year,
        cast(null as datetime) as first_seen_at,
        cast(null as datetime) as last_seen_at,
        cast(null as int64) as user_id_support_count,
        cast(null as int64) as source_event_count,
        cast(null as int64) as property_user_id_set_ts,
        cast(null as string) as user_type,
        cast(null as timestamp) as signup_completed_at,
        cast(null as int64) as is_deleted,
        cast(null as bool) as is_mysql_mapped
    from (select 1) as empty_source
    where false
    {% endif %}

),

source_filtered as (

    select
        e.stream_id,
        e.event_timestamp as event_ts,
        datetime(
            timestamp_micros(e.event_timestamp),
            'Asia/Seoul'
        ) as event_at,
        date(
            timestamp_micros(e.event_timestamp),
            'Asia/Seoul'
        ) as event_dt,
        e.user_pseudo_id,
        e.user_id as top_user_id_raw,
        (
            select as struct
                coalesce(
                    property.value.string_value,
                    cast(property.value.int_value as string),
                    cast(property.value.float_value as string),
                    cast(property.value.double_value as string)
                ) as user_id_raw,
                property.value.set_timestamp_micros as set_timestamp_micros
            from unnest(e.user_properties) as property
            where lower(property.key) = 'user_id'
            order by to_json_string(property.value)
            limit 1
        ) as property_user,
        (
            select
                coalesce(
                    param.value.string_value,
                    cast(param.value.int_value as string),
                    cast(param.value.float_value as string),
                    cast(param.value.double_value as string)
                )
            from unnest(e.event_params) as param
            where lower(param.key) = 'user_id'
            order by to_json_string(param.value)
            limit 1
        ) as param_user_id_raw,
        (
            select
                coalesce(
                    param.value.string_value,
                    cast(param.value.int_value as string),
                    cast(param.value.float_value as string),
                    cast(param.value.double_value as string)
                )
            from unnest(e.event_params) as param
            where lower(param.key) = 'gender'
            order by to_json_string(param.value)
            limit 1
        ) as gender_raw,
        (
            select
                coalesce(
                    param.value.string_value,
                    cast(param.value.int_value as string),
                    cast(param.value.float_value as string),
                    cast(param.value.double_value as string)
                )
            from unnest(e.event_params) as param
            where lower(param.key) = 'major'
            order by to_json_string(param.value)
            limit 1
        ) as major_raw
    from {{ source('ga4', 'events') }} as e
    left join existing_users
        on e.user_pseudo_id = existing_users.user_pseudo_id
    where regexp_contains(_table_suffix, r'^\d{8}$')
      and _table_suffix between {{ scan_start_sql }} and {{ scan_end_sql }}
      and date(timestamp_micros(e.event_timestamp), 'Asia/Seoul') between
          {{ target_start_sql }} and {{ target_end_sql }}
      {% if incremental_mode and not reconcile_window %}
      and (
          existing_users.user_pseudo_id is null
          or datetime(
              timestamp_micros(e.event_timestamp),
              'Asia/Seoul'
          ) > existing_users.last_seen_at
      )
      {% endif %}

),

identity_extracted as (

    select
        stream_id,
        event_ts,
        event_at,
        event_dt,
        user_pseudo_id,
        top_user_id_raw,
        property_user.user_id_raw as property_user_id_raw,
        property_user.set_timestamp_micros as property_user_id_set_ts,
        param_user_id_raw,
        gender_raw,
        major_raw
    from source_filtered

),

identifiers_cleaned as (

    select
        identity_extracted.*,
        nullif(
            lower(
                trim(
                    regexp_replace(
                        regexp_replace(
                            regexp_replace(
                                top_user_id_raw,
                                r'[\p{Cc}\p{Zl}\p{Zp}]',
                                ''
                            ),
                            '-',
                            '_'
                        ),
                        r'(?i)_optional\(\s*(\d+)\s*\)\s*$',
                        r'_\1'
                    )
                )
            ),
            ''
        ) as top_user_id_clean,
        nullif(
            lower(
                trim(
                    regexp_replace(
                        regexp_replace(
                            regexp_replace(
                                property_user_id_raw,
                                r'[\p{Cc}\p{Zl}\p{Zp}]',
                                ''
                            ),
                            '-',
                            '_'
                        ),
                        r'(?i)_optional\(\s*(\d+)\s*\)\s*$',
                        r'_\1'
                    )
                )
            ),
            ''
        ) as property_user_id_clean,
        nullif(
            lower(
                trim(
                    regexp_replace(
                        regexp_replace(
                            regexp_replace(
                                param_user_id_raw,
                                r'[\p{Cc}\p{Zl}\p{Zp}]',
                                ''
                            ),
                            '-',
                            '_'
                        ),
                        r'(?i)_optional\(\s*(\d+)\s*\)\s*$',
                        r'_\1'
                    )
                )
            ),
            ''
        ) as param_user_id_clean,
        nullif(
            lower(
                trim(
                    regexp_replace(
                        gender_raw,
                        r'[\p{Cc}\p{Zl}\p{Zp}]',
                        ''
                    )
                )
            ),
            ''
        ) as gender,
        nullif(
            lower(
                trim(
                    regexp_replace(
                        major_raw,
                        r'[\p{Cc}\p{Zl}\p{Zp}]',
                        ''
                    )
                )
            ),
            ''
        ) as major
    from identity_extracted

),

identifiers_validated as (

    select
        identifiers_cleaned.*,
        case
            when regexp_contains(
                top_user_id_clean,
                r'(?i)(_nil|_null|_0)\s*$'
            )
                then null
            when regexp_contains(
                top_user_id_clean,
                r'(?i)^anonymous(?:_\d+)?$'
            )
                then top_user_id_clean
            when regexp_contains(top_user_id_clean, r'^\d{6}_\d+$')
                then top_user_id_clean
            else null
        end as top_user_id,
        case
            when regexp_contains(
                property_user_id_clean,
                r'(?i)(_nil|_null|_0)\s*$'
            )
                then null
            when regexp_contains(
                property_user_id_clean,
                r'(?i)^anonymous(?:_\d+)?$'
            )
                then property_user_id_clean
            when regexp_contains(property_user_id_clean, r'^\d{6}_\d+$')
                then property_user_id_clean
            else null
        end as property_user_id,
        case
            when regexp_contains(
                param_user_id_clean,
                r'(?i)(_nil|_null|_0)\s*$'
            )
                then null
            when regexp_contains(
                param_user_id_clean,
                r'(?i)^anonymous(?:_\d+)?$'
            )
                then param_user_id_clean
            when regexp_contains(param_user_id_clean, r'^\d{6}_\d+$')
                then param_user_id_clean
            else null
        end as param_user_id
    from identifiers_cleaned

),

identity_resolved as (

    select
        identifiers_validated.*,
        coalesce(
            top_user_id,
            param_user_id
        ) as resolved_user_id,
        case
            when top_user_id is not null then 'header'
            when param_user_id is not null then 'event_param'
            else null
        end as user_id_source
    from identifiers_validated
    where user_pseudo_id is not null

),

identity_observation_prepared as (

    select
        identity_resolved.*,
        to_json_string(
            struct(
                stream_id as stream_id,
                user_pseudo_id as user_pseudo_id,
                event_ts as event_ts,
                top_user_id as top_user_id,
                property_user_id as property_user_id,
                param_user_id as param_user_id,
                gender as gender,
                major as major
            )
        ) as identity_observation_json
    from identity_resolved

),

identity_observations_deduped as (

    select
        identity_observation_prepared.*,
        to_hex(sha256(identity_observation_json)) as identity_observation_id
    from identity_observation_prepared
    qualify row_number() over (
        partition by to_hex(sha256(identity_observation_json))
        order by
            event_at,
            coalesce(property_user_id_set_ts, 0)
    ) = 1

),

daily_identity_states as (

    select
        event_dt,
        stream_id,
        user_pseudo_id,
        top_user_id,
        property_user_id,
        param_user_id,
        resolved_user_id,
        user_id_source,
        gender,
        major,
        min(event_at) as first_seen_at,
        max(event_at) as last_seen_at,
        min(property_user_id_set_ts) as property_user_id_set_ts,
        count(*) as source_event_count
    from identity_observations_deduped
    group by
        event_dt,
        stream_id,
        user_pseudo_id,
        top_user_id,
        property_user_id,
        param_user_id,
        resolved_user_id,
        user_id_source,
        gender,
        major

),

recent_candidate_states as (

    select
        daily_identity_states.*,
        source_event_count as base_user_id_support_count,
        to_hex(
            sha256(
                to_json_string(
                    struct(
                        event_dt as event_dt,
                        stream_id as stream_id,
                        user_pseudo_id as user_pseudo_id,
                        top_user_id as top_user_id,
                        property_user_id as property_user_id,
                        param_user_id as param_user_id,
                        gender as gender,
                        major as major
                    )
                )
            )
        ) as user_identity_state_id
    from daily_identity_states

),

existing_candidate_states as (

    select
        date(last_seen_at) as event_dt,
        stream_id,
        user_pseudo_id,
        top_user_id,
        property_user_id,
        param_user_id,
        user_id as resolved_user_id,
        user_id_source,
        gender,
        major,
        first_seen_at,
        last_seen_at,
        property_user_id_set_ts,
        source_event_count,
        user_id_support_count as base_user_id_support_count,
        to_hex(
            sha256(
                to_json_string(
                    struct(
                        'existing' as state_origin,
                        user_pseudo_id as user_pseudo_id,
                        user_id as user_id,
                        last_seen_at as last_seen_at
                    )
                )
            )
        ) as user_identity_state_id
    from existing_users

),

all_candidate_states as (

    select * from existing_candidate_states
    union all
    select * from recent_candidate_states

),

candidate_prepared as (

    select
        all_candidate_states.*,
        case
            when resolved_user_id is null then 2
            when regexp_contains(
                resolved_user_id,
                r'(?i)^anonymous(?:_\d+)?$'
            )
                then 1
            else 0
        end as user_id_priority,
        case user_id_source
            when 'header' then 0
            when 'event_param' then 1
            else 2
        end as user_id_source_priority,
        coalesce(
            cast(
                regexp_contains(resolved_user_id, r'^\d{6}_\d+$')
                as int64
            ),
            0
        )
            + cast(gender is not null as int64)
            + cast(major is not null as int64) as completeness
    from all_candidate_states

),

candidate_scored as (

    select
        candidate_prepared.*,
        sum(base_user_id_support_count) over (
            partition by user_pseudo_id, resolved_user_id
        ) as user_id_support_count,
        max(completeness) over (
            partition by user_pseudo_id, resolved_user_id
        ) as user_id_completeness,
        max(last_seen_at) over (
            partition by user_pseudo_id, resolved_user_id
        ) as user_id_latest_seen_at
    from candidate_prepared

),

canonical_observation as (

    select *
    from candidate_scored
    qualify row_number() over (
        partition by user_pseudo_id
        order by
            user_id_priority,
            user_id_source_priority,
            user_id_completeness desc,
            user_id_support_count desc,
            user_id_latest_seen_at desc,
            last_seen_at desc,
            user_identity_state_id
    ) = 1

),

latest_attributes as (

    select
        user_pseudo_id,
        array_agg(
            gender ignore nulls
            order by last_seen_at desc, user_identity_state_id
            limit 1
        )[safe_offset(0)] as gender,
        array_agg(
            major ignore nulls
            order by last_seen_at desc, user_identity_state_id
            limit 1
        )[safe_offset(0)] as major
    from all_candidate_states
    group by user_pseudo_id

),

user_lifetime as (

    select
        user_pseudo_id,
        min(first_seen_at) as first_seen_at,
        max(last_seen_at) as last_seen_at,
        sum(source_event_count) as source_event_count
    from all_candidate_states
    group by user_pseudo_id

),

ga4_users as (

    select
        canonical_observation.user_pseudo_id,
        canonical_observation.stream_id,
        canonical_observation.resolved_user_id as user_id,
        canonical_observation.user_id_source,
        canonical_observation.top_user_id,
        canonical_observation.property_user_id,
        canonical_observation.param_user_id,
        coalesce(
            canonical_observation.gender,
            latest_attributes.gender
        ) as gender,
        coalesce(
            canonical_observation.major,
            latest_attributes.major
        ) as major,
        safe_cast(
            regexp_extract(
                canonical_observation.resolved_user_id,
                r'^(20\d{2})'
            )
            as int64
        ) as entry_year,
        user_lifetime.first_seen_at,
        user_lifetime.last_seen_at,
        canonical_observation.user_id_support_count,
        user_lifetime.source_event_count,
        canonical_observation.property_user_id_set_ts,
        safe_cast(
            regexp_extract(
                canonical_observation.resolved_user_id,
                r'_(\d+)\s*$'
            )
            as int64
        ) as user_id_mysql
    from canonical_observation
    left join latest_attributes using (user_pseudo_id)
    left join user_lifetime using (user_pseudo_id)

),

{% if reconcile_window %}
monthly_attributes as (

    select
        user_pseudo_id,
        min(event_at) as monthly_first_seen_at,
        max(event_at) as monthly_last_seen_at,
        array_agg(
            gender ignore nulls
            order by event_at desc, identity_observation_id
            limit 1
        )[safe_offset(0)] as monthly_gender,
        array_agg(
            major ignore nulls
            order by event_at desc, identity_observation_id
            limit 1
        )[safe_offset(0)] as monthly_major
    from identity_observations_deduped
    group by user_pseudo_id

),

monthly_reconciled_existing_prepared as (

    select
        existing_users.user_pseudo_id,
        existing_users.stream_id,
        existing_users.user_id,
        existing_users.user_id_source,
        existing_users.top_user_id,
        existing_users.property_user_id,
        existing_users.param_user_id,
        coalesce(
            monthly_attributes.monthly_gender,
            existing_users.gender
        ) as gender,
        coalesce(
            monthly_attributes.monthly_major,
            existing_users.major
        ) as major,
        existing_users.entry_year,
        case
            when existing_users.first_seen_at is null
                then monthly_attributes.monthly_first_seen_at
            else least(
                existing_users.first_seen_at,
                monthly_attributes.monthly_first_seen_at
            )
        end as first_seen_at,
        case
            when existing_users.last_seen_at is null
                then monthly_attributes.monthly_last_seen_at
            else greatest(
                existing_users.last_seen_at,
                monthly_attributes.monthly_last_seen_at
            )
        end as last_seen_at,
        existing_users.user_id_support_count,
        existing_users.source_event_count,
        existing_users.property_user_id_set_ts,
        safe_cast(
            regexp_extract(existing_users.user_id, r'_(\d+)\s*$')
            as int64
        ) as user_id_mysql,
        existing_users.user_type as persisted_user_type,
        existing_users.signup_completed_at as persisted_signup_completed_at,
        existing_users.is_deleted as persisted_is_deleted,
        existing_users.is_mysql_mapped as persisted_is_mysql_mapped,
        true as is_monthly_existing,
        existing_users.first_seen_at as previous_first_seen_at,
        existing_users.last_seen_at as previous_last_seen_at,
        existing_users.gender as previous_gender,
        existing_users.major as previous_major
    from existing_users
    inner join monthly_attributes using (user_pseudo_id)

),

monthly_reconciled_existing as (

    select * except (
        previous_first_seen_at,
        previous_last_seen_at,
        previous_gender,
        previous_major
    )
    from monthly_reconciled_existing_prepared
    where first_seen_at is distinct from previous_first_seen_at
       or last_seen_at is distinct from previous_last_seen_at
       or gender is distinct from previous_gender
       or major is distinct from previous_major

),

monthly_new_users as (

    {#-
      월간 보정은 기존 사용자의 identity/count를 동결한다. 다만 일간 실행이
      누락됐더라도 최근 구간에서 처음 보인 사용자는 일반 증분 계산 결과로 삽입한다.
    -#}
    select
        ga4_users.*,
        cast(null as string) as persisted_user_type,
        cast(null as timestamp) as persisted_signup_completed_at,
        cast(null as int64) as persisted_is_deleted,
        cast(null as bool) as persisted_is_mysql_mapped,
        false as is_monthly_existing
    from ga4_users
    left join existing_users using (user_pseudo_id)
    where existing_users.user_pseudo_id is null

),

users_to_enrich as (

    select * from monthly_reconciled_existing
    union all
    select * from monthly_new_users

),

{% else %}
users_to_enrich as (

    select * from ga4_users

),

{% endif %}
mysql_users as (

    {#-
      월간 보정의 기존 사용자는 MySQL 속성을 저장된 값으로 유지한다.
      app_db.koin_users가 최신 스냅샷임이 운영적으로 보장되면,
      user_type, signup_completed_at, is_deleted, is_mysql_mapped는
      GA4 보정과 분리한 비교 CTE를 추가해 별도로 최신화할 수 있다.
    -#}
    select
        safe_cast(id as int64) as id,
        user_type,
        cast(created_at as timestamp) as signup_completed_at,
        safe_cast(is_deleted as int64) as is_deleted
    from {{ source('app_db', 'koin_users') }}

),

final as (

    select
        users_to_enrich.user_pseudo_id,
        users_to_enrich.stream_id,
        users_to_enrich.user_id,
        users_to_enrich.user_id_source,
        users_to_enrich.top_user_id,
        users_to_enrich.property_user_id,
        users_to_enrich.param_user_id,
        users_to_enrich.gender,
        users_to_enrich.major,
        users_to_enrich.entry_year,
        users_to_enrich.first_seen_at,
        users_to_enrich.last_seen_at,
        users_to_enrich.user_id_support_count,
        users_to_enrich.source_event_count,
        users_to_enrich.property_user_id_set_ts,
        {% if reconcile_window %}
        case
            when users_to_enrich.is_monthly_existing
                then users_to_enrich.persisted_user_type
            else mysql_users.user_type
        end as user_type,
        case
            when users_to_enrich.is_monthly_existing
                then users_to_enrich.persisted_signup_completed_at
            else mysql_users.signup_completed_at
        end as signup_completed_at,
        case
            when users_to_enrich.is_monthly_existing
                then users_to_enrich.persisted_is_deleted
            else mysql_users.is_deleted
        end as is_deleted,
        case
            when users_to_enrich.is_monthly_existing
                then users_to_enrich.persisted_is_mysql_mapped
            else mysql_users.id is not null
        end as is_mysql_mapped
        {% else %}
        mysql_users.user_type,
        mysql_users.signup_completed_at,
        mysql_users.is_deleted,
        mysql_users.id is not null as is_mysql_mapped
        {% endif %}
    from users_to_enrich
    left join mysql_users
        on users_to_enrich.user_id_mysql = mysql_users.id

)

select *
from final
