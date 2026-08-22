-- bayes;
drop table if exists cgan_general_published.ty25_5177_auths;
create table cgan_general_published.ty25_5177_auths as
with test as (
  select a.test_name
    , a.auth_id
    , a.pseudonym_id
    , a.first_assignment_timestamp_pt
    , a.first_assignment_date_pt
    , a.recipe_name_1 as recipe
    , a.completed_flag
    , a.total_revenue
    , a.efile_attempt_flag
    , a.gtkm_flag
    , a.pi_flag
    , a.income_flag
    , a.fnf_flag
    , a.start_flag
  from cgan_ustax_ws.ty25_5177_7216_gdc_muc_consent_daily a
),

consent as (
  select auth_id
    , gave_consent_Global_Disclosure_7216
    , gave_consent_Global_Use_7216
  from cgan_ustax_published.Consents_by_AUTH_ty25_ty24_aw
  where tax_year = 2025
)

select t.*
  , c.gave_consent_Global_Disclosure_7216
  , c.gave_consent_Global_Use_7216
from test t
left join consent c
  on t.auth_id = c.auth_id
;



DROP TABLE IF EXISTS cgan_general_published.ty25_5177_auths_users;
CREATE TABLE cgan_general_published.ty25_5177_auths_users as 
    select
        auth_id                                        
      , test_name                                                               as experiment_id
      , first_assignment_date_pt                                                as cohort_date
      , recipe                                                                  as condition 
      , 'GDC Consent Rate'                                                      as metric
      , coalesce(gave_consent_Global_Disclosure_7216,0)                         as outcome
    from cgan_general_published.ty25_5177_auths

    union

    select
        auth_id                                        
      , test_name                                                               as experiment_id
      , first_assignment_date_pt                                                as cohort_date
      , recipe                                                                  as condition 
      , 'MUC Consent Rate'                                                      as metric
      , coalesce(gave_consent_Global_Use_7216,0)                                as outcome
    from cgan_general_published.ty25_5177_auths

    union

    select
        auth_id                                        
      , test_name                                                               as experiment_id
      , first_assignment_date_pt                                                as cohort_date
      , recipe                                                                  as condition 
      , 'S2C'                                                                   as metric
      , completed_flag                                                          as outcome
    from cgan_general_published.ty25_5177_auths
    where start_flag = 1

    union

    select
        auth_id                                        
      , test_name                                                               as experiment_id
      , first_assignment_date_pt                                                as cohort_date
      , recipe                                                                  as condition 
      , 'RPn'                                                                   as metric
      , coalesce(total_revenue,0)                                               as outcome
    from cgan_general_published.ty25_5177_auths
;


DROP TABLE IF EXISTS cgan_general_published.ty25_5177;
CREATE TABLE cgan_general_published.ty25_5177 as 
SELECT
  experiment_id,
  condition,
  metric,
  cohort_date,
  AVG(outcome) AS mean_outcome,
  STDDEV(outcome) AS std_outcome,
  COUNT(*) AS trials       
from cgan_general_published.ty25_5177_auths_users
group by 1,2,3,4
;
