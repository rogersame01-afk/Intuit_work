drop table if exists cgan_ustax_ws.saves_efile_fed_reject_sms_ty25;
create table cgan_ustax_ws.saves_efile_fed_reject_sms_ty25 as
with base_raw as (
  -- Test (SMS send) rows
  select
    em.external_user_id as pseudonym_id,
    cast(em.time as timestamp) as ts_send,
    date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) as first_send_dt_la,
    case when d.external_user_id is not null then 1 else 0 end as delivered_flag,
    'Test' as test_group
  from tax_src.src_braze_turbotax_sms_send em
  left join tax_src.src_braze_turbotax_sms_delivery d
    on d.external_user_id = em.external_user_id
   and d.canvas_id = em.canvas_id
   and d.canvas_step_name = em.canvas_step_name
  where em.year = 2026
    and em.canvas_name = '60014_CSO_TY25_FEDefileReject_5k_low_SMS'

  union all

  -- Control (webhook) rows
  select
    wb.external_user_id as pseudonym_id,
    cast(wb.time as timestamp) as ts_send,
    date(from_utc_timestamp(cast(wb.time as timestamp), 'America/Los_Angeles')) as first_send_dt_la,
    0 as delivered_flag,
    'Control' as test_group
  from tax_src.src_braze_turbotax_webhook_send wb
  where wb.year = 2026
    and wb.canvas_name like '%60014_CSO_TY25_FEDefileReject_5k_low_SMS%'
),
base as (
  select
    pseudonym_id,
    test_group,
    min(ts_send) as first_send_ts,
    min(first_send_dt_la) as first_send_dt_la,
    max(delivered_flag) as any_delivery_flag
  from base_raw
  group by 1,2
),

-- aggregate logins/sessions -> first login after send (if any)
logins_after as (
  select
    l.pseudonym_id,
    min(l.session_start_datetime) as first_login_after_send
  from (
    select
      msam.server_timestamp as session_start_datetime,
      pam.pseudonym_id
    from tax_rpt.marketing_session_analytics_master msam
    inner join tax_rpt.product_analytics_master pam
      on msam.auth_id = pam.auth_id
     and pam.tax_year = msam.tax_year
    where msam.tax_year = 2025
      and date(msam.server_timestamp) >= date('2026-01-29')
      and msam.auth_id is not null
  ) l
  inner join base b
    on l.pseudonym_id = b.pseudonym_id
  where date(l.session_start_datetime) >= b.first_send_ts
  group by l.pseudonym_id
),

-- aggregate product analytics to get the refile success date (first_print_to_mail_date_adj)
pam_agg as (
  select
    pseudonym_id,
    min(first_print_to_mail_date_adj) as first_print_to_mail_date_adj,  -- DATE or date-like
    coalesce(first_fed_Efile_accepted_date,first_print_to_mail_date) as refiled_success_date
  from tax_rpt.product_analytics_master
  where tax_year = 2025
  group by 1,3
)

-- per-user flags (one row per pseudonym)

  select
    b.pseudonym_id,
    b.test_group,
    b.first_send_ts,
    b.first_send_dt_la,
    b.any_delivery_flag,

    -- reauth after SMS (exists)
    case when la.first_login_after_send is not null then 1 else 0 end as reauth_flag,

    p.first_print_to_mail_date_adj,

    -- Refile success AFTER send:
    -- DATE-safe: count as after if acceptance date is the same day or later than send date (first_send_dt_la).
    -- If you have a timestamp for acceptance, replace the date(...) comparison with timestamp comparison.
    case
      when refiled_success_date is null then 0
      when date(refiled_success_date) >= b.first_send_ts then 1
      else 0
    end as refile_after_send_flag,

    -- Refile BEFORE send (possible if this is their first_print before this trigger)
    case
      when refiled_success_date is not null
       and date(refiled_success_date) < b.first_send_ts then 1
      else 0
    end as refile_before_send_flag

  from base b
  left join logins_after la
    on b.pseudonym_id = la.pseudonym_id
  left join pam_agg p
    on b.pseudonym_id = p.pseudonym_id ;

drop table if exists cgan_ustax_ws.saves_efile_fed_reject_sms_ty25_final;
create table cgan_ustax_ws.saves_efile_fed_reject_sms_ty25_final as
select
  test_group,
  -- assigned users (ITT denominator)
  count(*) as assigned_users,

  -- REAUTH (secondary)
  sum(reauth_flag) as reauths,
  round(100.0 * sum(reauth_flag) / nullif(count(*),0), 4) as reauth_rate_pct,

  -- PRIMARY KPI: refile success after send
  sum(refile_after_send_flag) as refile_after_send,
  round(100.0 * sum(refile_after_send_flag) / nullif(count(*),0), 4) as refile_after_send_pct,

  -- Diagnostic: delivered users (TOT)
  count(case when any_delivery_flag = 1 then 1 end) as tot_delivered_users,
  sum(case when any_delivery_flag = 1 and refile_after_send_flag = 1 then 1 else 0 end) as tot_refile_after_send,
  round(100.0 * sum(case when any_delivery_flag = 1 and refile_after_send_flag = 1 then 1 else 0 end)
        / nullif(count(case when any_delivery_flag = 1 then 1 end),0), 4) as tot_refile_after_send_pct,

  -- Sanity buckets: before / after / never
  sum(refile_before_send_flag) as refile_before_send,
  sum(case when first_print_to_mail_date_adj is null then 1 else 0 end) as never_refiled,
  -- sanity total should equal assigned_users
  (sum(refile_before_send_flag) + sum(refile_after_send_flag) + sum(case when first_print_to_mail_date_adj is null then 1 else 0 end)) as sanity_total_check
from
cgan_ustax_ws.saves_efile_fed_reject_sms_ty25
group by 1
order by 1;
