DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_002_metrics_fs;
CREATE TABLE cgan_ustax_ws.saves_cch_002_metrics_fs as
select distinct
  base.*
  
--dates  
, fsm.first_start_date as first_start_date
, fsm.first_completed_date as first_completed_date
, pam.first_fed_efile_rejected_date
, pam.first_print_to_mail_date
, pam.first_fed_efile_accepted_date
, coalesce(pam.first_fed_efile_accepted_date, pam.first_print_to_mail_date) as first_file_success_date

--flags 

, case when fsm.first_start_date is not null then 1 else 0 end as flag_start
, case when fsm.first_completed_date is not null then 1 else 0 end as flag_complete
, case when fsm.first_completed_date is not null and pam.completed_sku like '%TTLF%' then 1 else 0 end as flag_complete_fs
, case when pam.first_fed_efile_rejected_date is not null then 1 else 0 end as flag_reject
, case when coalesce(pam.first_fed_efile_accepted_date, pam.first_print_to_mail_date) is not null then 1 else 0 end as flag_file_success

--attributes
, fsm.tto_segment_rollup
, fsm.tto_segment
, fsm.customer_type_rollup
, pam.start_sku_rollup
, pam.completed_sku_rollup
, fsm.completed_sku
from cgan_ustax_ws.saves_cch_001_historical as base
inner join cgan_ustax_published.fs_combined_master   as fsm
  on base.pseudonym_id = fsm.pseudonym_id
  and fsm.fs_entitlement_type in ('FS Starts','FS Upgrades') --customer started in FS
  and base.tax_year = fsm.tax_year 
  and base.flag_tax_year_current = 1 --SET CURRENT TAX YEAR 
left join tax_rpt.product_analytics_master as pam
  on base.pseudonym_id = pam.pseudonym_id
  and base.tax_year = pam.tax_year 
;   
