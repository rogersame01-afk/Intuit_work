DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_003_append_fs_stg1;
CREATE TABLE cgan_ustax_ws.saves_cch_003_append_fs_stg1 as
select distinct base.*

, coalesce(cct.flag_called_intuit, 0) as flag_called_intuit
, coalesce(cct.flag_called_within_7_days, 0) as flag_called_within_7_days 
from cgan_ustax_ws.saves_cch_002_metrics_fs as base
left join cgan_ustax_ws.saves_cch_002_contacts as cct
  on cast(cct.auth_id as string) = cast(base.auth_id as string)
    and cct.tax_year = base.tax_year
    and cct.date_outreach_start_pst = base.date_outreach_start_pst 
    and cct.cso = base.cso
    and cct.outreach_channel = base.outreach_channel  
;

DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_003_append_fs_stg;
CREATE TABLE cgan_ustax_ws.saves_cch_003_append_fs_stg as
select distinct base.*
, coalesce(reauth.flag_reauth, 0) as flag_reauth 
from cgan_ustax_ws.saves_cch_003_append_fs_stg1 as base
left join cgan_ustax_ws.saves_cch_002_reauth as reauth
  on cast(base.auth_id as string) = cast(reauth.auth_id as string)
    and reauth.tax_year = base.tax_year
    and reauth.date_outreach_start_pst = base.date_outreach_start_pst 
    and reauth.cso = base.cso
    and reauth.outreach_channel = base.outreach_channel 
;

DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_003_append_fs;
CREATE TABLE cgan_ustax_ws.saves_cch_003_append_fs as
select * from cgan_ustax_ws.saves_cch_003_append_fs_historical --historical
union 
select * from cgan_ustax_ws.saves_cch_003_append_fs_stg --current tax year
;
