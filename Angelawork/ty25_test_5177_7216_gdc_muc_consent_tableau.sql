drop table if exists cgan_ustax_ws.aw_test_ty25_5177_7216_gdc_muc_consent;
create table cgan_ustax_ws.aw_test_ty25_5177_7216_gdc_muc_consent as
with test as (
  select a.test_name
    , a.auth_id
    , a.pseudonym_id
    , a.first_assignment_timestamp_pt
    , a.first_assignment_date_pt
    , a.recipe_name_1
    , a.completed_flag
    , a.total_revenue
    , a.efile_attempt_flag
    , a.start_flag
    , a.gtkm_flag
    , a.pi_flag
    , a.income_flag
    , a.fnf_flag
  from cgan_ustax_ws.ty25_5177_7216_gdc_muc_consent_daily a
),

consent as (
  select auth_id
    , gave_consent_Global_Disclosure_7216
    , gave_consent_Global_Use_7216
  from cgan_ustax_published.Consents_by_AUTH_ty25_ty24_aw
  where tax_year = 2025
),

base as (
  select t.*
    , c.gave_consent_Global_Disclosure_7216
    , c.gave_consent_Global_Use_7216
  from test t
  left join consent c
    on t.auth_id = c.auth_id
)

select b.test_name
  , b.recipe_name_1
  , count(*) as users
  , sum(b.start_flag) as starts
  , sum(b.gave_consent_global_disclosure_7216) as gdc_consent
  , sum(b.gave_consent_global_use_7216) as muc_consent
  , sum(b.completed_flag) as completed
  , sum(b.efile_attempt_flag) as efile_attempt
  , sum(b.income_flag) as income
  , sum(b.fnf_flag) as fnf
  , sum(b.total_revenue) as total_revenue
from base b
group by 1,2
order by 1,2
;
