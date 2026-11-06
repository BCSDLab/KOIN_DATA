{{ config(tags=['gold_44_20']) }}
{% set p = gold_settings() %}
select s.*,({{ 'true' if p.main_visit_verified is sameas true else 'false' }} and s.platform in
 array<string>[{% for platform in p.main_visit_platforms %}'{{ platform }}'{% if not loop.last %},{% endif %}{% endfor %}]) as main_visit_verified,
 {{ 'true' if p.funnel_support_verified is sameas true else 'false' }} as funnel_support_verified,
 '{{ p.funnel_version }}' as funnel_version
from ({{ gold_funnel_support() }}) s
