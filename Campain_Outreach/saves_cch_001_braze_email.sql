DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_001_braze_email_stg;
CREATE TABLE cgan_ustax_ws.saves_cch_001_braze_email_stg AS

WITH BASE_EMAIL AS (
 SELECT *,
       COALESCE(s.canvas_name, s.campaign_name) AS outreach_campaign_name
    FROM tax_src.src_braze_turbotax_email_send S
    WHERE COALESCE(s.canvas_name, s.campaign_name)  like '%CSO%'
    AND year IN (2025, 2026))
  ,
  BASE_EMAIL_FILTERED AS (
    SELECT 
    *,
    CASE 
    WHEN SPLIT_PART(outreach_campaign_name, '_', 1) LIKE 'CSO-%' 
    THEN SPLIT_PART(outreach_campaign_name, '_', 1)
    ELSE CONCAT('CSO-', SPLIT_PART(outreach_campaign_name, '_', 1))
END AS cso_normalized
    FROM
    BASE_EMAIL
    WHERE external_user_id is not null),
BASE_EMAIL_DEPUDED AS (
SELECT *
FROM (
    SELECT
        id,
        user_id,
        dispatch_id,
        external_user_id,
        time,
        timezone,
        campaign_id,
        campaign_name,
        message_variation_id,
        email_address,
        canvas_id,
        canvas_name,
        canvas_variation_id,
        canvas_step_id,
        send_id,
        canvas_variation_name,
        canvas_step_name,
        ip_pool,
        run_detail_id,
        ingest_date,
        message_extras,
        year,
        month,
        day,
        outreach_campaign_name,
        cso_normalized,

        ROW_NUMBER() OVER (
            PARTITION BY
                external_user_id,
                canvas_name,
                canvas_step_id,
                canvas_step_name,
                time
            ORDER BY
                (SELECT NULL)
        ) AS rn

     FROM BASE_EMAIL_FILTERED
)
WHERE rn = 1)
  ,
 email_engagement AS (
    SELECT
          s.external_user_id
        , COALESCE(s.canvas_id, s.campaign_id)              AS campaign_id_coalesced
        , s.canvas_step_name
        , s.cso_normalized
        , s.outreach_campaign_name
        , s.canvas_id
        , s.campaign_id
        , s.canvas_name
        , s.campaign_name
        , s.time
        , FROM_UTC_TIMESTAMP(
              CAST(s.time AS TIMESTAMP),
              'America/Los_Angeles')                         AS timestamp_outreach_start_pst
        , DATE(FROM_UTC_TIMESTAMP(
              CAST(s.time AS TIMESTAMP),
              'America/Los_Angeles'))                        AS date_outreach_start_pst
        , MAX(CASE WHEN d.external_user_id IS NOT NULL
                   THEN 1 ELSE 0 END)                       AS flag_outreach_delivered
        , MAX(CASE WHEN d.external_user_id IS NOT NULL
                   THEN 'delivered' ELSE NULL END)          AS outreach_delivered_primary
        , MAX(CASE WHEN o.external_user_id IS NOT NULL
                   THEN 1 ELSE 0 END)                       AS flag_open
        , MAX(CASE WHEN c.external_user_id IS NOT NULL
                   THEN 1 ELSE 0 END)                       AS flag_click
        , MAX(CASE WHEN b.external_user_id IS NOT NULL
                   THEN 1 ELSE 0 END)                       AS flag_bounce
        , MAX(CASE WHEN o.external_user_id IS NOT NULL
                   THEN 'open' ELSE NULL END)               AS outreach_opened
        , MAX(CASE WHEN c.external_user_id IS NOT NULL
                   THEN 'click' ELSE NULL END)              AS outreach_click

    FROM BASE_EMAIL_DEPUDED AS s

    LEFT JOIN tax_src.src_braze_turbotax_email_delivery AS d
        ON  s.external_user_id = d.external_user_id
        AND COALESCE(s.canvas_id, s.campaign_id) = COALESCE(d.canvas_id, d.campaign_id)
        AND (s.canvas_step_name IS NULL OR s.canvas_step_name = d.canvas_step_name)
        AND d.year IN (2025, 2026)

    LEFT JOIN tax_src.src_braze_turbotax_email_open AS o
        ON  s.external_user_id = o.external_user_id
        AND COALESCE(s.canvas_id, s.campaign_id) = COALESCE(o.canvas_id, o.campaign_id)
        AND (s.canvas_step_name IS NULL OR s.canvas_step_name = o.canvas_step_name)
        AND s.time <= o.time
        AND o.year IN (2025, 2026)

    LEFT JOIN tax_src.src_braze_turbotax_email_click AS c
        ON  s.external_user_id = c.external_user_id
        AND COALESCE(s.canvas_id, s.campaign_id) = COALESCE(c.canvas_id, c.campaign_id)
        AND (s.canvas_step_name IS NULL OR s.canvas_step_name = c.canvas_step_name)
        AND s.time <= c.time
        AND c.year IN (2025, 2026)

    LEFT JOIN tax_src.src_braze_turbotax_email_bounce AS b
        ON  s.external_user_id = b.external_user_id
        AND COALESCE(s.canvas_id, s.campaign_id) = COALESCE(b.canvas_id, b.campaign_id)
        AND (s.canvas_step_name IS NULL OR s.canvas_step_name = b.canvas_step_name)
        AND b.year IN (2025, 2026)

    GROUP BY
        s.external_user_id
        , COALESCE(s.canvas_id, s.campaign_id)        
        , s.canvas_step_name
        , s.cso_normalized
        , s.outreach_campaign_name
        , s.canvas_id
        , s.campaign_id
        , s.canvas_name
        , s.campaign_name
        , s.time
)

