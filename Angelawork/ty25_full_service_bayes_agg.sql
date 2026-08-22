DROP TABLE IF EXISTS cgan_general_published.ty25_full_service_cso_814;
CREATE TABLE cgan_general_published.ty25_full_service_cso_814 as 
SELECT
  experiment_id,
  condition,
  metric,
  cohort_date,
  AVG(outcome) AS mean_outcome,
  STDDEV(outcome) AS std_outcome,
  COUNT(*) AS trials 
from cgan_general_published.814_CS_TY25_E_File_FS_Reject_2k_1k_low_Auto_1
where cohort_date <> date('2026-02-26')
group by 1,2,3,4
;
