{{ config(enabled=(var('silver_logging_validation_enabled', false) is sameas true), tags=['silver_logging_v1_fixture']) }}
{% if var('silver_logging_validation_enabled', false) is sameas true %}
-- Expected failure: strict classification must stop the candidate before publication.
{% set scopes=[{'platform':'WEB','event_name':'DA1','start_dt':'2026-10-01','end_dt':'2026-11-30','evidence':'SYNTHETIC ONLY'}] %}
with {{ silver_logging_v1_fixture_ctes() }},
bad as (select * from mock_events where event_id='unknown')
select * from ({{ silver_logging_v1_classify('bad',scopes) }})

{% endif %}
