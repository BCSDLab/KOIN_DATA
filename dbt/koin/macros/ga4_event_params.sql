{% macro ga4_event_param_string(param_name) -%}
  (
    select value.string_value
    from unnest(event_params)
    where key = '{{ param_name }}'
    limit 1
  )
{%- endmacro %}

{% macro ga4_event_param_int(param_name) -%}
  (
    select value.int_value
    from unnest(event_params)
    where key = '{{ param_name }}'
    limit 1
  )
{%- endmacro %}
