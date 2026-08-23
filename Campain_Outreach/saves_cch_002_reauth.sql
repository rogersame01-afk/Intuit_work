DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_002_reauth;
CREATE TABLE cgan_ustax_ws.saves_cch_002_reauth as
select  
  base.auth_id
, base.tax_year
, base.date_outreach_start_pst
, base.CSO 
, base.outreach_channel
, 1 as flag_reauth 
from cgan_ustax_ws.saves_cch_001_historical as base
inner join tax_rpt.MARKETING_SESSION_ANALYTICS_MASTER as msam
  on cast(base.auth_id as string) = cast(msam.auth_id as string)
  and date(from_utc_timestamp(msam.SESSION_AUTH_TIMESTAMP, 'America/Los_Angeles')) >= base.date_outreach_start_pst
  and base.tax_year = msam.tax_year 
  and base.flag_tax_year_current = 1 --SET CURRENT TAX YEAR 
;    
