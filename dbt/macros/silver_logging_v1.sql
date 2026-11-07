{# Notion specification mappings, not deployment evidence. Output schema is unchanged.
   All rule tuples: label, owner, category, service, stage, platforms, source page.
   No date is inferred from the Notion edit date. #}
{% macro silver_logging_v1_rules() %}
{% set rules = [
 ('main__main__shop_entry__main_entry__click','DA1','click','shop','entry',['ANDROID','IOS'],'0320221954bc838ba30c816a7787861c'),
 ('shop__main__shop_entry__popular_entry__click','DA2','click','shop','entry',['WEB','ANDROID','IOS'],'aa90221954bc83daafec817ac462f0eb'),
 ('shop__header__shop_entry__header_entry__click','DA1','click','shop','entry',['WEB'],'b180221954bc82f58adf016dde49a068'),
 ('shop__shop_list__shop_detail__entry__click','DA1','click','shop','shop_view',['WEB','ANDROID','IOS'],'8f00221954bc83d0afe881e3ddd2deed'),
 ('shop__shop_detail__contact__phone__click','DA1','click','shop','call',['WEB','ANDROID','IOS'],'2d50221954bc834f8ca9019292dd4741'),
 ('main__main__bus_entry__search_entry__click','DA1','click','bus','entry',['WEB','ANDROID','IOS'],'1c50221954bc821f86e20145c98947fa'),
 ('bus__bus_search__search__departure_confirm__select','DA1','select','bus','set_od',['WEB','ANDROID','IOS'],'e280221954bc8274ad3081acbafe9908'),
 ('bus__bus_search__search__arrival_confirm__select','DA1','select','bus','set_od',['WEB','ANDROID','IOS'],'a790221954bc82b28dee015081c4dfce'),
 ('bus__bus_search__search__click','DA1','click','bus','search',['WEB','ANDROID','IOS'],'7f30221954bc82979db281b71f9b253f'),
 ('main__main__more__click','DA1','click','cafeteria','entry',['WEB','ANDROID'],'4730221954bc829a90e7818e5ed78bd7'),
 ('cafeteria__main__meal__click','DA1','click','cafeteria','entry',['WEB','ANDROID','IOS'],'d400221954bc8338b341011b9a488dac'),
 ('cafeteria__header__cafeteria_entry__header_entry__click','DA1','click','cafeteria','entry',['WEB'],'c420221954bc831497240194ccc6ae54'),
 ('cafeteria__cafeteria__meal_time__select','DA1','select','cafeteria','explore',['WEB','ANDROID','IOS'],'e5f0221954bc821c881e01997734ea21'),
 ('cafeteria__cafeteria__share__kakao__click','DA1','click','cafeteria','share',['ANDROID','IOS'],'6650221954bc8290b31301687986010e'),
 ('timetable__header__timetable_entry__header_entry__click','DA1','click','timetable','entry',['WEB'],'6c90221954bc83d88f4a81ea4fe3e87a'),
 ('timetable__main_category__timetable_entry__category_entry__click','DA1','click','timetable','entry',['ANDROID','IOS'],'e9d0221954bc828aa337812594729789'),
 ('timetable__main_profile__timetable_entry__entry__click','DA2','click','timetable','entry',['WEB','ANDROID','IOS'],'8420221954bc82b587bc81059510b0ca'),
 ('timetable__timetable_edit__search__click','DA1','click','timetable','explore',['WEB'],'a0f0221954bc82868e5b013fc104b70c'),
 ('timetable__timetable__search__curriculum__select','DA1','select','timetable','explore',['WEB'],'bae0221954bc83be93e001fe5751accd'),
 ('timetable__timetable__semester_manage__select','DA1','select','timetable','explore',['WEB'],'8550221954bc82d88ad9017112a13e74'),
 ('timetable__timetable__timetable_export__image_save__click','DA1','click','timetable','save',['WEB','ANDROID','IOS'],'27e0221954bc821da617812bbc62ce44'),
 ('board__main__notice_entry__title_entry__click','DA2','click','board','entry',['WEB'],'aa70221954bc8350b61801d87fe1eb46'),
 ('main__main__notice_entry__navigation_entry__click','DA2','click','board','entry',['ANDROID','IOS'],'ac20221954bc839c82b481e92e072a58'),
 ('board__main_notice__search__entry__click','DA2','click','board','explore',['ANDROID','IOS'],'b6e0221954bc8309be9e811da1679706'),
 ('board__notice_search__search__submit','DA2','submit','board','explore',['ANDROID','IOS'],'af00221954bc832b866501b4e470f143'),
 ('board__main_notice__notice_detail__entry__click','DA2','click','board','read',['WEB','ANDROID','IOS'],'db60221954bc82a7981281691197c64e'),
 ('board__main_notice__notice_detail__popular_post_entry__click','DA2','click','board','read',['WEB'],'76a0221954bc839ab58e01d56b51c40f'),
 ('account__header__sign_up__header_entry__click','DA2','click','account','signup_start',['WEB'],'3630221954bc82c98974813502966a87'),
 ('account__main_category__sign_up__menu_entry__click','DA2','click','account','signup_start',['WEB','ANDROID','IOS'],'0820221954bc834eb41301752196a7d5'),
 ('account__login__sign_up__entry__click','DA2','click','account','signup_start',['WEB','ANDROID','IOS'],'a1e0221954bc82ebbe390176073d8e18'),
 ('account__sign_up_policy__sign_up__terms_agree__click','DA2','click','account','terms_agreement',['WEB','ANDROID','IOS'],'7910221954bc822fbaf881a78dc1919d'),
 ('account__identity_verification__sign_up__code_verify_success__click','DA2','click','account','identity_verification',['WEB','ANDROID','IOS'],'9dd0221954bc83328f3101973bcaff2b'),
 ('account__user_type_selection__sign_up__user_type__click','DA2','click','account',none,['ANDROID','IOS'],'9bd0221954bc833c845a818f39ef8ca0'),
 ('account__user_type_selection__sign_up__user_type__click','DA2','click','account',none,['WEB'],'6400221954bc829089cb01755624814f'),
 ('account__input_user_info__sign_up__confirm__click','DA2','click','account',none,['WEB','ANDROID','IOS'],'4830221954bc8355887e01f988251647'),
 ('main__main__more__click','DA1','click','cafeteria',none,['IOS'],'4730221954bc829a90e7818e5ed78bd7','ios_more_unverified'),
 ('timetable__main_category__timetable_entry__category_entry__click','DA1','click','timetable','entry',['WEB'],'e9d0221954bc828aa337812594729789','mobile_web_category'),
 ('account__main_profile__login__entry__click','DA2','click','account',none,['ANDROID','IOS'],'2660221954bc82719b1b01589fd83c1b'),
 ('account__main_profile__logout__click','DA2','click','account',none,['ANDROID','IOS'],'6d90221954bc83a8839d01823f621620'),
 ('account__password_change__password_change__confirm__click','DA2','click','account',none,['ANDROID','IOS'],'1250221954bc82a5bdb38115ed63b652'),
 ('account__password_change__password_change__confirm__click','DA2','click','account',none,['WEB'],'1150221954bc8217aaee812619b3653f')
] %}
{{ return(rules) }}
{% endmacro %}

{% macro silver_logging_v1_frozen_labels() %}
{# Preserve the existing results, not a new interpretation of frozen events. #}
{{ return(['cafeteria__cafeteria__soldout_submit',
 'cafeteria__dining__abtest__exposure','cafeteria__dining__soldout__start',
 'cafeteria__dining__soldout__select','cafeteria__dining__soldout__photo',
 'cafeteria__dining__soldout__submit','cafeteria__dining__soldout__exit']) }}
{% endmacro %}

{% macro silver_logging_v1_classify(relation,scopes=none,legacy_labels=none,diagnostic_only=false) %}
{% if target.name != 'dev' or target.database != 'koin-stage-438512' %}
  {{ exceptions.raise_compiler_error('Silver logging v1 draft is Stage-only') }}
{% endif %}
{% set scopes = scopes if scopes is not none else var('silver_logging_v1_scopes', []) %}
{% if not scopes %}
  {{ exceptions.raise_compiler_error('Explicit silver_logging_v1_scopes with evidence required') }}
{% endif %}
{% for s in scopes %}
  {% if s.platform not in ['WEB','ANDROID','IOS'] or s.event_name not in ['DA1','DA2']
     or not s.get('evidence','') %}
    {{ exceptions.raise_compiler_error('Invalid Silver naming scope or missing evidence') }}
  {% endif %}
  {% set start = modules.datetime.datetime.strptime(s.start_dt,'%Y-%m-%d').date() %}
  {% set end = modules.datetime.datetime.strptime(s.end_dt,'%Y-%m-%d').date() %}
  {% if start > end %}{{ exceptions.raise_compiler_error('Invalid Silver scope interval') }}{% endif %}
{% endfor %}
{% set legacy_labels = legacy_labels if legacy_labels is not none else var('silver_logging_v1_legacy_labels', []) %}
{% for r in legacy_labels %}
  {% if r.platform not in ['WEB','ANDROID','IOS'] or r.event_name not in ['DA1','DA2']
     or not r.get('evidence','') or not r.get('source_url','').startswith('https://')
     or not modules.re.fullmatch('[A-Za-z0-9_]+',r.event_label)
     or not modules.re.fullmatch('[A-Za-z0-9_]+',r.event_category) %}
    {{ exceptions.raise_compiler_error('Exact legacy contract and evidence required; no patterns') }}
  {% endif %}
  {% set start = modules.datetime.datetime.strptime(r.start_dt,'%Y-%m-%d').date() %}
  {% set end = modules.datetime.datetime.strptime(r.end_dt,'%Y-%m-%d').date() %}
  {% if start>end %}{{ exceptions.raise_compiler_error('Invalid legacy interval') }}{% endif %}
{% endfor %}
{% if diagnostic_only and var('silver_logging_validation_enabled',false) is not sameas true %}
 {{ exceptions.raise_compiler_error('Diagnostic mode requires explicit synthetic validation') }}
{% endif %}
with rule_contracts as (
  select r.* except(platforms),platform
  from unnest(array<struct<event_label string,event_name string,event_category string,
    service_name string,funnel_stage string,platforms array<string>,route_policy string>>[
  {% for r in silver_logging_v1_rules() %}
    struct('{{ r[0] }}','{{ r[1] }}','{{ r[2] }}','{{ r[3] }}',
      {{ "'"~r[4]~"'" if r[4] is not none else 'cast(null as string)' }},
      [{% for p in r[5] %}'{{ p }}'{% if not loop.last %},{% endif %}{% endfor %}],
      '{{ r[7] if r|length>7 else 'any' }}'){% if not loop.last %},{% endif %}
  {% endfor %}
  ]) r cross join unnest(r.platforms) platform
),
service_rules as (
 select distinct event_label,event_name,event_category,platform,service_name,route_policy,
   coalesce(funnel_stage='entry',false) as entry_flag
 from rule_contracts
 union all
 select r.event_label,r.event_name,r.event_category,r.platform,r.service_name,'any',r.entry_flag
 from unnest(array<struct<event_label string,event_name string,event_category string,
   service_name string,platform string,entry_flag bool,source_page string>>[
 {% for r in silver_logging_v1_service_catalog() %}
 struct('{{ r[0] }}','{{ r[1] }}','{{ r[2] }}','{{ r[3] }}','{{ r[4] }}',
   {{ 'true' if r[5] else 'false' }},'{{ r[6] }}'){% if not loop.last %},{% endif %}
 {% endfor %}
 ]) r
),
funnel_rules as (
 select event_label,event_name,event_category,platform,funnel_stage,route_policy
 from rule_contracts where funnel_stage is not null
),
scopes as (
 {% for s in scopes %}
 select '{{ s.platform }}' as platform,'{{ s.event_name }}' as event_name,
   date('{{ s.start_dt }}') as start_dt,date('{{ s.end_dt }}') as end_dt
 {% if not loop.last %}union all{% endif %}
 {% endfor %}
),
legacy_labels as (
 select * from unnest(array<struct<platform string,event_name string,event_label string,
   event_category string,start_dt date,end_dt date>>[
 {% for r in legacy_labels %}
 struct('{{ r.platform }}','{{ r.event_name }}','{{ r.event_label }}','{{ r.event_category }}',
   date('{{ r.start_dt }}'),date('{{ r.end_dt }}')){% if not loop.last %},{% endif %}
 {% endfor %}
 ])
),
eligible as (
 select e.*,exists(select 1 from scopes s where s.platform=e.platform and s.event_name=e.event_name
   and e.event_dt between s.start_dt and s.end_dt)
   and split(lower(coalesce(e.event_label,'')),'__')[safe_offset(0)]
     in ('main','account','shop','bus','cafeteria','timetable','board',
         'banner','callvan','chat','course_practice','department','facility','owner','real_estate')
   and strpos(coalesce(e.event_label,''),'__')>0
   and e.event_label not in ({% for label in silver_logging_v1_frozen_labels() %}'{{ label }}'{% if not loop.last %},{% endif %}{% endfor %})
   and not exists(select 1 from legacy_labels l where l.platform=e.platform and l.event_name=e.event_name
     and l.event_label=e.event_label and l.event_category=e.event_category
     and e.event_dt between l.start_dt and l.end_dt)
   as apply_v1
 from {{ relation }} e
),
mapped as (
 select e.* replace(
   case when not e.apply_v1 then e.service_name
     when sr.service_name is not null then sr.service_name
     {% if diagnostic_only %}else 'unmapped'
     {% else %}else error('Silver v1 service contract missing; publication blocked')
     {% endif %}end as service_name,
   case when not e.apply_v1 then e.funnel_stage
     when sr.route_policy='mobile_web_category' and not coalesce(
       regexp_contains(e.page_location,r'^https?://[^/]+/category(?:[/?#]|$)'),false)
       {% if diagnostic_only %}then cast(null as string)
       {% else %}then error('Silver v1 route contract missing; publication blocked'){% endif %}
     else fr.funnel_stage end as funnel_stage),sr.entry_flag as new_entry_flag
 from eligible e
 left join service_rules sr on e.apply_v1 and e.event_label=sr.event_label
   and e.event_name=sr.event_name and e.event_category=sr.event_category and e.platform=sr.platform
 left join funnel_rules fr on e.apply_v1 and e.event_label=fr.event_label
   and e.event_name=fr.event_name and e.event_category=fr.event_category and e.platform=fr.platform
   and (fr.route_policy!='mobile_web_category' or
     regexp_contains(e.page_location,r'^https?://[^/]+/category(?:[/?#]|$)'))
),
ordered as (
 select m.* replace(case when m.apply_v1 then case
   when m.funnel_stage in ('entry','signup_start') then 1
   when m.funnel_stage in ('shop_view','set_od','explore','terms_agreement') then 2
   when m.funnel_stage in ('call','search','share','save','read','identity_verification') then 3
   end else m.step_order end as step_order)
 from mapped m
)
select o.* except(apply_v1,new_entry_flag) replace(
 if(o.apply_v1,coalesce(o.new_entry_flag,false),o.is_entry_event) as is_entry_event,
 if(o.apply_v1,coalesce(o.funnel_stage in ('call','search','share','save','read'),false),o.is_core_action) as is_core_action,
 if(o.apply_v1,'service',o.stage_scope) as stage_scope,
 if(o.apply_v1,o.step_order,o.service_step_order) as service_step_order)
from ordered o
{% endmacro %}
