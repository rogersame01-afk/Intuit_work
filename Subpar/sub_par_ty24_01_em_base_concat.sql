----------------------CREATE TY24 SUB PAR AUDIENCE---------------------------------------------
--This section will generate distinct data lake tables by:
--tax_year + date + customer auth_id 
--that are: (1) specific to TY24 (2) net-new audience in the daily email outreach process 
--will combine all upstream sub par experience data lake tables 
--2.1.25 TY24 REMOVED JOINS FOR ISSUES 4 AND 5 WHICH ARE 2+ OFFERED AND NOT HANDLED AND HIGH WAIT TIME AND COMPLETES
--2/1 AD placeholder for left joins to historical and braze em/holdout for suppression to ensure customers didn't already receive this outreach
--2/3 uncommented code to suppress historical file in lines 63 and 64. Need to also uncomment the joins to braze today, awaiting confirmation on names
--2/3 uncommented code to brze email delivery in lines there was no holdout so not uncommenting the webhook join
--3/4 added suppression of service recovery email that went out on feb 28 to approximately 1k cso 635
--6/23 AD there is cross-pollination - historical suppression was not applied. Added this logic to lines 78-80
--------------------------------------------------------------------------------------------

--This table contains multiple tax year by auth_id + date + issue_type. 
--If you wanted to look at trended views/yoy/sizing/etc, you could leverage this table to determine volume trends by tax year
--combine all issue_types into one table
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_01_em_base_concat;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_01_em_base_concat as
--combine all sub par experiences
--select * from cgan_ustax_ws.sub_par_ty24_00_callissue_offerednothandled2ormore
--union 
--select * from cgan_ustax_ws.sub_par_ty24_00_highwaittimes_connected
--union 
select * from cgan_ustax_ws.sub_par_ty24_00_aftermidnight --KEEP
union 
select * from cgan_ustax_ws.sub_par_ty24_00_highwaittimes_abandoned  --KEEP
union 
select * from cgan_ustax_ws.sub_par_ty24_00_excessivetransfers_3plus_samecall --KEEP
;

--isolate TY24 by auth_id + dt + issue_type
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_01_em_base_cy;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_01_em_base_cy as
select 
  a.auth_id
, a.dt
, a.issue_type
from cgan_ustax_ws.sub_par_ty24_01_em_base_concat as a 
where cast(a.tax_year as int) = 2024 
;


--isolate past few days for net-new audience for email outreach
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_02_em_base_stg;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_02_em_base_stg as
with stg as (
select distinct
  a.auth_id
, a.dt
, a.issue_type
, pam.pseudonym_id
from cgan_ustax_ws.sub_par_ty24_01_em_base_cy as a 
--isolate only customers that are pre-complete for this outreach
inner join tax_rpt.product_analytics_master as pam
  on cast(a.auth_id as string) = cast(pam.auth_id as string)
    and pam.tax_year = 2024
    and pam.start_sku not like '%CK%' --exclude credit karma
    and pam.start_sku not like '%TTLF%' --exclude full-service
    --customers have not completed
    and pam.completed_sku is null
    and pam.completed_flag = 0
    and pam.first_completed_date is null

left join cgan_ustax_ws.sub_par_ty24_00_em_historical as suppress 
  on pam.pseudonym_id = suppress.pseudonym_id
left join tax_src.src_braze_turbotax_email_delivery as em 
  on pam.pseudonym_id = em.external_user_id 
  and em.canvas_name like '%CSO-541_TY24%' 
  and date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) >= date('2025-02-03')
--added march 4 --- remove people included in service recovery email on feb 28th about 1k people
left join tax_src.src_braze_turbotax_email_delivery as email_suppress 
  on pam.pseudonym_id = email_suppress.external_user_id 
  and email_suppress.canvas_name='CSO-635_PhoneQueueBug' 
  where --Did the sub par experience occur within the last 7 days --Did the sub par experience occur within the last 7 days
    DATEDIFF(day, CAST(a.dt AS DATE), CURRENT_DATE) BETWEEN 0 AND 7
--remove people froms service recovery email
    and email_suppress.external_user_id is null
    --did not qualify previously
    and em.external_user_id is null 
    and suppress.pseudonym_id is null 
)
select distinct *
, row_number() over (partition by auth_id order by issue_type asc) as rn
from stg
;

--finalize/de-dupe the net-new audience for daily email outreach
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_04_em_base_final;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_04_em_base_final as
select distinct
  a.pseudonym_id as external_id
, a.issue_type
, a.dt as date_issue
, cast(current_timestamp as date) as date_qualified
, case 
-- reference the email creative to assign the right cell 
-- https://docs.google.com/document/d/1-yGQOw6HDt6tsuUHeESqSQ-MBEALkuIN5icjShCmx2E/edit?tab=t.0#heading=h.b7uwbx7wu3vi
-- feedback erin --- needs to be telling us --
 -- when a.issue_type IN ('4. 2+ offered not handled','5. high wait times & connected') then '1'
    when a.issue_type IN ('2. late-night callback') then '1'
    when a.issue_type IN ('1. high wait times & abandoned') then '3'
    when a.issue_type IN ('3. excessive transfers 3 or more same call') then '5'
    end as cell 
--, case
--    when a.issue_type IN ('4. 2+ offered not handled','5. high wait times & connected') then 'Email apology'
--    when a.issue_type IN ('2. late-night callback','1. high wait times & abandoned','3. excessive transfers 3 or more same call') then 'Email apology + 20% PCode Discount'
--    end as copy_type

from cgan_ustax_ws.sub_par_ty24_02_em_base_stg as a 

where
  --isolate top "priority" issue_type per pseudonym_id
  a.rn = 1
;
