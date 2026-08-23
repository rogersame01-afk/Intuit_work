DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_002_metrics_diydiwm;
CREATE TABLE cgan_ustax_ws.saves_cch_002_metrics_diydiwm as
select distinct
  base.*
  
--dates  
, pam.first_start_date
, pam.first_completed_date
, pam.first_fed_efile_rejected_date
, pam.first_print_to_mail_date
, pam.first_fed_efile_accepted_date
, coalesce(pam.first_fed_efile_accepted_date, pam.first_print_to_mail_date) as first_file_success_date

--flags
, case when pam.first_start_date is not null then 1 else 0 end as flag_start
  --complete occurred after outreach
, case when pam.first_completed_date is not null and date(pam.first_completed_date) >= base.date_outreach_start_pst then 1 else 0 end as flag_complete
, case when pam.first_fed_efile_rejected_date is not null then 1 else 0 end as flag_reject
  --file success occurred after outreach
, case when coalesce(pam.first_fed_efile_accepted_date, pam.first_print_to_mail_date) is not null and coalesce(date(pam.first_fed_efile_accepted_date), date(pam.first_print_to_mail_date)) >= base.date_outreach_start_pst  then 1 else 0 end as flag_file_success

--attributes
, pam.tto_segment_rollup
, pam.tto_segment
, pam.customer_type_rollup
, pam.start_sku_rollup
, pam.completed_sku_rollup
, pam.completed_sku
from cgan_ustax_ws.saves_cch_001_historical as base
left join tax_rpt.product_analytics_master as pam
  on base.pseudonym_id = pam.pseudonym_id
  and base.tax_year = pam.tax_year 
where base.flag_tax_year_current = 1 --SET CURRENT TAX YEAR 
;    
