{{ config(tags=['gold_44_20']) }}
with {{ gold_common_ctes() }},
event_ids as (select event_id,count(*) n from silver_events group by 1),
user_ids as (select user_pseudo_id,count(*) n from user_snapshot group by 1)
select 'event_id' as violation,count(*) as failures from event_ids
where event_id is null or n!=1 having failures>0
union all
select 'user_id',count(*) from user_ids where user_pseudo_id is null or n!=1 having count(*)>0
union all
select 'relationship',count(*) from silver_events e left join user_snapshot u using(user_pseudo_id)
where u.user_pseudo_id is null or u.first_seen_dt is null having count(*)>0
