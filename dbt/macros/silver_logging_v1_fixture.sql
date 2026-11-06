{% macro silver_logging_v1_fixture_ctes() %}
{{ gold_fixture_ctes() }},
raw_cases as (
 select * from unnest(array<struct<case_id string,user_key string,case_platform string,label string,
   owner string,category string,expected_service string,expected_stage string,expected_order int64,
   test_group string,day_n int64,minute_n int64,legacy_service string,legacy_stage string,legacy_order int64>>[
  struct('shop_main','u1','WEB','legacy_main','page_view','view','main','main',0,'path',0,0,'main','main',0),
  struct('bus_main','u2','WEB','legacy_main','page_view','view','main','main',0,'path',0,0,'main','main',0),
  struct('cafeteria_main','u4','IOS','legacy_main','page_view','view','main','main',0,'path',0,0,'main','main',0),
  struct('timetable_main','u5','WEB','legacy_main','page_view','view','main','main',0,'path',0,0,'main','main',0),
  struct('board_main','u6','IOS','legacy_main','page_view','view','main','main',0,'path',0,0,'main','main',0),
  struct('shop_entry','u1','WEB','shop__main__shop_entry__popular_entry__click','DA2','click','shop','entry',1,'path',0,1,'main','main',0),
  struct('shop_detail','u1','WEB','shop__shop_list__shop_detail__entry__click','DA1','click','shop','shop_view',2,'path',0,2,'main','main',0),
  struct('shop_call','u1','WEB','shop__shop_detail__contact__phone__click','DA1','click','shop','call',3,'path',0,3,'main','main',0),
  struct('bus_entry','u2','WEB','main__main__bus_entry__search_entry__click','DA1','click','bus','entry',1,'path',0,1,'main','main',0),
  struct('bus_od','u2','WEB','bus__bus_search__search__departure_confirm__select','DA1','select','bus','set_od',2,'path',0,2,'main','main',0),
  struct('bus_search','u2','WEB','bus__bus_search__search__click','DA1','click','bus','search',3,'path',0,3,'main','main',0),
  struct('caf_entry','u4','IOS','cafeteria__main__meal__click','DA1','click','cafeteria','entry',1,'path',0,1,'main','main',0),
  struct('caf_time','u4','IOS','cafeteria__cafeteria__meal_time__select','DA1','select','cafeteria','explore',2,'path',0,2,'main','main',0),
  struct('caf_share','u4','IOS','cafeteria__cafeteria__share__kakao__click','DA1','click','cafeteria','share',3,'path',0,3,'main','main',0),
  struct('time_entry','u5','WEB','timetable__header__timetable_entry__header_entry__click','DA1','click','timetable','entry',1,'path',0,1,'main','main',0),
  struct('time_explore','u5','WEB','timetable__timetable__search__curriculum__select','DA1','select','timetable','explore',2,'path',0,2,'main','main',0),
  struct('time_save','u5','WEB','timetable__timetable__timetable_export__image_save__click','DA1','click','timetable','save',3,'path',0,3,'main','main',0),
  struct('board_entry','u6','IOS','main__main__notice_entry__navigation_entry__click','DA2','click','board','entry',1,'path',0,1,'main','main',0),
  struct('board_search','u6','IOS','board__notice_search__search__submit','DA2','submit','board','explore',2,'path',0,2,'main','main',0),
  struct('board_read','u6','IOS','board__main_notice__notice_detail__entry__click','DA2','click','board','read',3,'path',0,3,'main','main',0),
  struct('signup_start','u7','WEB','account__login__sign_up__entry__click','DA2','click','account','signup_start',1,'path',0,1,'main','main',0),
  struct('signup_terms','u7','WEB','account__sign_up_policy__sign_up__terms_agree__click','DA2','click','account','terms_agreement',2,'path',0,2,'main','main',0),
  struct('signup_auth','u7','WEB','account__identity_verification__sign_up__code_verify_success__click','DA2','click','account','identity_verification',3,'path',0,3,'main','main',0),
  struct('signup_type','u7','WEB','account__user_type_selection__sign_up__user_type__click','DA2','click','account',null,null,'path',0,4,'main','main',0),
  struct('signup_confirm','u7','WEB','account__input_user_info__sign_up__confirm__click','DA2','click','account',null,null,'path',0,5,'main','main',0),
  struct('u2_d1_entry','u2','WEB','main__main__bus_entry__search_entry__click','DA1','click','bus','entry',1,'path',1,1,'main','main',0),
  struct('u7_d1_entry','u7','WEB','main__main__bus_entry__search_entry__click','DA1','click','bus','entry',1,'path',1,1,'main','main',0),
  struct('unknown','u1','WEB','bus__bus_search__unknown__click','DA1','click','unmapped',null,null,'edge',0,1,'main','main',0),
  struct('wrong_category','u1','WEB','bus__bus_search__search__click','DA1','submit','unmapped',null,null,'edge',0,1,'main','main',0),
  struct('wrong_owner','u1','WEB','bus__bus_search__search__click','DA2','click','unmapped',null,null,'edge',0,1,'main','main',0),
  struct('wrong_platform','u1','WEB','cafeteria__cafeteria__share__kakao__click','DA1','click','unmapped',null,null,'edge',0,1,'main','main',0),
  struct('wrong_case','u1','WEB','BUS__bus_search__search__click','DA1','click','unmapped',null,null,'edge',0,1,'main','main',0),
  struct('logical_main','u1','WEB','main__main__navigation__main_entry__click','DA2','click','unmapped',null,null,'edge',0,1,'main','main',0),
  struct('frozen_typo','u1','WEB','cafeteria__dining__soldout__submit_typo','DA1','click','unmapped',null,null,'edge',0,1,'main','main',0),
  struct('outside_scope','u1','WEB','bus__bus_search__search__click','DA1','click','main','main',0,'edge',-1,0,'main','main',0),
  struct('legacy','u1','WEB','shop_call','DA1','click','shop','call',3,'edge',0,0,'shop','call',3),
  struct('frozen_0','u1','IOS','cafeteria__cafeteria__soldout_submit','DA1','fail','unmapped',null,null,'edge',0,0,'unmapped',null,null),
  struct('frozen_1','u1','IOS','cafeteria__dining__abtest__exposure','DA1','fail','unmapped',null,null,'edge',0,0,'unmapped',null,null),
  struct('frozen_2','u1','IOS','cafeteria__dining__soldout__start','DA1','fail','unmapped',null,null,'edge',0,0,'unmapped',null,null),
  struct('frozen_3','u1','IOS','cafeteria__dining__soldout__select','DA1','fail','unmapped',null,null,'edge',0,0,'unmapped',null,null),
  struct('frozen_4','u1','IOS','cafeteria__dining__soldout__photo','DA1','fail','unmapped',null,null,'edge',0,0,'unmapped',null,null),
  struct('frozen_5','u1','IOS','cafeteria__dining__soldout__submit','DA1','fail','unmapped',null,null,'edge',0,0,'unmapped',null,null),
  struct('frozen_6','u1','IOS','cafeteria__dining__soldout__exit','DA1','fail','unmapped',null,null,'edge',0,0,'unmapped',null,null)
 ,struct('approved_old','u1','WEB','bus__old__legacy__click','DA1','click','main','main',0,'edge',0,1,'main','main',0)
 ])
),
raw_mock_events as (
 select e.* replace(
   c.case_id as event_id,c.user_key as user_pseudo_id,c.case_platform as platform,
   date_add(date '2026-10-01',interval c.day_n day) as event_dt,
   datetime(timestamp_add(timestamp_add(timestamp('2026-10-01 10:00:00','Asia/Seoul'),interval c.day_n day),interval c.minute_n minute),'Asia/Seoul') as event_at,
   unix_micros(timestamp_add(timestamp_add(timestamp('2026-10-01 10:00:00','Asia/Seoul'),interval c.day_n day),interval c.minute_n minute)) as event_ts,
   c.label as event_label,c.owner as event_name,c.category as event_category,
   concat(c.user_key,'_',cast(c.day_n as string)) as custom_session_id,
   '1' as ga_session_id,
   c.legacy_service as service_name,c.legacy_stage as funnel_stage,
   c.legacy_order as service_step_order,coalesce(c.legacy_stage='entry',false) as is_entry_event,
   coalesce(c.legacy_stage='call',false) as is_core_action),
   c.legacy_order as step_order,if(c.legacy_service='main','global','service') as stage_scope,
   c.test_group,c.expected_service,c.expected_stage,c.expected_order
 from fixture_events e cross join raw_cases c where e.event_id='e1'
),
mock_events as (
 select e.* replace(cast(case e.user_pseudo_id when 'u1' then 100 when 'u2' then 200
    when 'u4' then 400 when 'u5' then 500 when 'u6' then 600 when 'u7' then 700 end
    +date_diff(e.event_dt,date '2026-10-01',day) as string) as ga_session_id)
 from raw_mock_events e
)
{% endmacro %}

{% macro silver_logging_v1_fixture_legacy() %}
{{ return([{'platform':'WEB','event_name':'DA1','event_label':'bus__old__legacy__click',
 'event_category':'click','start_dt':'2026-10-01','end_dt':'2026-11-30',
 'evidence':'SYNTHETIC ONLY; not an actual approved label','source_url':'https://example.com/synthetic-only'}]) }}
{% endmacro %}