, email_base AS (
    SELECT
          'email'                                             AS outreach_channel
        , 'braze'                                            AS outreach_channel_type
        , CASE WHEN base.canvas_id IS NOT NULL
               THEN 'canvas' ELSE 'campaign' END             AS outreach_channel_subtype
        , base.campaign_id_coalesced                         AS outreach_campaign_id_primary
        , base.outreach_campaign_name
        ,base.cso_normalized
        , base.canvas_step_name                              AS outreach_campaign_id_secondary
        , base.timestamp_outreach_start_pst
        , base.date_outreach_start_pst
        , base.outreach_delivered_primary
        , CAST(NULL AS STRING)                               AS outreach_delivered_secondary
        , CAST(NULL AS STRING)                               AS expert_id
        , base.flag_outreach_delivered
        , base.external_user_id                              AS pseudonym_id
        , 'email'                                            AS customer_contact_pii_type
        , CAST(NULL AS STRING)                               AS intuit_contact_type
        , CAST(NULL AS STRING)                               AS intuit_contact_value
        , CAST(NULL AS STRING)                               AS recording_id
        , CAST(NULL AS DOUBLE)                               AS outreach_duration_seconds
        , 'flag_click'                                       AS outreach_engagement_type_primary
        , base.outreach_opened
        , base.outreach_click
        , base.flag_click                                    AS outreach_engagement_value_primary
        , 'flag_bounce'                                      AS outreach_engagement_type_secondary
        , base.flag_bounce                                   AS outreach_engagement_value_secondary

    FROM email_engagement AS base
),
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

FROM email_base AS ch

INNER JOIN cgan_ustax_ws.Saves_Smartsheet_Outreach_Campaigns_Roadmap AS sm
    ON  ch.cso_normalized = sm.CSO 
    AND ch.outreach_channel_type = 'braze'
    AND sm.CSO is not null

LEFT JOIN dim_date_deduped  AS td
    ON  ch.date_outreach_start_pst = td.tax_pt_date

LEFT JOIN tax_rpt.product_analytics_master AS pam
    ON  ch.pseudonym_id = pam.pseudonym_id
    AND td.tax_year     = pam.tax_year;

INSERT INTO cgan_ustax_ws.saves_cch_001_braze_email
SELECT *, CURRENT_DATE AS last_ingested_date
FROM cgan_ustax_ws.saves_cch_001_braze_email_stg AS stg
WHERE NOT EXISTS (
    SELECT 1
    FROM cgan_ustax_ws.saves_cch_001_braze_email AS tgt
    WHERE tgt.pseudonym_id                  = stg.pseudonym_id
      AND tgt.outreach_campaign_id_primary  = stg.outreach_campaign_id_primary
      AND tgt.outreach_campaign_id_secondary = stg.outreach_campaign_id_secondary
      AND tgt.timestamp_outreach_start_pst  = stg.timestamp_outreach_start_pst
)

