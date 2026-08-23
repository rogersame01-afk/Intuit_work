DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_delivered;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_delivered AS
select distinct
  a.pseudonym_id
, a.issue_type
, a.cell
, a.date_issue
, a.datetime_qualified
, a.date_qualified
, a.mpm
--, a.copy_type
, a.dt
, a.mpm_cell

--email details
, case when em.external_user_id is not null then 1 else 0 end as flag_test --if customer gets email, should be in test group
, case when em.external_user_id is not null then 'test' end as test_group --if customer gets email, should be in test group
, em.canvas_name
, em.canvas_id
, em.canvas_step_name
--ref alexis code for dt_em_delivered format 
--https://github.intuit.com/CGCSData/cgcs-core-cx/blob/master/outreach/efile_rejects/ty24/reporting/fed_core/Saves_efile_reject_ty24_00_braze_em.sql#L50
, date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) as dt_em_delivered
, case when em.external_user_id is not null then 1 else 0 end as flag_delivered 
from cgan_ustax_ws.sub_par_ty24_00_em_historical as a 
left join tax_src.src_braze_turbotax_email_delivery as em
  on a.pseudonym_id = em.external_user_id  
  and em.year=2025
  and em.canvas_id = '581c52df-01e9-46b8-b0cc-3d3d63739140'
;    
