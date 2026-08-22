DROP TABLE IF EXISTS cgan_general_published.ty25_1095a_ade_app_users_auth_level;
CREATE TABLE cgan_general_published.ty25_1095a_ade_app_users_auth_level as 
select auth_id
  , test_name                           as experiment_id
  , date(first_assignment_timestamp_pt) as cohort_date
  , recipe_name_1                       as condition
  , 'S2C'                               as metric
  , completed_flag                      as outcome
from cgan_ustax_ws.ty25_295574_1095_ade_mobile_app_daily

union
  
select auth_id
  , test_name                           as experiment_id
  , date(first_assignment_timestamp_pt) as cohort_date
  , recipe_name_1                       as condition
  , 'RPn'                               as metric
  , coalesce(total_revenue,0)           as outcome
from cgan_ustax_ws.ty25_295574_1095_ade_mobile_app_daily

union

select auth_id
  , test_name                           as experiment_id
  , date(first_assignment_timestamp_pt) as cohort_date
  , recipe_name_1                       as condition
  , 'E-File Reject Rate'                as metric
  , efile_reject_flag                   as outcome
from cgan_ustax_ws.ty25_295574_1095_ade_mobile_app_daily

union

select a.auth_id
  , test_name                           as experiment_id
  , date(first_assignment_timestamp_pt) as cohort_date
  , recipe_name_1                       as condition
  , '1095-A Reject Rate'                as metric
  , coalesce(reject_1095_flag,0)        as outcome
from cgan_ustax_ws.ty25_295574_1095_ade_mobile_app_daily a
;


DROP TABLE IF EXISTS cgan_general_published.ty25_1095a_ade_app;
CREATE TABLE cgan_general_published.ty25_1095a_ade_app as 
SELECT
  experiment_id,
  condition,
  metric,
  cohort_date,
  AVG(outcome) AS mean_outcome,
  STDDEV(outcome) AS std_outcome,
  COUNT(*) AS trials      
from cgan_general_published.ty25_1095a_ade_app_users_auth_level
group by 1,2,3,4
;
