{# Silver owns service/Entry/Core and identity. Label tokens are diagnostics. #}
{% macro gold_settings(overrides={}) %}
  {% set p = {
    'build_id': 'compile_only', 'snapshot_at': '2000-01-01T00:00:00Z',
    'computed_at': '2000-01-01T00:00:00Z', 'logging_start_dt': '2000-01-01',
    'event_complete_start_dt': '2000-01-01', 'event_complete_dt': '2000-01-01',
    'metric_start_dt': '2000-01-01', 'metric_end_dt': '2000-01-01',
    'funnel_version': 'new_logging_v1_draft',
    'coverage_verified': false, 'signup_verified': false,
    'mapping_verified': false, 'session_verified': false,
    'main_visit_verified': false, 'funnel_support_verified': false,
    'main_visit_platforms': [],
    'session_inactivity_minutes': 0, 'late_arrival_hours': 0
  } %}
  {% do p.update(var('gold_build', {})) %}
  {% do p.update(overrides) %}
  {% for key, value in p.items() %}
    {% if value is string and "'" in value %}
      {{ exceptions.raise_compiler_error('Invalid quote in gold_build.' ~ key) }}
    {% endif %}
  {% endfor %}
  {{ return(p) }}
{% endmacro %}

{% macro gold_block_individual_publish() %}
  {% if execute and flags.WHICH in ['run', 'build'] %}
    {{ exceptions.raise_compiler_error('Gold 44/20 requires joint publication; independent dbt run/build is disabled. Compile and use the guarded Stage publisher.') }}
  {% endif %}
{% endmacro %}

{% macro gold_common_ctes(event_relation=none, user_relation=none, frozen=true, overrides={}) %}
{% set p = gold_settings(overrides) %}
{% set er = event_relation if event_relation is not none else ref('silver_events_v2') %}
{% set ur = user_relation if user_relation is not none else ref('silver__users') %}
gold_parameters as (
  select date('{{ p.event_complete_start_dt }}') as complete_start_dt,
    date('{{ p.event_complete_dt }}') as complete_dt,
    date('{{ p.metric_start_dt }}') as metric_start_dt,
    date('{{ p.metric_end_dt }}') as metric_end_dt,
    timestamp('{{ p.snapshot_at }}') as snapshot_at,
    timestamp('{{ p.computed_at }}') as computed_at,
    '{{ p.build_id }}' as build_id, '{{ p.funnel_version }}' as funnel_version,
    {{ 'true' if p.coverage_verified is sameas true else 'false' }} as coverage_verified,
    {{ 'true' if p.signup_verified is sameas true else 'false' }} as signup_verified,
    {{ 'true' if p.mapping_verified is sameas true else 'false' }} as mapping_verified,
    {{ 'true' if p.session_verified is sameas true else 'false' }} as session_verified,
    {{ 'true' if p.main_visit_verified is sameas true else 'false' }} as main_visit_verified,
    {{ 'true' if p.funnel_support_verified is sameas true else 'false' }} as funnel_support_verified,
    array<string>[{% for platform in p.main_visit_platforms %}'{{ platform }}'{% if not loop.last %},{% endif %}{% endfor %}] as main_visit_platforms,
    {{ p.session_inactivity_minutes | int }} as inactivity_minutes,
    {{ p.late_arrival_hours | int }} as late_arrival_hours
),
silver_events as (
  select event_id, event_dt, event_at, timestamp_micros(event_ts) as event_time,
    user_pseudo_id, ga_session_id, custom_session_id, platform, device_category, device_os,
    event_name, event_label, event_category, event_value,
    split(event_label, '__')[safe_offset(0)] as label_service,
    split(event_label, '__')[safe_offset(1)] as label_page,
    split(event_label, '__')[safe_offset(2)] as label_feature,
    service_name, funnel_stage, service_step_order,
    coalesce(is_entry_event, false) as is_entry_event,
    coalesce(is_core_action, false) as is_core_action,
    coalesce(engagement_time_msec, 0) as engagement_time_msec
  from {{ er }} {% if frozen %}for system_time as of timestamp('{{ p.snapshot_at }}'){% endif %}
  where user_pseudo_id is not null and event_dt >= date('{{ p.logging_start_dt }}')
),
user_snapshot as (
  select user_pseudo_id, user_id, gender, major, safe_cast(entry_year as int64) as entry_year,
    user_type, case when is_deleted = 1 then true when is_deleted = 0 then false end as is_deleted,
    is_mysql_mapped, date(first_seen_at) as first_seen_dt,
    date(signup_completed_at, 'Asia/Seoul') as first_signup_dt
  from {{ ur }} {% if frozen %}for system_time as of timestamp('{{ p.snapshot_at }}'){% endif %}
),
event_user_days as (
  select event_dt, user_pseudo_id, count(*) as event_cnt_day,
    countif(is_entry_event) as entry_event_cnt_day, countif(is_core_action) as core_action_cnt_day,
    count(distinct coalesce(custom_session_id, ga_session_id)) as session_cnt_day,
    sum(engagement_time_msec) as engagement_msec_day,
    {% for s in ['shop','bus','board','facility','timetable'] %}
    max(if(service_name = '{{ s }}' and is_entry_event, 1, 0)) as used_{{ s }}_flg,
    {% endfor %}
    {% for s in ['cafeteria','main','account'] %}
    max(if(service_name = '{{ s }}', 1, 0)) as used_{{ s }}_flg{% if not loop.last %},{% endif %}
    {% endfor %}
  from silver_events group by 1, 2
)
{% endmacro %}
