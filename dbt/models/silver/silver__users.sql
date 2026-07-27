{{
    config(
        materialized='table',
        cluster_by=['user_pseudo_id', 'user_id'],
        on_schema_change='fail'
    )
}}

{#-
  Dataform의 canonical 선정과 mart.table_mart_dim_users 결합을 한 모델로 이관한다.

  grain: user_pseudo_id당 1행
  입력:
    * silver__user_identity_events     — GA4 사용자 식별자 관측 이력
    * analytics_432041405.koin_users   — 앱 MySQL 회원 원천

  날짜 변수는 사용하지 않는다. 누적된 identity 전체 이력을 매번 다시 읽어
  user_pseudo_id별 canonical user_id를 선정한 뒤 앱 회원정보를 결합한다.
-#}

with identity_base as (

    select
        event_dt,
        event_at,
        user_pseudo_id,
        nullif(
            trim(
                regexp_replace(
                    lower(uid_norm),
                    r'[\p{Cc}\p{Zl}\p{Zp}]',
                    ''
                )
            ),
            ''
        ) as uid_norm,
        gender,
        major
    from {{ ref('silver__user_identity_events') }}

),

candidate_flags as (

    select
        identity_base.*,
        coalesce(
            regexp_contains(uid_norm, r'(?i)(_nil|_null)\s*$'),
            false
        ) as is_nil_like,
        coalesce(
            regexp_contains(uid_norm, r'(?i)^anonymous(?:_\d+)?$'),
            false
        ) as is_anon_flg,
        coalesce(
            regexp_contains(uid_norm, r'^\d{6}_\d+$'),
            false
        ) as is_student_like,
        coalesce(
            regexp_contains(uid_norm, r'(?i)^(null|nil|undefined)$'),
            false
        ) as is_null_literal,
        coalesce(
            regexp_contains(
                uid_norm,
                r'(?i)^(user|userid|user_id|guest|test|tester|admin|dev)$'
            ),
            false
        ) as is_placeholder_exact,
        coalesce(
            regexp_contains(
                uid_norm,
                r'(?i)^(test|guest|user(id)?)[_-]?\d*$'
            ),
            false
        ) as is_placeholder_pat
    from identity_base

),

candidates as (

    select
        event_dt,
        event_at,
        user_pseudo_id,
        uid_norm as user_id,
        gender,
        major,
        case
            when uid_norm is null then 2
            when is_anon_flg then 1
            else 0
        end as priority,
        is_anon_flg,
        cast(is_student_like as int64)
            + cast(gender is not null as int64)
            + cast(major is not null as int64) as completeness
    from candidate_flags
    where not is_nil_like
      and not is_null_literal
      and not is_placeholder_exact
      and not is_placeholder_pat
      and (is_anon_flg or is_student_like or uid_norm is null)

),

candidate_aggregated as (

    select
        user_pseudo_id,
        user_id,
        gender,
        major,
        priority,
        is_anon_flg,
        count(*) as support_count,
        max(event_at) as latest_seen_at,
        max(completeness) as completeness
    from candidates
    group by
        user_pseudo_id,
        user_id,
        gender,
        major,
        priority,
        is_anon_flg

),

canonical_primary as (

    select
        user_pseudo_id,
        user_id,
        gender,
        major
    from candidate_aggregated
    qualify row_number() over (
        partition by user_pseudo_id
        order by
            priority,
            completeness desc,
            support_count desc,
            latest_seen_at desc
    ) = 1

),

latest_attributes as (

    select
        user_pseudo_id,
        array_agg(gender ignore nulls order by event_at desc limit 1)
            [safe_offset(0)] as gender,
        array_agg(major ignore nulls order by event_at desc limit 1)
            [safe_offset(0)] as major
    from identity_base
    group by user_pseudo_id

),

all_pseudo_ids as (

    select distinct user_pseudo_id
    from identity_base

),

canonical_users as (

    select
        all_pseudo_ids.user_pseudo_id,
        canonical_primary.user_id,
        coalesce(
            canonical_primary.gender,
            latest_attributes.gender
        ) as gender,
        coalesce(
            canonical_primary.major,
            latest_attributes.major
        ) as major
    from all_pseudo_ids
    left join canonical_primary using (user_pseudo_id)
    left join latest_attributes using (user_pseudo_id)

),

ga4_users as (

    select
        user_pseudo_id,
        user_id,
        gender,
        major,
        safe_cast(regexp_extract(user_id, r'_(\d+)\s*$') as int64)
            as user_id_mysql
    from canonical_users

),

mysql_users as (

    select
        id,
        user_type,
        created_at as signup_completed_at,
        is_deleted
    from {{ source('app_db', 'koin_users') }}

)

select
    ga4_users.user_pseudo_id,
    ga4_users.user_id,
    ga4_users.gender,
    ga4_users.major,
    cast(
        regexp_extract(ga4_users.user_id, r'^(20\d{2})')
        as int64
    ) as entry_year,
    mysql_users.user_type,
    mysql_users.signup_completed_at,
    mysql_users.is_deleted,
    mysql_users.id is not null as is_mysql_mapped
from ga4_users
left join mysql_users
    on ga4_users.user_id_mysql = mysql_users.id
