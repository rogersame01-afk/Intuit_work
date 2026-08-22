-- 1095-A Resolution Bayes;
-- Metris is refile success;

DROP TABLE IF EXISTS cgan_general_published.ty25_4956_users;
CREATE TABLE cgan_general_published.ty25_4956_users as 

with test as (
    select t.recipe_name
        , t.auth_id
        , t.first_assignment_timestamp
        , t.first_authentication_app_type
        , t.test_name
    from tax_rpt.rpt_testing_analytics_master_auth t
    where lower(t.test_name) = 'ty25_4956_1095a_jump_to_link_on_taxhome'
),

aca_errors as (
    select re.auth_id
        , min(re.efile_status_timestamp) as first_efile_status_timestamp
    from dlprd.tax_dm.fact_efile_reject_error re
    left join dlprd.tax_dm.dim_efile_reject_code rc
        on re.efile_reject_code_id = rc.efile_reject_code_id
    where re.filing_type_id = '244' 
        and rc.error_code = 'F8962-070'
        and re.tax_year = 2025
        and re.auth_id <> -1
    group by 1
),

contacts as (
  select cast(cct.auth_id as bigint) as auth_id
      , cct.agent_leg_start_ts_utc
      , date(cct.agent_leg_start_ts_utc) as agent_leg_start_date_utc
      , cct.interaction_skill_seg
      , cct.offered_flg -- sum this to get the total number of offered contacts
  from ent_care_7216_dwh.rpt_cct_interactions cct
  where cct.offered_flg = 1
      and cct.tax_year = 2025
      and cct.bu = 'cg'
      and cct.auth_id <> '000-00-0000'
      and cct.auth_id <> ''
      and cct.interaction_skill_seg = 'PS' -- limit to product support contacts only;
),

pam as (
    select pam.*
    from tax_rpt.product_analytics_master pam
    where pam.tax_year = 2025
)

select t.recipe_name
    , t.test_name
    , t.auth_id
    , t.first_assignment_timestamp
    , case when pam.first_fed_efile_accepted_date is not null then 1 else 0 end as refiled
    , case when c.auth_id is not null then 1 else 0 end as contacted
from test t
inner join aca_errors aca
    on t.auth_id = aca.auth_id
left join contacts c
    on t.auth_id = c.auth_id
        and c.agent_leg_start_ts_utc >= t.first_assignment_timestamp
left join pam
    on t.auth_id = pam.auth_id
where pam.first_fed_efile_attempted_date is not null
;

DROP TABLE IF EXISTS cgan_general_published.ty25_4956_users_auth_level;
CREATE TABLE cgan_general_published.ty25_4956_users_auth_level as 
    select
          auth_id                                        
        , test_name                                                                     as experiment_id
        , date(first_assignment_timestamp)                                              as cohort_date
        , recipe_name                                                                   as condition 
        , 'Refile Success'                                                              as metric
        , 1.0 * ((count(distinct case when refiled = 1 then auth_id end)) 
            / count(distinct auth_id))                                                  as outcome
    from cgan_general_published.ty25_4956_users
    group by 1,2,3,4,5
    
    union all
    
    select
          auth_id                                        
        , test_name                                                                     as experiment_id
        , date(first_assignment_timestamp)                                              as cohort_date
        , recipe_name                                                                   as condition 
        , 'PE Contact Rate'                                                             as metric
        , 1.0 * ((count(distinct case when contacted = 1 then auth_id end)) 
            / count(distinct auth_id))                                                  as outcome
    from cgan_general_published.ty25_4956_users
    group by 1,2,3,4,5
;


DROP TABLE IF EXISTS cgan_general_published.ty25_4956;
CREATE TABLE cgan_general_published.ty25_4956 as 
select 
          experiment_id
        , cohort_date
        , condition
        , metric
        , outcome        
from cgan_general_published.ty25_4956_users_auth_level
;
