{#
  데이터셋 이름을 커스텀 스키마(+schema) 그대로 쓰게 만드는 매크로.
  기본 dbt는 `타겟dataset_커스텀` 으로 이어붙여 silver_silver 같은 이름이 나온다.
  이 매크로로 덮어써서 silver 폴더 → silver, gold 폴더 → gold 로 깔끔하게 나오게 한다.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
