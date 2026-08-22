DROP TABLE IF EXISTS cgan_general_published.ty25_4786_users_auth_level;
CREATE TABLE cgan_general_published.ty25_4786_users_auth_level as 
select auth_id
  , test_name                           as experiment_id
  , date(first_assignment_timestamp_pt) as cohort_date
  , recipe_name_1                       as condition
  , 'S2C'                               as metric
  , completed_flag                      as outcome
from cgan_ustax_ws.ty25_285985_1095ade_sw_daily

union

select auth_id
  , test_name                           as experiment_id
  , date(first_assignment_timestamp_pt) as cohort_date
  , recipe_name_1                       as condition
  , 'E-File Reject Rate'                as metric
  , efile_reject_flag                   as outcome
from cgan_ustax_ws.ty25_285985_1095ade_sw_daily

union

select a.auth_id
  , test_name                           as experiment_id
  , date(first_assignment_timestamp_pt) as cohort_date
  , recipe_name_1                       as condition
  , '1095-A Reject Rate'                as metric
  , coalesce(reject_1095_flag,0)        as outcome
from cgan_ustax_ws.ty25_285985_1095ade_sw_daily a
left join cgan_ustax_ws.ty25_1095_ade_test_sw_mw_funnel_depth b
  on a.auth_id = b.auth_id
where (a.recipe_name_1 = 'Control' and b.ade_1095_screen_flag = 2)
  or (a.recipe_name_1 = 'B' and b.ade_1095_screen_flag = 3)
;


DROP TABLE IF EXISTS cgan_general_published.ty25_4786;
CREATE TABLE cgan_general_published.ty25_4786 as 
SELECT
  experiment_id,
  condition,
  metric,
  cohort_date,
  AVG(outcome) AS mean_outcome,
  STDDEV(outcome) AS std_outcome,
  COUNT(*) AS trials 
from cgan_general_published.ty25_4786_users_auth_level
GROUP BY 1,2,3,4
;
