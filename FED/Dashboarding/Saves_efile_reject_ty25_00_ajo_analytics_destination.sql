drop table if exists cgan_ustax_ws.Saves_states_efile_reject_ty25_00_ajo_analytics_destination_stg;
create table cgan_ustax_ws.Saves_states_efile_reject_ty25_00_ajo_analytics_destination_stg as
SELECT distinct
    aepJourney.currentNodeName as aepJourney_currentNodeName,
    aepJourney.journeyVersionName,
    pseudonymid,
    DATE(
        CONVERT_TIMEZONE(
            'America/Los_Angeles', 
            'UTC', 
            TRY_CAST(
                COALESCE(
                    get_json_object(CAST(__event_payload AS STRING), '$.aepJourney.stepExecutionTime'),
                    get_json_object(CAST(__event_payload AS STRING), '$.aepjourney.stepexecutiontime')
                ) AS TIMESTAMP
            )
        )
    ) AS timestamp_ingestion
  
FROM intuit_customergrowthandengagement_marketingtech_journeymanagement.aepttousrejectjourneys_history
-- aepJourney.stepExecutionTime > from_iso8601_timestamp('2025-02-01T12:07:15.259163927-08:00')
 where aepJourney.journeyVersionName in ('TY2025_SERCJO_realtime')
 and aepJourney.currentNodeName in (
      -- -------------------------------------------------FEDERAL CJO KEYS----------------------------------------
      'JO_CDC_Destination3 - entered_analytics_ty25_sercjo_realtime',  -- entered_analytics_sercjo_realtime
      'JO_CDC_Destination4 - holdout_analytics_ty25_sercjo_realtime',       --  Analytics - Holdout
      'JO_CDC_Destination - test_analytics_ty25_sercjo_realtime',  -- test_analytics
       'JO_CDC_Destination1 - epcDay1_analytics_ty25_sercjo_realtime',    -- qualified for day 1 epc
      'JO_CDC_Destination6 - prcDay2_analytics_ty25_sercjo_realtime'         --  Analytics - Qualified for Day 2 PRC
  );

drop table if exists cgan_ustax_ws.Saves_states_efile_reject_ty25_00_ajo_analytics_destination;
create table cgan_ustax_ws.Saves_states_efile_reject_ty25_00_ajo_analytics_destination as
select 
  a.pseudonymid as pseudonym_id
, pam.auth_id
, min(date(cast(timestamp_ingestion as timestamp))) as eligible_date_min_pst
, max(date(cast(timestamp_ingestion as timestamp))) as eligible_date_max_pst,
-------------------------------------------------FEDERAL CJO KEYS----------------------------------------
--flags CJO
  max(case when a.aepJourney_currentNodeName = 'JO_CDC_Destination3 - entered_analytics_ty25_sercjo_realtime' then 1 else 0 end) as entered_analytics_sercjo_realtime,
    max(case when a.aepJourney_currentNodeName = 'JO_CDC_Destination4 - holdout_analytics_ty25_sercjo_realtime' then 1 else 0 end) as analytics_holdout_journey,
    max(case when a.aepJourney_currentNodeName = 'JO_CDC_Destination33 - ErrorCodes_analytics_fercjo_realtime' then 1 else 0 end) as ErrorCodes,
    max(case when a.aepJourney_currentNodeName = 'JO_CDC_Destination - test_analytics_ty25_sercjo_realtime' then 1 else 0 end) as test_analytics,
    max(case when a.aepJourney_currentNodeName = 'JO_CDC_Destination1 - epcDay1_analytics_ty25_sercjo_realtime' then 1 else 0 end) as flag_epcDay1,
    max(case when a.aepJourney_currentNodeName = 'JO_CDC_Destination6 - prcDay2_analytics_ty25_sercjo_realtime'  then 1 else 0 end) as flag_prcDay2
from cgan_ustax_ws.Saves_states_efile_reject_ty25_00_ajo_analytics_destination_stg a
left join tax_rpt.product_analytics_master pam
  on a.pseudonymid = pam.pseudonym_id
 and pam.tax_year = 2025
group by 1,2;
