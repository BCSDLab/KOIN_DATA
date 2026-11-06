{# Versioned support policy for the current new-logging contract.
   Unsupported is not zero conversion. Main observation is a separate gate. #}
{% macro gold_funnel_support() %}
select *,if(funnel_id='cafeteria' and platform='IOS',
 'more_callback_sessions_require_path_evidence','') as route_note
from unnest(array<struct<funnel_id string,platform string,supported bool,reason string>>[
{% for f in ['signup','shop','bus','cafeteria','timetable','board'] %}
{% for p in ['WEB','ANDROID','IOS'] %}
{% set reason = 'signup_steps_4_5_unverified' if f=='signup' else
  ('share_not_supported_on_web' if f=='cafeteria' and p=='WEB' else
  ('explore_not_mapped_on_app' if f=='timetable' and p!='WEB' else
  ('explore_not_mapped_on_web' if f=='board' and p=='WEB' else 'supported'))) %}
struct('{{ f }}','{{ p }}',{{ 'true' if reason=='supported' else 'false' }},'{{ reason }}'),
{% endfor %}{% endfor %}
struct(cast(null as string),null,false,'sentinel')
]) where funnel_id is not null
{% endmacro %}
