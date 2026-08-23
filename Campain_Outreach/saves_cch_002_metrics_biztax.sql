DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_002_metrics_biztax;
CREATE TABLE cgan_ustax_ws.saves_cch_002_metrics_biztax as
select distinct
  base.*
  
--Biz Tax Incorporated (FS + LAB)
, pam.completed_flag as flag_completed_incorporated
, pam.start_sku as start_sku_incorporated
, pam.current_sku as current_sku_incorporated
, pam.first_completed_sku_fed as completed_sku_incorporated
, pam.first_complete_ts_fed as date_completed_incorporated

--Sole Proprietorship (SP)
, pam.cy_pt_start_sku_ytd as start_sku_sp
, pam.cy_pt_start_sku_rollup_ytd as start_sku_rollup_sp
, pam.cy_pt_completed_sku_ytd as completed_sku_sp
, pam.cy_pt_first_completed_date_adj as date_completed_sp

--flags
, case when pam.start_ts_adj is not null then 1 else 0 end as flag_start_incorporated
, case when pam.cy_pt_first_start_date_adj is not null then 1 else 0 end as flag_start_sp
, case when pam.first_complete_ts_fed is not null then 1 else 0 end as flag_complete_incorporated
, case when pam.cy_pt_first_completed_date_adj is not null then 1 else 0 end as flag_complete_sp
from cgan_ustax_ws.saves_cch_001_historical as base
inner join cgan_ustax_ws.biz_tax_product_analytics_master as pam
  on base.pseudonym_id = pam.start_pseudo_id
  and base.tax_year = pam.tax_year 
  and base.flag_tax_year_current = 1 --SET CURRENT TAX YEAR 
;  
