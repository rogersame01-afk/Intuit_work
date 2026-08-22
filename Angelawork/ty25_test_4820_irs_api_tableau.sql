drop table if exists cgan_ustax_ws.aw_test_ty25_4820_irs_api_tableau;
create table cgan_ustax_ws.aw_test_ty25_4820_irs_api_tableau as (
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
    and date(convert_timezone('UTC','America/Los_Angeles', cct.agent_leg_start_ts_utc)) >= date('2026-03-12')
  ),

  base as (
    select t.auth_id
      , t.pseudonym_id
      , t.test_name
      , t.recipe_name
      , t.first_assignment_date_pt
      , t.first_assignment_timestamp_pt
      , case when t.first_fed_efile_attempted_date is not null then 1 else 0 end as efile_attempted_flag
      , coalesce(rej.agi_reject_flag,0) as agi_reject_flag
      , coalesce(rej.ippin_missing_reject_flag,0) as ippin_missing_reject_flag
      , coalesce(rej.ippin_invalid_reject_flag,0) as ippin_invalid_reject_flag
      , sum(coalesce(c.offered_flg,0)) as offered_contacts
    from test t
    left join rej
      on t.auth_id = rej.auth_id
    left join contacts c
      on t.auth_id = c.auth_id
        and c.agent_leg_start_ts_pt >= t.first_assignment_date_pt
    group by 1,2,3,4,5,6,7,8,9,10
  )

  select b.test_name
    , b.recipe_name
    , b.first_assignment_date_pt
    , count(distinct b.auth_id) as users
    , sum(b.efile_attempted_flag) as efile_attempted
    , sum(b.agi_reject_flag) as agi_reject
    , sum(b.ippin_missing_reject_flag) as ippin_missing_reject
    , sum(b.ippin_invalid_reject_flag) as ippin_invalid_reject
    , sum(b.offered_contacts) as offered_contacts
  from base b
  group by 1,2,3
  order by 1,2,3
)
;
