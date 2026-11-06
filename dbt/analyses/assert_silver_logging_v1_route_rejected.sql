{{ config(enabled=(var('silver_logging_validation_enabled', false) is sameas true), tags=['silver_logging_v1_fixture']) }}
{% if var('silver_logging_validation_enabled', false) is sameas true %}
-- Expected failure: WEB category label alone cannot certify the mobile /category route.
{% set scopes=[{'platform':'WEB','event_name':'DA1','start_dt':'2026-10-01','end_dt':'2026-11-30','evidence':'SYNTHETIC ONLY'}] %}
with {{ silver_logging_v1_fixture_ctes() }},
bad as (select * replace('timetable__main_category__timetable_entry__category_entry__click' as event_label,
  'https://stage.koreatech.in/' as page_location) from mock_events where event_id='unknown')
select * from ({{ silver_logging_v1_classify('bad',scopes) }})

{% endif %}
