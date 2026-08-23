DROP TABLE IF EXISTS cgan_ustax_ws.saves_commshub_ob;
CREATE TABLE  cgan_ustax_ws.saves_commshub_ob;
-- WITH max_ts AS (
--     -- Computed once; reused in pre-filter CTE
--     SELECT MAX(timestamp_outreach_start_pst) AS max_outbound_ts
--     FROM cgan_ustax_ws.saves_cch_001_historical
--     WHERE outreach_channel = 'outbound'
-- )

WITH outbound_base AS (
    -- Pre-filter, pre-cast, and pre-compute repeated expressions before joining
    SELECT
          base.usercontext_pseudonymid
        , base.usercontext_phone
        , base.communication_source
        , base.communication_id
        , base.communication_identifier
        , base.communication_metadata
        , base.communication_dispatchinfo_status
        , base.communication_engagements
        , base.communication_dispatchinfo_errorstatus
        , base.lastmodifiedat
        -- Pre-compute timestamp once; reused in WHERE, SELECT, and date derivation
        , FROM_UTC_TIMESTAMP(
              TO_TIMESTAMP(base.communication_dispatchInfo_time / 1000),
              'America/Los_Angeles')                        AS timestamp_outreach_start_pst
        , DATE(FROM_UTC_TIMESTAMP(
              TO_TIMESTAMP(base.communication_dispatchInfo_time / 1000),
              'America/Los_Angeles'))                        AS date_outreach_start_pst
        -- Pre-compute JSON extractions reused across multiple columns
        , CAST(GET_JSON_OBJECT(base.communication_identifier, '$.type')         AS STRING) AS comm_type
        , CAST(GET_JSON_OBJECT(base.communication_identifier, '$.contactId')    AS STRING) AS comm_contact_id
        , CAST(GET_JSON_OBJECT(base.communication_metadata,   '$.secondaryDisposition.SpokeCustomer') AS STRING) AS comm_spoke_customer
        , CAST(GET_JSON_OBJECT(base.communication_metadata,   '$.expertId')     AS STRING) AS comm_expert_id
        , CAST(GET_JSON_OBJECT(base.communication_metadata,   '$.outboundAni')  AS STRING) AS comm_outbound_ani
        , CAST(GET_JSON_OBJECT(base.communication_metadata,   '$.recordingId')  AS STRING) AS comm_recording_id
        , CAST(GET_JSON_OBJECT(base.communication_metadata,   '$.handleTime')   AS STRING) AS comm_handle_time
    FROM stream2hive_dwh.ch_user_communication_history AS base
--     CROSS JOIN max_ts
--     WHERE LOWER(CAST(GET_JSON_OBJECT(
--                 base.communication_identifier, '$.type') AS STRING))
--               IN ('expert-placed', 'pre-recorded')
--         AND YEAR(DATE(TO_TIMESTAMP(base.lastmodifiedat)))
--               = YEAR(DATE(FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP, 'America/Los_Angeles'))
--   )
--         AND FROM_UTC_TIMESTAMP(
--                 TO_TIMESTAMP(base.communication_dispatchInfo_time / 1000),
--                 'America/Los_Angeles') > max_ts.max_outbound_ts 
  )

