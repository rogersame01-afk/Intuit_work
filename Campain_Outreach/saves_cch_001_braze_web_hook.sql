DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_001_braze_webhook_stg;
CREATE TABLE cgan_ustax_ws.saves_cch_001_braze_webhook_stg AS

WITH BASE_WEBHOOK AS (
 SELECT *,
       COALESCE(s.canvas_name, s.campaign_name) AS outreach_campaign_name
    FROM tax_src.src_braze_turbotax_webhook_send S
    WHERE COALESCE(s.canvas_name, s.campaign_name)  like '%CSO%'
    AND year IN (2025, 2026))
  ,
  BASE_WEBHOOK_FILTERED AS (
    SELECT 
    *,
    CASE 
    WHEN SPLIT_PART(outreach_campaign_name, '_', 1) LIKE 'CSO-%' 
    THEN SPLIT_PART(outreach_campaign_name, '_', 1)
    ELSE CONCAT('CSO-', SPLIT_PART(outreach_campaign_name, '_', 1))
END AS cso_normalized
    FROM
    BASE_WEBHOOK
    WHERE external_user_id is not null),

 BASE_WEBHOOK_FILTERED_DEPUDED AS (
SELECT *
FROM (
     SELECT
          'web_hook'                                         AS outreach_channel
        , 'braze'                                           AS outreach_channel_type
        , CASE WHEN base.canvas_id IS NOT NULL
            THEN 'canvas' ELSE 'campaign' END            AS outreach_channel_subtype
        , COALESCE(base.canvas_id, base.campaign_id)        AS outreach_campaign_id_primary
        , base.outreach_campaign_name
        ,base.cso_normalized
        , base.canvas_step_name                             AS outreach_campaign_id_secondary
        , FROM_UTC_TIMESTAMP(
              CAST(base.time AS TIMESTAMP),
              'America/Los_Angeles')                         AS timestamp_outreach_start_pst
        , DATE(FROM_UTC_TIMESTAMP(
              CAST(base.time AS TIMESTAMP),
              'America/Los_Angeles'))                        AS date_outreach_start_pst
        , 'delivered'                                       AS outreach_delivered_primary
        , CAST(NULL AS STRING)                              AS outreach_delivered_secondary
        , CAST(NULL AS STRING)                              AS expert_id
        , 1                                                 AS flag_outreach_delivered
        , base.external_user_id                             AS pseudonym_id
        , CAST(NULL AS STRING)                              AS customer_contact_pii_type
        , CAST(NULL AS STRING)                              AS customer_contact_pii_value
        , CAST(NULL AS STRING)                              AS intuit_contact_type
        , CAST(NULL AS STRING)                              AS intuit_contact_value
        , CAST(NULL AS STRING)                              AS recording_id
        , CAST(NULL AS DOUBLE)                              AS outreach_duration_seconds
        , CAST(NULL AS STRING)                              AS outreach_engagement_type_primary
        , CAST(NULL AS STRING)                              AS outreach_opened
        , CAST(NULL AS STRING)                              AS outreach_click
        , CAST(NULL AS INT)                                 AS outreach_engagement_value_primary
        , CAST(NULL AS STRING)                              AS outreach_engagement_type_secondary
        , CAST(NULL AS INT)                                 AS outreach_engagement_value_secondary
        , ROW_NUMBER() OVER (
            PARTITION BY
                external_user_id,
                canvas_step_name,
                canvas_step_id,
                time
            ORDER BY
                ingest_date DESC) as rn
     FROM BASE_WEBHOOK_FILTERED as base
)
WHERE rn = 1)
,
 dim_date_deduped AS (
    SELECT *
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY tax_pt_date
                   ORDER BY tax_year DESC  -- keep most recent tax year assignment
               ) AS rn
        FROM common_dm.dim_cg_date
    )
    WHERE rn = 1
)
SELECT
     ch.*
    , sm.Type, sm.Driver, sm.Priority, sm.Product
    , sm.Desired_Outreach_Channel, sm.Stack_Rank, sm.Campaign_Name
    , sm.Status, sm.Target_Launch, sm.Call_to_Action, sm.Hypothesis
    , sm.Size_Number_of_Customers, sm.Content, sm.List_Provided_By, sm.CSO
    , sm.Send_Schedule, sm.USPS_Status, sm.Next_Steps_Comments
    , sm.Link_to_Checklist, sm.Link_to_Content_Email_Call_Script
    , sm.Added_to_IEP_Expert_Outreach_Hub, sm.Results_Summary, sm.Results_Link
    , sm.Revenue_ROI_Cost_of_Campaign, sm.Test, sm.Test_Recipes
    , sm.Customer_List_Attributes, sm.Customer_Cohort, sm.Refund_Trigger
    , sm.Financial_Impact, CAST(NULL AS STRING) AS Email_Ops_Notes, sm.Legal
    , sm.Reviewed_with_CG_Marketing, sm.Selected_Outreach_Channel
    , sm.Selected_Expert_Profile, sm.Requestor, sm.Org, sm.Slack_Channel
    , sm.Kickoff, sm.Date_of_SR_Incident, sm.Time_of_SR_Incident_Pacific
    , sm.Link_to_Data_JIRA_Attach_CSV, sm.Created_By, sm.Created
    , sm.timestamp_ingested_utc
    , DATE(FROM_UTC_TIMESTAMP(CURRENT_TIMESTAMP, 'America/Los_Angeles'))   AS date_outreach_ingested_pst
    , pam.auth_id
    , td.tax_pt_date, td.tax_year, td.season_part, td.tax_year_ind
    , td.reporting_date, td.tax_week, td.tax_day
    , CASE WHEN td.tax_year = 2025 THEN 1 ELSE 0 END                      AS flag_tax_year_current
    , CASE WHEN td.tax_year = 2024 THEN 1 ELSE 0 END                      AS flag_tax_year_prior

FROM BASE_WEBHOOK_FILTERED_DEPUDED AS ch

INNER JOIN cgan_ustax_ws.Saves_Smartsheet_Outreach_Campaigns_Roadmap AS sm
    ON  ch.cso_normalized = sm.CSO 
    AND ch.outreach_channel_type = 'braze'
    AND sm.CSO is not null

LEFT JOIN dim_date_deduped AS td
    ON  ch.date_outreach_start_pst = td.tax_pt_date

LEFT JOIN tax_rpt.product_analytics_master AS pam
    ON  ch.pseudonym_id = pam.pseudonym_id
    AND td.tax_year     = pam.tax_year;

INSERT INTO cgan_ustax_ws.saves_cch_001_braze_webhook
SELECT *, CURRENT_DATE AS last_ingested_date
FROM cgan_ustax_ws.saves_cch_001_braze_webhook_stg AS stg
WHERE NOT EXISTS (
    SELECT 1
    FROM cgan_ustax_ws.saves_cch_001_braze_webhook AS tgt
    WHERE tgt.pseudonym_id                  = stg.pseudonym_id
      AND tgt.outreach_campaign_id_primary  = stg.outreach_campaign_id_primary
      AND tgt.outreach_campaign_id_secondary = stg.outreach_campaign_id_secondary
      AND tgt.timestamp_outreach_start_pst  = stg.timestamp_outreach_start_pst
)

