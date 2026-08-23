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


--change log fy 24 ---
--jan 8th removing join to  dlprd.cgan_ustax_published.abandon_LAST_SKU since it has not been updated for a year
--jan 8th updated sku's in rows 58 and 59 after confirming with erin sanborn , these are the sku's for ty24 that are in pam table
--FEB 1 ADDED LENGTH TO VARCHAR BECAUSE IT WAS ERRORING OUT
--2/1 AD removed dlprd from schema.table_name

----------------------CREATE HISTORICAL SUB PAR---------------------------------------------
--This section will generate distinct data lake tables by:
--tax_year + date + customer auth_id 
--that were impacted by a sub par experience as defined by TY24 test
--------------------------------------------------------------------------------------------

--Cell =
--Email Apology + 20% PCode Discount + Survey: 
--Cohort: Call Issue - High Wait Times (30+ min or 2X SLA and abandoned)
--This identifies base population of customers where they had:
--High Wait Times (30+ minutes) OR 2X SLA
--Abandoned after waiting 30+ minutes
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_highwaittimes_abandoned;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_00_highwaittimes_abandoned as
select 
          cast(cct.auth_id as string) as auth_id
        , cast(cct.tax_year as int) as tax_year
        , date(cct.contact_start_ts) as dt
        , sum(cct.offered_flg) as offered_total
        , sum(cct.customer_handle_flg) as handled_total
        , '1. high wait times & abandoned' as issue_type
from ent_care_7216_dwh.rpt_cct_interactions as cct
left join tax_rpt.product_analytics_master as pam
        on cast(cct.auth_id as string) = cast(pam.auth_id as string)
            and cct.tax_year = pam.tax_year
--left join cgan_ustax_published.abandon_LAST_SKU ls
--        on cast(cct.auth_id as varchar) = cast(ls.auth_id as varchar)
--        and cast(cct.tax_year as varchar) = cast(ls.tax_year as varchar)
where --cct.leg_queue like '%transfer%'
        --customer abandoned after waiting
        cct.customer_handle_flg = 0
        and cct.auth_id is not null
        --customer waited 30 minutes
        and (cct.queue_seconds_dur >= 1800 --30 minutes
                    or cct.queue_seconds_dur > (cct.sla_target_duration_seconds * 2))
        and (pam.completed_sku IN ('600|PAID DELUXE','855|PAID PREMIUM','910|PAID TTL BASIC','915|PAID TTL STANDARD','920|PAID TTL DELUXE','945|PAID TTL PREMIUM')
              or pam.start_sku IN ('600|PAID DELUXE','855|PAID PREMIUM','910|PAID TTL BASIC','915|PAID TTL STANDARD','920|PAID TTL DELUXE','945|PAID TTL PREMIUM')
         --       or (ls.last_sku IN ('600|Paid Deluxe', '800|Paid Premier', '850|Paid Self Employed', '910|Paid TTL Basic', '920|Paid TTL Deluxe', '930|Paid TTL Premier', '940|Paid TTL SE'))
            )
        and cct.bu = 'cg'          
group by
          cct.auth_id
        , cct.tax_year
        , date(cct.contact_start_ts)
        , '1. high wait times & abandoned'
;  
