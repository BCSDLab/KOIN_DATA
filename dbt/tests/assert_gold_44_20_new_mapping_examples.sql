{{ config(enabled=(var('gold_validation_enabled', false) is sameas true), tags=['gold_44_20']) }}
with {{ gold_common_ctes() }}, examples as ({{ gold_new_logging_examples() }})
select e.event_id,e.event_label,e.service_name,e.funnel_stage,e.service_step_order
from silver_events e join examples x using(event_label)
where e.service_name is distinct from x.expected_service
  or e.funnel_stage is distinct from x.expected_stage
  or e.service_step_order is distinct from x.expected_order
