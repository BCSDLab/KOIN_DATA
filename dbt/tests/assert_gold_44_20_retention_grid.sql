{{ config(tags=['gold_44_20']) }}
select metric_type,metric_dt,service_name,gender,major,entry_year,user_type,cohort_user_segment
from {{ ref('mart_service_metrics_daily') }}
where metric_type in ('retention_daily','retention_weekly')
group by 1,2,3,4,5,6,7,8
having min(denominator_users)!=max(denominator_users)
  or count(*)!=if(metric_type='retention_daily',57,9)
  or count(distinct period_n)!=if(metric_type='retention_daily',57,9)
  or min(period_n)!=0 or max(period_n)!=if(metric_type='retention_daily',56,8)
