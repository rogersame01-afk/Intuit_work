DROP TABLE IF EXISTS cgan_general_published.ty25_4820_auths;
CREATE TABLE cgan_general_published.ty25_4820_auths as 
with test as (
    SELECT pam.auth_id as auth_id
        , pam.pseudonym_id as pseudonym_id
        , pam.tax_year
        , pam.first_fed_efile_attempted_date
        , case when pam.first_fed_efile_rejected_date is not null then 1 else 0 end as fed_efile_reject_flag
        , IXP.experiment_name as test_name
        , treatment_name AS recipe_name
        , MIN(date((first_timestamp))) as first_assignment_date_pt
        , MIN((first_timestamp)) as first_assignment_timestamp_pt
      FROM ixp_dwh.ixp_first_assignment ixp 
          JOIN tax_rpt.product_analytics_master pam 
            ON cast(ixp.id as varchar(255)) = cast(pam.auth_id as varchar(255))
            AND pam.tax_year = 2025
    WHERE 1=1
      AND ixp.experiment_id = 289392
      AND ixp.treatment_name IS NOT NULL
      AND ixp.version >= 16
      AND ixp.partitiondate >= date('2026-03-31')
      AND pam.first_fed_efile_attempted_date > first_timestamp -- users attempting to Efile for the first time AFTER getting assigned to the test
    GROUP BY 1,2,3,4,5,6,7
  ),

  rej as (
    select re.auth_id
        , max(case when rc.error_code = 'IND-031-04' then 1 else 0 end) as agi_reject_flag
        , max(case when rc.error_code = 'IND-181-01' then 1 else 0 end) as ippin_missing_reject_flag
        , max(case when rc.error_code = 'IND-180-01' then 1 else 0 end) as ippin_invalid_reject_flag
    from tax_dm.fact_efile_reject_error re
    left join tax_dm.dim_efile_reject_code rc
        on re.efile_reject_code_id = rc.efile_reject_code_id
    where re.filing_type_id = '244'
        and re.tax_year = 2025
        and re.auth_id <> -1
        and date(re.efile_status_timestamp) >= date('2026-03-31')
    group by 1
  ),

  contacts as (
    select cast(cct.auth_id as bigint) as auth_id			
    , cct.case_number			
    , cct.tax_year			
    , cast(cct.agent_corp_id as bigint) as agent_corp_id			
    , cct.agent_source_key			
    , cct.agent_partner_name			
    , cct.agent_routing_profile			
    , cct.contact_start_ts			
    , cct.offered_flg			
    , cct.customer_handle_flg			
    , cct.interaction_skill_function			
    , cct.leg_queue			
    , cct.interaction_skill_seg			
    , cct.agent_leg_start_ts_utc			
    , convert_timezone('UTC','America/Los_Angeles', cct.agent_leg_start_ts_utc) as agent_leg_start_ts_pt
    , cct.handle_seconds_dur			
    , cct.initiated_type			
    , cct.dropped_case_ind			
    from ent_care_7216_dwh.rpt_cct_interactions cct			
    where cct.tax_year = 2025			
    and cct.interaction_skill_country = 'US'			
    -- and cct.customer_handle_flg = 1			
    and cct.bu = 'cg'			
    -- and try(cast(cct.auth_id as bigint)) is not null			
    -- and date(cct.agent_leg_start_ts_utc) >= date('2025-03-31')			
    and date(convert_timezone('UTC','America/Los_Angeles', cct.agent_leg_start_ts_utc)) >= date('2026-03-31')
  )

  select t.auth_id
    , t.recipe_name
    , t.first_assignment_date_pt
    -- , case when t.first_fed_efile_attempted_date is not null then 1 else 0 end as efile_attempted_flag
    , coalesce(rej.agi_reject_flag,0) as agi_reject_flag
    , coalesce(rej.ippin_missing_reject_flag,0) as ippin_missing_reject_flag
    , coalesce(rej.ippin_invalid_reject_flag,0) as ippin_invalid_reject_flag
    , sum(coalesce(c.offered_flg,0)) as offered_contacts
    , greatest(coalesce(rej.ippin_missing_reject_flag,0),coalesce(rej.ippin_invalid_reject_flag,0)) as ippin_overall_reject_flag
    , greatest(coalesce(rej.agi_reject_flag,0),coalesce(rej.ippin_missing_reject_flag,0),coalesce(rej.ippin_invalid_reject_flag,0)) as overall_reject_flag
  from test t
  left join rej
    on t.auth_id = rej.auth_id
  left join contacts c
    on t.auth_id = c.auth_id
      and c.agent_leg_start_ts_pt >= t.first_assignment_date_pt
  group by 1,2,3,4,5,6
;

