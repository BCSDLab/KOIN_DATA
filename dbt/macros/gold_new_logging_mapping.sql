{# Verified documentation examples, NOT a complete six-funnel mapping and NOT
   a Silver repair. The owning Silver implementation must emit these semantics. #}
{% macro gold_new_logging_examples() %}
select 'shop__shop_list__shop_detail__entry__click' as event_label,
  'shop' as expected_service,'shop_view' as expected_stage,2 as expected_order
union all select 'cafeteria__cafeteria__share__kakao__click','cafeteria','share',3
union all select 'timetable__timetable__timetable_export__image_save__click','timetable','save',3
union all select 'account__sign_up_policy__sign_up__terms_agree__click','account','terms_agreement',2
union all select 'account__identity_verification__sign_up__code_verify_success__click','account','identity_verification',3
{% endmacro %}
