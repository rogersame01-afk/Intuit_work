--Change Log
--2/1 AD remove dlprd from schema.tablename 

/*
--This code captures the audience criteria for TY23 Sub Par Experiences call issues based on requirements dictated in: INSERT JIRA
Cohorts for the experience include Issues (in order of issue priority):
#1. Call Issue - High Wait Times (60+ minutes) and abandoned
#2. Call Issue - Late-Night Callbacks
#3. Excessive Transfers 3 or more same call
#4. Call Issue - 2+ Offered Not Handled
#5. Call Issue - High Wait Times (60+ minutes) and connected
Of the above, these cohorts are eligible for Apology + Discount:
--Call Issue - High Wait Times (60+ minutes) and abandoned - Outreach Details:  Email apology + 20% PCode Discount
--Call Issue - Late-Night Callbacks - Outreach Details:  Email apology + 20% PCode Discount
--Excessive Transfers 3 or more same call - Outreach Details:  Email apology + 20% PCode Discount
Of the above, these cohorts are eligible for Apology only
--Call Issue - 2+ Offered Not Handled - Outreach Details: Email apology
--Call Issue - High Wait Times (60+ minutes) and connected - Outreach Details: Email apology
*/


----------------------CREATE HISTORICAL SUB PAR---------------------------------------------
--This section will generate distinct data lake tables by:
--tax_year + date + customer auth_id 
--that were impacted by a sub par experience as defined by TY23 test
--------------------------------------------------------------------------------------------

--Cell = 
--Email Apology + 20% PCode Discount + Survey:
--Cohort: Call Issue - Excessive Transfers 3+ Same Call
--This identifies base population of customers where they had:
--3 or more transfers on the same call
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_excessivetransfers_3plus_samecall;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_00_excessivetransfers_3plus_samecall as
with transfers as (
select 
      cct.auth_id
    , cct.cc_id
    , cct.tax_year
    , sum(offered_flg) as offered_total
    , sum(customer_handle_flg) as handled_total
    , '3. excessive transfers 3 or more same call' as issue_type
from ent_care_7216_dwh.rpt_cct_interactions as cct
left join tax_rpt.product_analytics_master as pam
    on cast(cct.auth_id as string) = cast(pam.auth_id as string)
        and cct.tax_year = pam.tax_year
--left join cgan_ustax_published.abandon_LAST_SKU ls
  --      on cast(cct.auth_id as string) = cast(ls.auth_id as string)
    --        and cast(cct.tax_year as string) = cast(ls.tax_year as string)
where cct.transferred_flg = 1 --https://intuit-teams.slack.com/archives/C03M3RSEHDF/p1680718051453729?thread_ts=1680712573.863539&cid=C03M3RSEHDF
    --cct.transferred_from_queue is not null --transfers
    and cct.auth_id is not null
         and (pam.completed_sku IN ('600|PAID DELUXE','855|PAID PREMIUM','910|PAID TTL BASIC','915|PAID TTL STANDARD','920|PAID TTL DELUXE','945|PAID TTL PREMIUM')
              or pam.start_sku IN ('600|PAID DELUXE','855|PAID PREMIUM','910|PAID TTL BASIC','915|PAID TTL STANDARD','920|PAID TTL DELUXE','945|PAID TTL PREMIUM')
    --            or (ls.last_sku IN ('600|Paid Deluxe', '800|Paid Premier', '850|Paid Self Employed', '910|Paid TTL Basic', '920|Paid TTL Deluxe', '930|Paid TTL Premier', '940|Paid TTL SE'))
              )
    and cct.bu = 'cg'          
group by
      cct.auth_id
    , cct.cc_id
    , cct.tax_year
    , '3. excessive transfers 3 or more same call'           
)
select 
      cast(a.auth_id as string) as auth_id
    , cast(a.tax_year as int) as tax_year
    , date(cct.contact_start_ts) as dt
    , sum(a.offered_total) as offered_total
    , sum(a.handled_total) as handled_total
    , a.issue_type
from (select * from transfers where offered_total >= 3) a --identify population with 3+ transfers on same call
left join tax_rpt.product_analytics_master as pam
    on cast(a.auth_id as string) = cast(pam.auth_id as string)
        and a.tax_year = pam.tax_year
--join back to cct to retrieve date        
left join ent_care_7216_dwh.rpt_cct_interactions as cct
    on cast(a.auth_id as string) = cast(cct.auth_id as string)
        and a.tax_year = cct.tax_year
        and a.cc_id = cct.cc_id          
--left join cgan_ustax_published.abandon_LAST_SKU ls
  --      on cast(cct.auth_id as string) = cast(ls.auth_id as string)
    --        and cast(cct.tax_year as string) = cast(ls.tax_year as string)
where (         pam.completed_sku IN ('600|PAID DELUXE','855|PAID PREMIUM','910|PAID TTL BASIC','915|PAID TTL STANDARD','920|PAID TTL DELUXE','945|PAID TTL PREMIUM')
              or pam.start_sku IN ('600|PAID DELUXE','855|PAID PREMIUM','910|PAID TTL BASIC','915|PAID TTL STANDARD','920|PAID TTL DELUXE','945|PAID TTL PREMIUM')

     --     or ls.last_sku IN ('600|Paid Deluxe', '800|Paid Premier', '850|Paid Self Employed', '910|Paid TTL Basic', '920|Paid TTL Deluxe', '930|Paid TTL Premier', '940|Paid TTL SE')
      )
group by
      a.auth_id
    , a.tax_year
    , date(cct.contact_start_ts)
    , a.issue_type
;
