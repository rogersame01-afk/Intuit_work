--Change Log
--2/1  AD update new_time_stamp and time_bin_after_midnight logic
--2/10 PV update new_time_stamp and time_bin_after_midnight logic to remove conversion from utc to pst. It appears this conversion is already done in the cct table
--     that is even though the field is called agent_leg_start_ts_utc it is actually in pst 

DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_aftermidnight;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_00_aftermidnight as
with after_midnight as (
select 
          cast(cct.auth_id as string) as auth_id
        , cast(cct.tax_year as int) as tax_year
        , taxml.resident_state
     -- Compute the new timestamp adjusting for timezone difference removing conversion from utc to pst as seen in row 15
        , TIMESTAMPADD(HOUR, CAST(tz.Difference AS INT), cct.agent_leg_start_ts_utc) AS new_time_stamp
     -- , TIMESTAMPADD(HOUR, CAST(tz.Difference AS INT), from_utc_timestamp(cct.agent_leg_start_ts_utc, 'America/Los_Angeles')) AS new_time_stamp
     -- , cct.agent_leg_start_ts_utc + INTERVAL cast(tz.Difference as int) HOURS AS new_time_stamp
          
          -- Categorize time into 'After Midnight' bin removing conversion from utc to pst as seen in rows 24-29
        , CASE 
          WHEN HOUR(TIMESTAMPADD(HOUR, CAST(tz.Difference AS INT), cct.agent_leg_start_ts_utc)) BETWEEN 0 AND 4
          THEN 'After Midnight'
          END AS time_bin_after_midnight

      --  , CASE 
      --        WHEN 
      --              HOUR(TIMESTAMPADD(HOUR, CAST(tz.Difference AS INT), from_utc_timestamp(cct.agent_leg_start_ts_utc, 'America/Los_Angeles'))) >= 0
      --              AND HOUR(TIMESTAMPADD(HOUR, CAST(tz.Difference AS INT), from_utc_timestamp(cct.agent_leg_start_ts_utc, 'America/Los_Angeles'))) < 5
      --    THEN 'After Midnight'
      --    END AS time_bin_after_midnight

        , '2. late-night callback' as issue_type
        , sum(cct.offered_flg) as offered_total
        , sum(cct.customer_handle_flg) as handled_total
from ent_care_7216_dwh.rpt_cct_interactions as cct
left join tax_rpt.product_analytics_master as pam
        on cast(cct.auth_id as string) = cast(pam.auth_id as string)
            and cct.tax_year = pam.tax_year
left join tax_src.agg_taxml taxml
        on cast(cct.auth_id as string) = cast(taxml.auth_id as string)
                and cct.tax_year = taxml.tax_year
left join cgan_ustax_ws.tmp_state_timezones as tz --vertica table of state timezones xlsx - https://intuit.box.com/s/n2h9c73zm7dop1378rzwbhegl1vctbhs
        on taxml.resident_state = tz.Abbreviation
--left join cgan_ustax_published.abandon_LAST_SKU ls
--      on cast(cct.auth_id as string) = cast(ls.auth_id as string)
--           and cast(cct.tax_year as string) = cast(ls.tax_year as string)
where (lower(initiated_type) like '%callback%' or lower(initiated_type) like '%hms%' or lower(initiated_type) like '%outbound%')
        and cct.bu = 'cg' 
        --and cct.tax_year = 2022
           and (pam.completed_sku IN ('600|PAID DELUXE','855|PAID PREMIUM','910|PAID TTL BASIC','915|PAID TTL STANDARD','920|PAID TTL DELUXE','945|PAID TTL PREMIUM')
              or pam.start_sku IN ('600|PAID DELUXE','855|PAID PREMIUM','910|PAID TTL BASIC','915|PAID TTL STANDARD','920|PAID TTL DELUXE','945|PAID TTL PREMIUM')
   --              or (ls.last_sku IN ('600|Paid Deluxe', '800|Paid Premier', '850|Paid Self Employed', '910|Paid TTL Basic', '920|Paid TTL Deluxe', '930|Paid TTL Premier', '940|Paid TTL SE'))
          ) 
group by 1,2,3,4,5,6
)
select distinct
  auth_id
, tax_year
, new_time_stamp as dt
, offered_total
, handled_total
, issue_type
from after_midnight 
where time_bin_after_midnight = 'After Midnight'
;   
