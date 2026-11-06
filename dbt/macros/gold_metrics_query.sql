{% macro gold_metrics_query(event_relation=none, user_relation=none, frozen=true, overrides={}) %}
with {{ gold_common_ctes(event_relation,user_relation,frozen,overrides) }},
service_days as (
  select d.user_pseudo_id,d.event_dt,s as service_name
  from event_user_days d cross join unnest([
    if(used_shop_flg=1,'shop',null),if(used_cafeteria_flg=1,'cafeteria',null),
    if(used_bus_flg=1,'bus',null),if(used_board_flg=1,'board',null),
    if(used_facility_flg=1,'facility',null),if(used_timetable_flg=1,'timetable',null),
    if(used_main_flg=1,'main',null),if(used_account_flg=1,'account',null),'__all__'
  ]) s where s is not null
),
cohort_returns as (
  select a.user_pseudo_id,a.event_dt,a.service_name,
    array_agg(distinct date_diff(r.event_dt,a.event_dt,day) ignore nulls) as return_days
  from service_days a left join service_days r on a.user_pseudo_id=r.user_pseudo_id
    and a.service_name=r.service_name and r.event_dt between a.event_dt and date_add(a.event_dt,interval 56 day)
  cross join gold_parameters p where a.event_dt between p.metric_start_dt and p.metric_end_dt
  group by 1,2,3
),
retention_windows as (
  select 'retention_daily' as metric_type,n as period_n,n as start_day,n as end_day
  from unnest(generate_array(0,56)) n
  union all
  select 'retention_weekly',n,if(n=0,0,7*n-6),7*n from unnest(generate_array(0,8)) n
),
retention_users as (
  select w.metric_type,a.event_dt as metric_dt,a.service_name,w.period_n,
    date_add(a.event_dt,interval w.start_day day) as window_start_dt,
    date_add(a.event_dt,interval w.end_day day) as window_end_dt,
    u.gender,u.major,u.entry_year,u.user_type,
    if(u.first_seen_dt=a.event_dt,'new','existing') as cohort_user_segment,
    p.coverage_verified and a.event_dt>=p.complete_start_dt
      and date_add(a.event_dt,interval w.end_day day)<=p.complete_dt as is_complete,
    exists(select 1 from unnest(a.return_days) n where n between w.start_day and w.end_day) as success
  from cohort_returns a join user_snapshot u using(user_pseudo_id)
  cross join retention_windows w cross join gold_parameters p
),
range_users as (
  select 'first_seen_range_entry_d1_d7' as metric_type,u.first_seen_dt as metric_dt,
    '__all__' as service_name,7 as period_n,
    date_add(u.first_seen_dt,interval 1 day) as window_start_dt,
    date_add(u.first_seen_dt,interval 7 day) as window_end_dt,
    u.gender,u.major,u.entry_year,u.user_type,'new' as cohort_user_segment,
    p.coverage_verified and u.first_seen_dt>=p.complete_start_dt
      and date_add(u.first_seen_dt,interval 7 day)<=p.complete_dt as is_complete,
    exists(select 1 from event_user_days r where r.user_pseudo_id=u.user_pseudo_id
      and r.event_dt between date_add(u.first_seen_dt,interval 1 day)
        and date_add(u.first_seen_dt,interval 7 day) and r.entry_event_cnt_day>0) as success
  from user_snapshot u cross join gold_parameters p
  where u.first_seen_dt between p.metric_start_dt and p.metric_end_dt
),
week_users as (
  select distinct user_pseudo_id,date_trunc(event_dt,week(monday)) as week_start
  from event_user_days
),
nonreturn_users as (
  select 'app_weekly_nonreturn' as metric_type,w.week_start as metric_dt,
    '__all__' as service_name,1 as period_n,
    date_add(w.week_start,interval 7 day) as window_start_dt,
    date_add(w.week_start,interval 13 day) as window_end_dt,
    u.gender,u.major,u.entry_year,u.user_type,'not_applicable' as cohort_user_segment,
    p.coverage_verified and w.week_start>=p.complete_start_dt
      and date_add(w.week_start,interval 13 day)<=p.complete_dt as is_complete,
    n.user_pseudo_id is null as success
  from week_users w join user_snapshot u using(user_pseudo_id)
  left join week_users n on w.user_pseudo_id=n.user_pseudo_id
    and n.week_start=date_add(w.week_start,interval 7 day)
  cross join gold_parameters p where w.week_start between p.metric_start_dt and p.metric_end_dt
),
activity_intervals as (
  select *,lead(event_dt) over(partition by user_pseudo_id,service_name order by event_dt) as next_dt
  from service_days where service_name in ('shop','bus','cafeteria','board','facility','timetable')
),
churn_users as (
  select 'churn_56d' as metric_type,t as metric_dt,a.service_name,56 as period_n,
    date_sub(t,interval 55 day) as window_start_dt,t as window_end_dt,
    u.gender,u.major,u.entry_year,u.user_type,'not_applicable' as cohort_user_segment,
    p.coverage_verified and date_sub(t,interval 55 day)>=p.complete_start_dt
      and t<=p.complete_dt as is_complete,
    date_diff(t,a.event_dt,day)>=56 as success
  from activity_intervals a join user_snapshot u using(user_pseudo_id)
  cross join gold_parameters p cross join unnest(generate_date_array(
    greatest(a.event_dt,p.metric_start_dt),
    least(coalesce(date_sub(a.next_dt,interval 1 day),p.metric_end_dt),p.metric_end_dt)
  )) t
),
evaluation_users as (
  select * from retention_users union all select * from range_users
  union all select * from nonreturn_users union all select * from churn_users
),
aggregated as (
  select metric_type,metric_dt,service_name,period_n,window_start_dt,window_end_dt,
    gender,major,entry_year,user_type,cohort_user_segment,
    count(*) as denominator_users,if(is_complete,countif(success),null) as numerator_users,is_complete
  from evaluation_users group by 1,2,3,4,5,6,7,8,9,10,11,is_complete
)
select to_hex(sha256(to_json_string(struct(
    a.metric_type,a.metric_dt,a.service_name,a.period_n,a.gender,a.major,
    a.entry_year,a.user_type,a.cohort_user_segment)))) as metric_row_id,
  a.metric_type,a.metric_dt,a.service_name,a.period_n,a.window_start_dt,a.window_end_dt,
  a.gender,a.major,a.entry_year,a.user_type,a.cohort_user_segment,
  a.denominator_users,a.numerator_users,a.is_complete,
  p.complete_start_dt as event_complete_start_dt,p.complete_dt as event_complete_dt,
  p.snapshot_at as user_snapshot_at,p.build_id,p.computed_at
from aggregated a cross join gold_parameters p
{% endmacro %}
