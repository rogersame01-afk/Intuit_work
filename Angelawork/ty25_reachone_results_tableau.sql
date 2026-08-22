drop table if exists cgan_ustax_ws.aw_ty25_reachone;
create table cgan_ustax_ws.aw_ty25_reachone as

with base as (
--Test
  select distinct 
    external_user_id as pseudonym_id
  , date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) as dt
  , canvas_name
  , canvas_id
  , canvas_step_name
  , 'test' as test_group
  from tax_src.src_braze_turbotax_email_delivery as em
  where date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) >= '2026-03-12' --Change this to reflect the start date of the campaign
    and em.canvas_step_name like 'em_803_NULL_00%'

  union

  --holdout
  select distinct 
    external_user_id as pseudonym_id
  , date(from_utc_timestamp(cast(time as timestamp), 'America/Los_Angeles')) as dt
  , canvas_name
  , canvas_id
  , canvas_step_name
  , 'holdout' as test_group
  from tax_src.src_braze_turbotax_webhook_send
  where date(from_utc_timestamp(cast(time as timestamp), 'America/Los_Angeles')) >= '2026-03-12' --Change this to reflect the start date of the campaign
    and canvas_step_name like 'em_803_NULL_00%'  
),

logins as (
    select msam.auth_id
        , msam.auth_type
        , msam.server_timestamp as session_start_datetime
        , pam.pseudonym_id
    from tax_rpt.marketing_session_analytics_master as msam
    inner join tax_rpt.product_analytics_master pam
        on msam.auth_id = pam.auth_id
            and pam.tax_year = msam.tax_year
    where msam.tax_year = 2025
        and date(msam.server_timestamp) >= date('2026-03-12')
        and msam.auth_id is not null
)

select b.canvas_name
    , b.canvas_step_name
    , b.test_group
    , count(distinct b.pseudonym_id) as sends
    , count(distinct case when l.auth_id is not null then b.pseudonym_id end) as reauths
    , sum(pam.completed_flag) as completes
from base b
left join logins l
    on b.pseudonym_id = l.pseudonym_id
        and date(l.session_start_datetime) >= date('2026-03-12')
left join tax_rpt.product_analytics_master pam
    on b.pseudonym_id = pam.pseudonym_id
        and pam.tax_year = 2025
where pam.first_completed_date is null or (pam.first_completed_date > l.session_start_datetime)
group by 1,2,3
order by 1,2,3
;
