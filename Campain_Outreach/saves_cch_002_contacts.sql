DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_002_contacts;
CREATE TABLE cgan_ustax_ws.saves_cch_002_contacts as
select  
  base.auth_id
, base.tax_year
, base.date_outreach_start_pst  
, base.CSO 
, base.outreach_channel
, 1 as flag_called_intuit --call occurred after outreach
, case when date(from_utc_timestamp(cct.contact_start_ts, 'America/Los_Angeles')) <= DATEADD(day, 7, base.date_outreach_start_pst) 
  then 1 else 0 end as flag_called_within_7_days --last 7 days -- call occurred within 7 days of outreach 
from cgan_ustax_ws.saves_cch_001_historical as base
inner join ent_care_7216_dwh.rpt_cct_interactions as cct
  on cast(cct.auth_id as string) = cast(base.auth_id as string)
  and date(from_utc_timestamp(cct.contact_start_ts, 'America/Los_Angeles')) >= base.date_outreach_start_pst
  and base.tax_year = cct.tax_year 
  and base.flag_tax_year_current = 1 --SET CURRENT TAX YEAR 
;  