, a AS (
    -- Net-new outbound call records with disposition mapping
    SELECT DISTINCT
          'outbound'                                        AS outreach_channel
        , base.communication_source                        AS outreach_channel_type
        , base.comm_type                                   AS outreach_channel_subtype
        , base.comm_contact_id                             AS outreach_campaign_id_primary
        , NULL                                             AS outreach_campaign_name
        , base.communication_id                            AS outreach_campaign_id_secondary
        , base.timestamp_outreach_start_pst
        , base.date_outreach_start_pst

        -- Delivery disposition: collapsed repeated SUCCESS + engagement pattern
        , CASE
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%INT - Spoke with Customer%'  THEN 'Spoke with customer'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Spoke with customer%'        THEN 'Spoke with customer'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Complete%'                   THEN 'Spoke with customer'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Left VM%'                    THEN 'Left VM'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Answering Machine%'          THEN 'Left VM'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Call Back%'                  THEN 'Call Back'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Spoke with 3rd Party%'       THEN 'Spoke with 3rd Party'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%INT - Transfer - Security%'  THEN 'Transferred to Security'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%INT - Transfer - Spanish%'   THEN 'Transferred to Spanish'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%INT - Updated Customers Info%' THEN 'Updated Customers Info'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Agent Error%'                THEN 'Agent Error'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Caller Disconnected%'        THEN 'Caller Disconnected'
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND base.communication_engagements LIKE '%Hangup%'                     THEN 'Caller Disconnected'
              ELSE base.communication_dispatchinfo_errorstatus
          END                                              AS outreach_delivered_primary

        , base.comm_spoke_customer                         AS outreach_delivered_secondary
        , base.comm_expert_id                              AS expert_id

        -- flag_outreach_delivered: 1 if spoke with customer (any variant)
        -- consolidated: all three patterns map to the same outcome
        , CASE
              WHEN base.communication_dispatchinfo_status = 'SUCCESS'
               AND (   base.communication_engagements LIKE '%INT - Spoke with Customer%'
                    OR base.communication_engagements LIKE '%Spoke with customer%'
                    OR base.communication_engagements LIKE '%Complete%'
                    OR LOWER(base.communication_engagements) LIKE '%spoke with customer%'
                   ) THEN 1
              ELSE 0
          END                                              AS flag_outreach_delivered

        , base.usercontext_pseudonymid                     AS pseudonym_id
        , 'phone'                                          AS customer_contact_pii_type
        , base.usercontext_phone                           AS customer_contact_pii_value
        , 'phone'                                          AS intuit_contact_type
        , base.comm_outbound_ani                           AS intuit_contact_value
        , base.comm_recording_id                           AS recording_id
        , base.comm_handle_time                            AS outreach_duration_seconds    -- fixed typo: duraction
        , NULL                                             AS outreach_engagement_type_primary
        , NULL                                             AS outreach_engagement_value_primary
        , NULL                                             AS outreach_engagement_type_secondary
        , NULL                                             AS outreach_engagement_value_secondary

    FROM outbound_base AS base
)

SELECT DISTINCT
      a.*

    -- Smartsheet roadmap attributes
    , sm.Type
    , sm.Driver
    , sm.Priority
    , sm.Product
    , sm.Desired_Outreach_Channel
    , sm.Stack_Rank
    , sm.Campaign_Name
    , sm.Status
    , sm.Target_Launch
    , sm.Call_to_Action
    , sm.Hypothesis
    , sm.Size_Number_of_Customers
    , sm.Content
    , sm.List_Provided_By
    , sm.CSO
    , sm.Send_Schedule
    , sm.USPS_Status
    , sm.Next_Steps_Comments
    , sm.Link_to_Checklist
    , sm.Link_to_Content_Email_Call_Script
    , sm.Added_to_IEP_Expert_Outreach_Hub
    , sm.Results_Summary
    , sm.Results_Link
    , sm.Revenue_ROI_Cost_of_Campaign
    , sm.Test
    , sm.Test_Recipes
    , sm.Customer_List_Attributes
    , sm.Customer_Cohort
    , sm.Refund_Trigger
    , sm.Financial_Impact
    , sm.Email_Ops_Notes
    , sm.Legal
    , sm.Reviewed_with_CG_Marketing
    , sm.Selected_Outreach_Channel
    , sm.Selected_Expert_Profile
    , sm.Requestor
    , sm.Org
    , sm.Slack_Channel
    , sm.Kickoff
    , sm.Date_of_SR_Incident
    , sm.Time_of_SR_Incident_Pacific
    , sm.Link_to_Data_JIRA_Attach_CSV
    , sm.Created_By
    , sm.Created
    , sm.timestamp_ingested_utc

    -- Ingestion date
    , DATE(FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP, 'America/Los_Angeles')) AS date_outreach_ingested_pst

    -- Product analytics
    , pam.auth_id

    -- Tax calendar reporting attributes
    , td.tax_pt_date
    , td.tax_year
    , td.season_part
    , td.tax_year_ind
    , td.reporting_date
    , td.tax_week
    , td.tax_day

    -- Tax year flags
    , CASE WHEN td.tax_year = 2025 THEN 1 ELSE 0 END AS flag_tax_year_current
    , CASE WHEN td.tax_year = 2024 THEN 1 ELSE 0 END AS flag_tax_year_prior

FROM a

INNER JOIN cgan_ustax_ws.Saves_Smartsheet_Outreach_Campaigns_Roadmap AS sm
    ON  CONTAINS(sm.ContactID, a.outreach_campaign_id_primary)
    AND a.outreach_channel = 'outbound'
    AND LOWER(sm.Desired_Outreach_Channel) LIKE '%call%'

LEFT JOIN common_dm.dim_cg_date AS td
    ON  a.date_outreach_start_pst = td.tax_pt_date

LEFT JOIN tax_rpt.product_analytics_master AS pam
    ON  a.pseudonym_id = pam.pseudonym_id
    AND td.tax_year = pam.tax_year
;     