DROP TABLE IF EXISTS cgan_general_published.ty25_4820_auths_users;
CREATE TABLE cgan_general_published.ty25_4820_auths_users as 
    select
        auth_id                                        
      , 'IRS Integration'                                                       as experiment_id
      , date(first_assignment_date_pt)                                          as cohort_date
      , recipe_name                                                             as condition 
      , 'AGI Reject Rate'                                                       as metric
      , agi_reject_flag                                                         as outcome
    from cgan_general_published.ty25_4820_auths

    union

    select
        auth_id                                        
      , 'IRS Integration'                                                       as experiment_id
      , date(first_assignment_date_pt)                                          as cohort_date
      , recipe_name                                                             as condition 
      , 'IPPIN Missing Reject Rate'                                             as metric
      , ippin_missing_reject_Flag                                               as outcome
    from cgan_general_published.ty25_4820_auths

    union

    select
        auth_id                                        
      , 'IRS Integration'                                                       as experiment_id
      , date(first_assignment_date_pt)                                          as cohort_date
      , recipe_name                                                             as condition 
      , 'IPPIN Invalid Reject Rate'                                             as metric
      , ippin_invalid_reject_Flag                                               as outcome
    from cgan_general_published.ty25_4820_auths

    union

    select
        auth_id                                        
      , 'IRS Integration'                                                       as experiment_id
      , date(first_assignment_date_pt)                                          as cohort_date
      , recipe_name                                                             as condition 
      , 'IPPIN Overall Reject Rate'                                             as metric
      , ippin_overall_reject_Flag                                               as outcome
    from cgan_general_published.ty25_4820_auths

    union

    select
        auth_id                                        
      , 'IRS Integration'                                                       as experiment_id
      , date(first_assignment_date_pt)                                          as cohort_date
      , recipe_name                                                             as condition 
      , 'Overall Reject Rate (AGI + IPPIN)'                                     as metric
      , overall_reject_Flag                                                     as outcome
    from cgan_general_published.ty25_4820_auths
;


DROP TABLE IF EXISTS cgan_general_published.ty25_4820;
CREATE TABLE cgan_general_published.ty25_4820 as 
SELECT
  experiment_id,
  condition,
  metric,
  cohort_date,
  AVG(outcome) AS mean_outcome,
  STDDEV(outcome) AS std_outcome,
  COUNT(*) AS trials       
from cgan_general_published.ty25_4820_auths_users
group by 1,2,3,4
;

DROP TABLE IF EXISTS cgan_general_published.ty25_4820_revenue;
CREATE TABLE cgan_general_published.ty25_4820_revenue as 
with test as (
  select
    a.recipe_name,
    count(*) as trials,
    avg(a.overall_reject_flag) as reject_rate,
    sqrt(avg(a.overall_reject_flag) * (1 - avg(a.overall_reject_flag))) as std_dev,
    sqrt(avg(a.overall_reject_flag) * (1 - avg(a.overall_reject_flag))) / sqrt(count(*)) as std_error,
    power(sqrt(avg(a.overall_reject_flag) * (1 - avg(a.overall_reject_flag))) / sqrt(count(*)),2) as std_error_squared
  from cgan_general_published.ty25_4820_auths a
  group by a.recipe_name
),

baseline as (
  select reject_rate,
      std_error_squared
  from test
  where recipe_name = 'Baseline'
),

ci as (
select
  t.recipe_name,
  t.trials,
  t.reject_rate,
  t.reject_rate - b.reject_rate as reject_rate_delta,
  sqrt(t.std_error_squared + b.std_error_squared) as se_delta,
  (t.reject_rate - b.reject_rate) - 1.96*sqrt(t.std_error_squared + b.std_error_squared) as reject_rate_lower_95ci,
  (t.reject_rate - b.reject_rate) + 1.96*sqrt(t.std_error_squared + b.std_error_squared) as reject_rate_upper_95ci
from test t
cross join baseline b
where t.recipe_name <> 'Baseline'
),

size_cte as (
  select count(*) as size
  from tax_src.tto_abandonment_src
  where tab_name = 'Finish and File'
    and screen = 'filing-method-summary'
    and tax_year = 2024
    and date(from_unixtime(event_ts)) between (current_date - 364) and date('2025-04-30')
)

select
  ci.reject_rate_delta,
  ci.reject_rate_lower_95ci,
  ci.reject_rate_upper_95ci,

  -- rt revenue impact, 0.30 pay with rt, 0.20 remain unresolved, 165 arpc
  ci.reject_rate_delta * s.size * 0.30 * 0.20 * 165 as rt_revenue_impact,
  ci.reject_rate_lower_95ci * s.size * 0.30 * 0.20 * 165 as rt_revenue_impact_lower_95ci,
  ci.reject_rate_upper_95ci * s.size * 0.30 * 0.20 * 165 as rt_revenue_impact_upper_95ci,

  -- 5de impact, 0.13 attach, 0.80 fulfillment, 0.20 unresolved, 35 fee
  ci.reject_rate_delta * s.size * 0.13 * 0.80 * 0.20 * 35 as fivede_revenue_impact,
  ci.reject_rate_lower_95ci * s.size * 0.13 * 0.80 * 0.20 * 35 as fivede_revenue_impact_lower_95ci,
  ci.reject_rate_upper_95ci * s.size * 0.13 * 0.80 * 0.20 * 35 as fivede_revenue_impact_upper_95ci
from ci
cross join baseline b
cross join size_cte s
;
