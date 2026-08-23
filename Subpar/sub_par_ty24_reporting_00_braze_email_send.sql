DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_send;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_send AS
--test
select distinct
  a.pseudonym_id
, b.accountid as auth_id
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
, 'V1' as test_window
, em.canvas_name
, em.canvas_id
, em.canvas_step_name
--date that email was sent or delivered  
--, date(cast(replace(cast(from_unixtime(em.time) AT TIME ZONE 'America/Los_Angeles' as varchar), ' America/Los_Angeles') as timestamp)) as dt_em_sent
, date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) as dt_em_sent
from cgan_ustax_ws.sub_par_ty24_00_em_historical as a 
left join tax_src.src_braze_turbotax_email_send as em
  on a.pseudonym_id = em.external_user_id
    and em.year=2025
    and em.canvas_id = '581c52df-01e9-46b8-b0cc-3d3d63739140'
--for retrieving auth_id
left join intuit_foundation_identityandcustomer360_unified_dwh.person_account as b
  on a.pseudonym_id = b.digitalidentitypseudonymid   
    and b.profilestatus = 'ACTIVE' 
;
