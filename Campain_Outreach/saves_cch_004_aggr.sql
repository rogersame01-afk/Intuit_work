DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr as
select 
--Campaign smartsheet attributes
  Type as outreach_type 
, Driver as outreach_driver
, Priority as outreach_priority
, Product as outreach_product
, Campaign_Name as campaign_name
, Status as outreach_status
, Hypothesis as outreach_hypothesis
, CSO as outreach_cso
, Send_Schedule as outreach_send_schedule
, Link_to_Content_Email_Call_Script as outreach_content_link
, Added_to_IEP_Expert_Outreach_Hub as outreach_added_to_iep_expert_outreach_hub
, Test as outreach_test
, Test_Recipes as outreach_test_recipe
, Customer_Cohort as outreach_customer_cohort
, Refund_Trigger as outreach_refund_trigger
, Financial_Impact as outreach_finance_impact
, Email_Ops_Notes as outreach_email_ops_notes
, Requestor as outreach_requestor
, Org as outreach_org
, Slack_Channel as outreach_slack_channel
, Date_of_SR_Incident as date_sr_incident
, Time_of_SR_Incident_Pacific as time_sr_incident
, Created as timestamp_added_to_smartsheet

--Touchpoint attributes
, date_outreach_start_pst
, outreach_channel
, outreach_channel_type
, outreach_channel_subtype
, outreach_campaign_id_primary
, outreach_campaign_name
--, outreach_campaign_id_secondary
, tax_year
--, case when outreach_cso IN ('CSO-547', 'CSO-548') then '2023' else tax_year end as tax_year --clean-up to reflect actual TY 

--Customer Attributes
, tto_segment_rollup
--, tto_segment
--, customer_type_rollup
, start_sku_rollup
, completed_sku_rollup
--, completed_sku

--Metrics
, count(*) as total_touchpoints
, count(distinct CSO) as distinct_csos
, count(distinct pseudonym_id) as distinct_customers
, count(distinct case when flag_start  = 1 then pseudonym_id end) as distinct_customers_start
, count(distinct case when flag_complete  = 1 then pseudonym_id end) as distinct_customers_complete
, count(distinct case when flag_reject  = 1 then pseudonym_id end) as distinct_customers_reject
, count(distinct case when flag_file_success  = 1 then pseudonym_id end) as distinct_customers_file_success
, count(distinct case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(distinct case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(distinct case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(distinct case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(distinct case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(distinct case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(distinct case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(distinct case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from cgan_ustax_ws.saves_cch_003_append_diwm
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33--,34,35,36,37,38
;

DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_outreach_type;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_outreach_type as
select 
  Type as outreach_type 
, tax_year 

--Metrics
, count(*) as total_touchpoints
, count(distinct CSO) as distinct_csos
, count(distinct pseudonym_id) as distinct_customers
, count(case when outreach_channel = 'email' then pseudonym_id end) as total_touchpoints_email
, count(case when outreach_channel = 'sms' then pseudonym_id end) as total_touchpoints_sms
, count(case when outreach_channel = 'push' then pseudonym_id end) as total_touchpoints_push
, count(case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as total_touchpoints_epc
, count(case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as total_touchpoints_prc
, count(distinct case when outreach_channel = 'email' then pseudonym_id end) as distinct_customers_email
, count(distinct case when outreach_channel = 'sms' then pseudonym_id end) as distinct_customers_sms
, count(distinct case when outreach_channel = 'push' then pseudonym_id end) as distinct_customers_push
, count(distinct case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as distinct_customers_epc
, count(distinct case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as distinct_customers_prc
, count(distinct case when flag_start  = 1 then pseudonym_id end) as distinct_customers_start
, count(distinct case when flag_complete  = 1 then pseudonym_id end) as distinct_customers_complete
, count(distinct case when flag_reject  = 1 then pseudonym_id end) as distinct_customers_reject
, count(distinct case when flag_file_success  = 1 then pseudonym_id end) as distinct_customers_file_success
, count(distinct case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(distinct case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(distinct case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(distinct case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(distinct case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(distinct case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(distinct case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(distinct case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from cgan_ustax_ws.saves_cch_003_append_diwm
group by Type, tax_year
;

-- DELETE FROM cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty25
-- WHERE TAX_YEAR = '2025';

INSERT INTO cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty25
SELECT *
FROM cgan_ustax_ws.saves_cch_004_aggr_outreach_type
WHERE TAX_YEAR = '2025';
DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty25_aggr;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty25_aggr
USING PARQUET AS
WITH base AS (
    SELECT 
        outreach_type, tax_year, total_touchpoints, distinct_csos, distinct_customers,
        total_touchpoints_email, total_touchpoints_sms, total_touchpoints_push,
        total_touchpoints_epc, total_touchpoints_prc, distinct_customers_email,
        distinct_customers_sms, distinct_customers_push, distinct_customers_epc,
        distinct_customers_prc, distinct_customers_start, distinct_customers_complete,
        distinct_customers_reject, distinct_customers_file_success, distinct_customers_reauth,
        distinct_customers_called_intuit, distinct_customers_called_intuit_within_7_days,
        distinct_customers_delivered, distinct_customers_open, distinct_customers_click,
        distinct_customers_bounce, distinct_customers_sms_textback
    FROM cgan_ustax_ws.saves_cch_004_aggr_outreach_type
    WHERE tax_year = '2025'

    UNION ALL

    SELECT 
        outreach_type, tax_year, total_touchpoints, distinct_csos, distinct_customers,
        total_touchpoints_email, total_touchpoints_sms, total_touchpoints_push,
        total_touchpoints_epc, total_touchpoints_prc, distinct_customers_email,
        distinct_customers_sms, distinct_customers_push, distinct_customers_epc,
        distinct_customers_prc, distinct_customers_start, distinct_customers_complete,
        distinct_customers_reject, distinct_customers_file_success, distinct_customers_reauth,
        distinct_customers_called_intuit, distinct_customers_called_intuit_within_7_days,
        distinct_customers_delivered, distinct_customers_open, distinct_customers_click,
        distinct_customers_bounce, distinct_customers_sms_textback
    FROM cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty24
),

pivoted AS (
    SELECT
        outreach_type,

        -- 2024 values
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints               END) AS total_touchpoints_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_csos                   END) AS distinct_csos_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers              END) AS distinct_customers_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_email         END) AS total_touchpoints_email_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_sms           END) AS total_touchpoints_sms_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_push          END) AS total_touchpoints_push_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_epc           END) AS total_touchpoints_epc_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_prc           END) AS total_touchpoints_prc_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_email        END) AS distinct_customers_email_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_sms          END) AS distinct_customers_sms_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_push         END) AS distinct_customers_push_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_epc          END) AS distinct_customers_epc_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_prc          END) AS distinct_customers_prc_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_start        END) AS distinct_customers_start_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_complete     END) AS distinct_customers_complete_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_reject       END) AS distinct_customers_reject_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_file_success END) AS distinct_customers_file_success_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_reauth       END) AS distinct_customers_reauth_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_called_intuit               END) AS distinct_customers_called_intuit_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_called_intuit_within_7_days END) AS distinct_customers_called_intuit_7d_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_delivered    END) AS distinct_customers_delivered_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_open         END) AS distinct_customers_open_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_click        END) AS distinct_customers_click_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_bounce       END) AS distinct_customers_bounce_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_sms_textback END) AS distinct_customers_sms_textback_2024,

        -- 2025 values
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints               END) AS total_touchpoints_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_csos                   END) AS distinct_csos_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers              END) AS distinct_customers_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_email         END) AS total_touchpoints_email_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_sms           END) AS total_touchpoints_sms_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_push          END) AS total_touchpoints_push_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_epc           END) AS total_touchpoints_epc_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_prc           END) AS total_touchpoints_prc_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_email        END) AS distinct_customers_email_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_sms          END) AS distinct_customers_sms_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_push         END) AS distinct_customers_push_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_epc          END) AS distinct_customers_epc_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_prc          END) AS distinct_customers_prc_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_start        END) AS distinct_customers_start_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_complete     END) AS distinct_customers_complete_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_reject       END) AS distinct_customers_reject_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_file_success END) AS distinct_customers_file_success_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_reauth       END) AS distinct_customers_reauth_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_called_intuit               END) AS distinct_customers_called_intuit_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_called_intuit_within_7_days END) AS distinct_customers_called_intuit_7d_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_delivered    END) AS distinct_customers_delivered_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_open         END) AS distinct_customers_open_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_click        END) AS distinct_customers_click_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_bounce       END) AS distinct_customers_bounce_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_sms_textback END) AS distinct_customers_sms_textback_2025

    FROM base
    GROUP BY outreach_type
)

SELECT
    outreach_type,

    -- Total Touchpoints
    total_touchpoints_2024,
    total_touchpoints_2025,
    ROUND((total_touchpoints_2025 - total_touchpoints_2024) / NULLIF(total_touchpoints_2024, 0) * 100, 1) AS total_touchpoints_yoy_pct,

    -- Distinct CSOs
    distinct_csos_2024,
    distinct_csos_2025,
    ROUND((distinct_csos_2025 - distinct_csos_2024) / NULLIF(distinct_csos_2024, 0) * 100, 1) AS distinct_csos_yoy_pct,

    -- Distinct Customers
    distinct_customers_2024,
    distinct_customers_2025,
    ROUND((distinct_customers_2025 - distinct_customers_2024) / NULLIF(distinct_customers_2024, 0) * 100, 1) AS distinct_customers_yoy_pct,

    -- Touchpoints by Channel
    total_touchpoints_email_2024, total_touchpoints_email_2025,
    ROUND((total_touchpoints_email_2025 - total_touchpoints_email_2024) / NULLIF(total_touchpoints_email_2024, 0) * 100, 1) AS total_touchpoints_email_yoy_pct,

    total_touchpoints_sms_2024, total_touchpoints_sms_2025,
    ROUND((total_touchpoints_sms_2025 - total_touchpoints_sms_2024) / NULLIF(total_touchpoints_sms_2024, 0) * 100, 1) AS total_touchpoints_sms_yoy_pct,

    total_touchpoints_push_2024, total_touchpoints_push_2025,
    ROUND((total_touchpoints_push_2025 - total_touchpoints_push_2024) / NULLIF(total_touchpoints_push_2024, 0) * 100, 1) AS total_touchpoints_push_yoy_pct,

    total_touchpoints_epc_2024, total_touchpoints_epc_2025,
    ROUND((total_touchpoints_epc_2025 - total_touchpoints_epc_2024) / NULLIF(total_touchpoints_epc_2024, 0) * 100, 1) AS total_touchpoints_epc_yoy_pct,

    total_touchpoints_prc_2024, total_touchpoints_prc_2025,
    ROUND((total_touchpoints_prc_2025 - total_touchpoints_prc_2024) / NULLIF(total_touchpoints_prc_2024, 0) * 100, 1) AS total_touchpoints_prc_yoy_pct,

    -- Distinct Customers by Channel
    distinct_customers_email_2024, distinct_customers_email_2025,
    ROUND((distinct_customers_email_2025 - distinct_customers_email_2024) / NULLIF(distinct_customers_email_2024, 0) * 100, 1) AS distinct_customers_email_yoy_pct,

    distinct_customers_sms_2024, distinct_customers_sms_2025,
    ROUND((distinct_customers_sms_2025 - distinct_customers_sms_2024) / NULLIF(distinct_customers_sms_2024, 0) * 100, 1) AS distinct_customers_sms_yoy_pct,

    distinct_customers_push_2024, distinct_customers_push_2025,
    ROUND((distinct_customers_push_2025 - distinct_customers_push_2024) / NULLIF(distinct_customers_push_2024, 0) * 100, 1) AS distinct_customers_push_yoy_pct,

    distinct_customers_epc_2024, distinct_customers_epc_2025,
    ROUND((distinct_customers_epc_2025 - distinct_customers_epc_2024) / NULLIF(distinct_customers_epc_2024, 0) * 100, 1) AS distinct_customers_epc_yoy_pct,

    distinct_customers_prc_2024, distinct_customers_prc_2025,
    ROUND((distinct_customers_prc_2025 - distinct_customers_prc_2024) / NULLIF(distinct_customers_prc_2024, 0) * 100, 1) AS distinct_customers_prc_yoy_pct,

    -- Funnel Stages
    distinct_customers_start_2024, distinct_customers_start_2025,
    ROUND((distinct_customers_start_2025 - distinct_customers_start_2024) / NULLIF(distinct_customers_start_2024, 0) * 100, 1) AS distinct_customers_start_yoy_pct,

    distinct_customers_complete_2024, distinct_customers_complete_2025,
    ROUND((distinct_customers_complete_2025 - distinct_customers_complete_2024) / NULLIF(distinct_customers_complete_2024, 0) * 100, 1) AS distinct_customers_complete_yoy_pct,

    distinct_customers_reject_2024, distinct_customers_reject_2025,
    ROUND((distinct_customers_reject_2025 - distinct_customers_reject_2024) / NULLIF(distinct_customers_reject_2024, 0) * 100, 1) AS distinct_customers_reject_yoy_pct,

    distinct_customers_file_success_2024, distinct_customers_file_success_2025,
    ROUND((distinct_customers_file_success_2025 - distinct_customers_file_success_2024) / NULLIF(distinct_customers_file_success_2024, 0) * 100, 1) AS distinct_customers_file_success_yoy_pct,

    distinct_customers_reauth_2024, distinct_customers_reauth_2025,
    ROUND((distinct_customers_reauth_2025 - distinct_customers_reauth_2024) / NULLIF(distinct_customers_reauth_2024, 0) * 100, 1) AS distinct_customers_reauth_yoy_pct,

    -- Support & Engagement
    distinct_customers_called_intuit_2024, distinct_customers_called_intuit_2025,
    ROUND((distinct_customers_called_intuit_2025 - distinct_customers_called_intuit_2024) / NULLIF(distinct_customers_called_intuit_2024, 0) * 100, 1) AS distinct_customers_called_intuit_yoy_pct,

    distinct_customers_called_intuit_7d_2024, distinct_customers_called_intuit_7d_2025,
    ROUND((distinct_customers_called_intuit_7d_2025 - distinct_customers_called_intuit_7d_2024) / NULLIF(distinct_customers_called_intuit_7d_2024, 0) * 100, 1) AS distinct_customers_called_intuit_7d_yoy_pct,

    -- Email Engagement
    distinct_customers_delivered_2024, distinct_customers_delivered_2025,
    ROUND((distinct_customers_delivered_2025 - distinct_customers_delivered_2024) / NULLIF(distinct_customers_delivered_2024, 0) * 100, 1) AS distinct_customers_delivered_yoy_pct,

    distinct_customers_open_2024, distinct_customers_open_2025,
    ROUND((distinct_customers_open_2025 - distinct_customers_open_2024) / NULLIF(distinct_customers_open_2024, 0) * 100, 1) AS distinct_customers_open_yoy_pct,

    distinct_customers_click_2024, distinct_customers_click_2025,
    ROUND((distinct_customers_click_2025 - distinct_customers_click_2024) / NULLIF(distinct_customers_click_2024, 0) * 100, 1) AS distinct_customers_click_yoy_pct,

    distinct_customers_bounce_2024, distinct_customers_bounce_2025,
    ROUND((distinct_customers_bounce_2025 - distinct_customers_bounce_2024) / NULLIF(distinct_customers_bounce_2024, 0) * 100, 1) AS distinct_customers_bounce_yoy_pct,

    -- SMS Textback
    distinct_customers_sms_textback_2024, distinct_customers_sms_textback_2025,
    ROUND((distinct_customers_sms_textback_2025 - distinct_customers_sms_textback_2024) / NULLIF(distinct_customers_sms_textback_2024, 0) * 100, 1) AS distinct_customers_sms_textback_yoy_pct

FROM pivoted
ORDER BY total_touchpoints_2025 DESC NULLS LAST;

/*DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_tax_year;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_tax_year as
select 
  tax_year

--Metrics
, count(*) as total_touchpoints
, count(distinct CSO) as distinct_csos
, count(distinct pseudonym_id) as distinct_customers
, count(case when outreach_channel = 'email' then pseudonym_id end) as total_touchpoints_email
, count(case when outreach_channel = 'sms' then pseudonym_id end) as total_touchpoints_sms
, count(case when outreach_channel = 'push' then pseudonym_id end) as total_touchpoints_push
, count(case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as total_touchpoints_epc
, count(case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as total_touchpoints_prc
, count(distinct case when outreach_channel = 'email' then pseudonym_id end) as distinct_customers_email
, count(distinct case when outreach_channel = 'sms' then pseudonym_id end) as distinct_customers_sms
, count(distinct case when outreach_channel = 'push' then pseudonym_id end) as distinct_customers_push
, count(distinct case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as distinct_customers_epc
, count(distinct case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as distinct_customers_prc
, count(distinct case when flag_start  = 1 then pseudonym_id end) as distinct_customers_start
, count(distinct case when flag_complete  = 1 then pseudonym_id end) as distinct_customers_complete
, count(distinct case when flag_reject  = 1 then pseudonym_id end) as distinct_customers_reject
, count(distinct case when flag_file_success  = 1 then pseudonym_id end) as distinct_customers_file_success
, count(distinct case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(distinct case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(distinct case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(distinct case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(distinct case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(distinct case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(distinct case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(distinct case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from cgan_ustax_ws.saves_cch_003_append_diwm
group by tax_year
;

DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_sent_month;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_sent_month as
select 
  outreach_month
, outreach_year  

--Metrics
, count(*) as total_touchpoints
, count(distinct CSO) as distinct_csos
, count(distinct pseudonym_id) as distinct_customers
, count(case when outreach_channel = 'email' then pseudonym_id end) as total_touchpoints_email
, count(case when outreach_channel = 'sms' then pseudonym_id end) as total_touchpoints_sms
, count(case when outreach_channel = 'push' then pseudonym_id end) as total_touchpoints_push
, count(case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as total_touchpoints_epc
, count(case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as total_touchpoints_prc
, count(distinct case when outreach_channel = 'email' then pseudonym_id end) as distinct_customers_email
, count(distinct case when outreach_channel = 'sms' then pseudonym_id end) as distinct_customers_sms
, count(distinct case when outreach_channel = 'push' then pseudonym_id end) as distinct_customers_push
, count(distinct case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as distinct_customers_epc
, count(distinct case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as distinct_customers_prc
, count(distinct case when flag_start  = 1 then pseudonym_id end) as distinct_customers_start
, count(distinct case when flag_complete  = 1 then pseudonym_id end) as distinct_customers_complete
, count(distinct case when flag_reject  = 1 then pseudonym_id end) as distinct_customers_reject
, count(distinct case when flag_file_success  = 1 then pseudonym_id end) as distinct_customers_file_success
, count(distinct case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(distinct case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(distinct case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(distinct case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(distinct case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(distinct case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(distinct case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(distinct case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from (select *, month(date_outreach_start_pst) as outreach_month, year(date_outreach_start_pst) as outreach_year  from cgan_ustax_ws.saves_cch_003_append_diwm) a
group by outreach_month, outreach_year
;*/
/*DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty25;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty25
USING PARQUET AS
select 
outreach_type
,tax_year	
,total_touchpoints	
,distinct_csos	
,distinct_customers	
,total_touchpoints_email	
,total_touchpoints_sms	
,total_touchpoints_push	
,total_touchpoints_epc	
,total_touchpoints_prc	
,distinct_customers_email	
,distinct_customers_sms	
,distinct_customers_push	
,distinct_customers_epc	
,distinct_customers_prc	
,distinct_customers_start	
,distinct_customers_complete	
,distinct_customers_reject	
,distinct_customers_file_success	
,distinct_customers_reauth	
,distinct_customers_called_intuit	
,distinct_customers_called_intuit_within_7_days	
,distinct_customers_delivered	
,distinct_customers_open	
,distinct_customers_click	
,distinct_customers_bounce	
,distinct_customers_sms_textback
from
 cgan_ustax_ws.saves_cch_004_aggr_outreach_type WHERE TAX_YEAR= '2025'
 UNION all 	
 select
 outreach_type	
,TAX_YEAR	 as tax_year	
,total_touchpoints	
,distinct_csos	
,distinct_customers	
,total_touchpoints_email	
,total_touchpoints_sms	
,total_touchpoints_push	
,total_touchpoints_epc	
,total_touchpoints_prc	
,distinct_customers_email	
,distinct_customers_sms	
,distinct_customers_push	
,distinct_customers_epc	
,distinct_customers_prc	
,distinct_customers_start	
,distinct_customers_complete	
,distinct_customers_reject	
,distinct_customers_file_success	
,distinct_customers_reauth	
,distinct_customers_called_intuit	
,distinct_customers_called_intuit_within_7_days	
,distinct_customers_delivered	
,distinct_customers_open	
,distinct_customers_click	
,distinct_customers_bounce	
,distinct_customers_sms_textback
from cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty24 ;*/

/*DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty25_aggr;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty25_aggr
USING PARQUET AS
WITH base AS (
    SELECT 
        outreach_type, tax_year, total_touchpoints, distinct_csos, distinct_customers,
        total_touchpoints_email, total_touchpoints_sms, total_touchpoints_push,
        total_touchpoints_epc, total_touchpoints_prc, distinct_customers_email,
        distinct_customers_sms, distinct_customers_push, distinct_customers_epc,
        distinct_customers_prc, distinct_customers_start, distinct_customers_complete,
        distinct_customers_reject, distinct_customers_file_success, distinct_customers_reauth,
        distinct_customers_called_intuit, distinct_customers_called_intuit_within_7_days,
        distinct_customers_delivered, distinct_customers_open, distinct_customers_click,
        distinct_customers_bounce, distinct_customers_sms_textback
    FROM cgan_ustax_ws.saves_cch_004_aggr_outreach_type
    WHERE tax_year = '2025'

    UNION ALL

    SELECT 
        outreach_type, tax_year, total_touchpoints, distinct_csos, distinct_customers,
        total_touchpoints_email, total_touchpoints_sms, total_touchpoints_push,
        total_touchpoints_epc, total_touchpoints_prc, distinct_customers_email,
        distinct_customers_sms, distinct_customers_push, distinct_customers_epc,
        distinct_customers_prc, distinct_customers_start, distinct_customers_complete,
        distinct_customers_reject, distinct_customers_file_success, distinct_customers_reauth,
        distinct_customers_called_intuit, distinct_customers_called_intuit_within_7_days,
        distinct_customers_delivered, distinct_customers_open, distinct_customers_click,
        distinct_customers_bounce, distinct_customers_sms_textback
    FROM cgan_ustax_ws.saves_cch_004_aggr_outreach_type_ty24
),

pivoted AS (
    SELECT
        outreach_type,

        -- 2024 values
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints               END) AS total_touchpoints_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_csos                   END) AS distinct_csos_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers              END) AS distinct_customers_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_email         END) AS total_touchpoints_email_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_sms           END) AS total_touchpoints_sms_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_push          END) AS total_touchpoints_push_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_epc           END) AS total_touchpoints_epc_2024,
        MAX(CASE WHEN tax_year = '2024' THEN total_touchpoints_prc           END) AS total_touchpoints_prc_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_email        END) AS distinct_customers_email_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_sms          END) AS distinct_customers_sms_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_push         END) AS distinct_customers_push_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_epc          END) AS distinct_customers_epc_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_prc          END) AS distinct_customers_prc_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_start        END) AS distinct_customers_start_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_complete     END) AS distinct_customers_complete_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_reject       END) AS distinct_customers_reject_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_file_success END) AS distinct_customers_file_success_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_reauth       END) AS distinct_customers_reauth_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_called_intuit               END) AS distinct_customers_called_intuit_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_called_intuit_within_7_days END) AS distinct_customers_called_intuit_7d_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_delivered    END) AS distinct_customers_delivered_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_open         END) AS distinct_customers_open_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_click        END) AS distinct_customers_click_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_bounce       END) AS distinct_customers_bounce_2024,
        MAX(CASE WHEN tax_year = '2024' THEN distinct_customers_sms_textback END) AS distinct_customers_sms_textback_2024,

        -- 2025 values
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints               END) AS total_touchpoints_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_csos                   END) AS distinct_csos_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers              END) AS distinct_customers_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_email         END) AS total_touchpoints_email_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_sms           END) AS total_touchpoints_sms_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_push          END) AS total_touchpoints_push_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_epc           END) AS total_touchpoints_epc_2025,
        MAX(CASE WHEN tax_year = '2025' THEN total_touchpoints_prc           END) AS total_touchpoints_prc_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_email        END) AS distinct_customers_email_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_sms          END) AS distinct_customers_sms_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_push         END) AS distinct_customers_push_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_epc          END) AS distinct_customers_epc_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_prc          END) AS distinct_customers_prc_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_start        END) AS distinct_customers_start_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_complete     END) AS distinct_customers_complete_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_reject       END) AS distinct_customers_reject_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_file_success END) AS distinct_customers_file_success_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_reauth       END) AS distinct_customers_reauth_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_called_intuit               END) AS distinct_customers_called_intuit_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_called_intuit_within_7_days END) AS distinct_customers_called_intuit_7d_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_delivered    END) AS distinct_customers_delivered_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_open         END) AS distinct_customers_open_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_click        END) AS distinct_customers_click_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_bounce       END) AS distinct_customers_bounce_2025,
        MAX(CASE WHEN tax_year = '2025' THEN distinct_customers_sms_textback END) AS distinct_customers_sms_textback_2025

    FROM base
    GROUP BY outreach_type
)

SELECT
    outreach_type,

    -- Total Touchpoints
    total_touchpoints_2024,
    total_touchpoints_2025,
    ROUND((total_touchpoints_2025 - total_touchpoints_2024) / NULLIF(total_touchpoints_2024, 0) * 100, 1) AS total_touchpoints_yoy_pct,

    -- Distinct CSOs
    distinct_csos_2024,
    distinct_csos_2025,
    ROUND((distinct_csos_2025 - distinct_csos_2024) / NULLIF(distinct_csos_2024, 0) * 100, 1) AS distinct_csos_yoy_pct,

    -- Distinct Customers
    distinct_customers_2024,
    distinct_customers_2025,
    ROUND((distinct_customers_2025 - distinct_customers_2024) / NULLIF(distinct_customers_2024, 0) * 100, 1) AS distinct_customers_yoy_pct,

    -- Touchpoints by Channel
    total_touchpoints_email_2024, total_touchpoints_email_2025,
    ROUND((total_touchpoints_email_2025 - total_touchpoints_email_2024) / NULLIF(total_touchpoints_email_2024, 0) * 100, 1) AS total_touchpoints_email_yoy_pct,

    total_touchpoints_sms_2024, total_touchpoints_sms_2025,
    ROUND((total_touchpoints_sms_2025 - total_touchpoints_sms_2024) / NULLIF(total_touchpoints_sms_2024, 0) * 100, 1) AS total_touchpoints_sms_yoy_pct,

    total_touchpoints_push_2024, total_touchpoints_push_2025,
    ROUND((total_touchpoints_push_2025 - total_touchpoints_push_2024) / NULLIF(total_touchpoints_push_2024, 0) * 100, 1) AS total_touchpoints_push_yoy_pct,

    total_touchpoints_epc_2024, total_touchpoints_epc_2025,
    ROUND((total_touchpoints_epc_2025 - total_touchpoints_epc_2024) / NULLIF(total_touchpoints_epc_2024, 0) * 100, 1) AS total_touchpoints_epc_yoy_pct,

    total_touchpoints_prc_2024, total_touchpoints_prc_2025,
    ROUND((total_touchpoints_prc_2025 - total_touchpoints_prc_2024) / NULLIF(total_touchpoints_prc_2024, 0) * 100, 1) AS total_touchpoints_prc_yoy_pct,

    -- Distinct Customers by Channel
    distinct_customers_email_2024, distinct_customers_email_2025,
    ROUND((distinct_customers_email_2025 - distinct_customers_email_2024) / NULLIF(distinct_customers_email_2024, 0) * 100, 1) AS distinct_customers_email_yoy_pct,

    distinct_customers_sms_2024, distinct_customers_sms_2025,
    ROUND((distinct_customers_sms_2025 - distinct_customers_sms_2024) / NULLIF(distinct_customers_sms_2024, 0) * 100, 1) AS distinct_customers_sms_yoy_pct,

    distinct_customers_push_2024, distinct_customers_push_2025,
    ROUND((distinct_customers_push_2025 - distinct_customers_push_2024) / NULLIF(distinct_customers_push_2024, 0) * 100, 1) AS distinct_customers_push_yoy_pct,

    distinct_customers_epc_2024, distinct_customers_epc_2025,
    ROUND((distinct_customers_epc_2025 - distinct_customers_epc_2024) / NULLIF(distinct_customers_epc_2024, 0) * 100, 1) AS distinct_customers_epc_yoy_pct,

    distinct_customers_prc_2024, distinct_customers_prc_2025,
    ROUND((distinct_customers_prc_2025 - distinct_customers_prc_2024) / NULLIF(distinct_customers_prc_2024, 0) * 100, 1) AS distinct_customers_prc_yoy_pct,

    -- Funnel Stages
    distinct_customers_start_2024, distinct_customers_start_2025,
    ROUND((distinct_customers_start_2025 - distinct_customers_start_2024) / NULLIF(distinct_customers_start_2024, 0) * 100, 1) AS distinct_customers_start_yoy_pct,

    distinct_customers_complete_2024, distinct_customers_complete_2025,
    ROUND((distinct_customers_complete_2025 - distinct_customers_complete_2024) / NULLIF(distinct_customers_complete_2024, 0) * 100, 1) AS distinct_customers_complete_yoy_pct,

    distinct_customers_reject_2024, distinct_customers_reject_2025,
    ROUND((distinct_customers_reject_2025 - distinct_customers_reject_2024) / NULLIF(distinct_customers_reject_2024, 0) * 100, 1) AS distinct_customers_reject_yoy_pct,

    distinct_customers_file_success_2024, distinct_customers_file_success_2025,
    ROUND((distinct_customers_file_success_2025 - distinct_customers_file_success_2024) / NULLIF(distinct_customers_file_success_2024, 0) * 100, 1) AS distinct_customers_file_success_yoy_pct,

    distinct_customers_reauth_2024, distinct_customers_reauth_2025,
    ROUND((distinct_customers_reauth_2025 - distinct_customers_reauth_2024) / NULLIF(distinct_customers_reauth_2024, 0) * 100, 1) AS distinct_customers_reauth_yoy_pct,

    -- Support & Engagement
    distinct_customers_called_intuit_2024, distinct_customers_called_intuit_2025,
    ROUND((distinct_customers_called_intuit_2025 - distinct_customers_called_intuit_2024) / NULLIF(distinct_customers_called_intuit_2024, 0) * 100, 1) AS distinct_customers_called_intuit_yoy_pct,

    distinct_customers_called_intuit_7d_2024, distinct_customers_called_intuit_7d_2025,
    ROUND((distinct_customers_called_intuit_7d_2025 - distinct_customers_called_intuit_7d_2024) / NULLIF(distinct_customers_called_intuit_7d_2024, 0) * 100, 1) AS distinct_customers_called_intuit_7d_yoy_pct,

    -- Email Engagement
    distinct_customers_delivered_2024, distinct_customers_delivered_2025,
    ROUND((distinct_customers_delivered_2025 - distinct_customers_delivered_2024) / NULLIF(distinct_customers_delivered_2024, 0) * 100, 1) AS distinct_customers_delivered_yoy_pct,

    distinct_customers_open_2024, distinct_customers_open_2025,
    ROUND((distinct_customers_open_2025 - distinct_customers_open_2024) / NULLIF(distinct_customers_open_2024, 0) * 100, 1) AS distinct_customers_open_yoy_pct,

    distinct_customers_click_2024, distinct_customers_click_2025,
    ROUND((distinct_customers_click_2025 - distinct_customers_click_2024) / NULLIF(distinct_customers_click_2024, 0) * 100, 1) AS distinct_customers_click_yoy_pct,

    distinct_customers_bounce_2024, distinct_customers_bounce_2025,
    ROUND((distinct_customers_bounce_2025 - distinct_customers_bounce_2024) / NULLIF(distinct_customers_bounce_2024, 0) * 100, 1) AS distinct_customers_bounce_yoy_pct,

    -- SMS Textback
    distinct_customers_sms_textback_2024, distinct_customers_sms_textback_2025,
    ROUND((distinct_customers_sms_textback_2025 - distinct_customers_sms_textback_2024) / NULLIF(distinct_customers_sms_textback_2024, 0) * 100, 1) AS distinct_customers_sms_textback_yoy_pct

FROM pivoted
ORDER BY total_touchpoints_2025 DESC NULLS LAST;


/*
--only looking at touchpoints --- exclude web_hook 
DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_tax_year_tytd;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_tax_year_tytd as
with cy as (
select
  tax_year
, tax_day

--Metrics
, min(date_outreach_start_pst) as date_outreach_start
, max(date_outreach_start_pst) as date_outreach_end
from cgan_ustax_ws.saves_cch_003_append_diwm
where flag_tax_year_current = 1
    and outreach_channel != 'web_hook'
group by 1,2
)  
, py as (
select distinct a.*
from cgan_ustax_ws.saves_cch_003_append_diwm as a 
inner join cy 
    on a.tax_day <= cy.tax_day
    and a.flag_tax_year_current = 0  
    and a.outreach_channel != 'web_hook'
)  
select 
  tax_year
, 'TYTD' as totals_aggregated_by

--Metrics
, min(date_outreach_start_pst) as date_outreach_start
, max(date_outreach_start_pst) as date_outreach_end
, count(*) as total_touchpoints
, count(case when outreach_channel = 'email' then pseudonym_id end) as total_touchpoints_email
, count(case when outreach_channel = 'sms' then pseudonym_id end) as total_touchpoints_sms
, count(case when outreach_channel = 'push' then pseudonym_id end) as total_touchpoints_push
, count(case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as total_touchpoints_epc
, count(case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as total_touchpoints_prc
, count(distinct pseudonym_id) as distinct_customers
, count(distinct case when outreach_channel = 'email' then pseudonym_id end) as distinct_customers_email
, count(distinct case when outreach_channel = 'sms' then pseudonym_id end) as distinct_customers_sms
, count(distinct case when outreach_channel = 'push' then pseudonym_id end) as distinct_customers_push
, count(distinct case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as distinct_customers_epc
, count(distinct case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as distinct_customers_prc
, count(distinct case when flag_start  = 1 then pseudonym_id end) as distinct_customers_start
, count(distinct case when flag_complete  = 1 then pseudonym_id end) as distinct_customers_complete
, count(distinct case when flag_reject  = 1 then pseudonym_id end) as distinct_customers_reject
, count(distinct case when flag_file_success  = 1 then pseudonym_id end) as distinct_customers_file_success
, count(distinct case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(distinct case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(distinct case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(distinct case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(distinct case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(distinct case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(distinct case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(distinct case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from cgan_ustax_ws.saves_cch_003_append_diwm
where flag_tax_year_current = 1
  and outreach_channel != 'web_hook'
group by 1

union

select 
  tax_year
, 'TYTD' as totals_aggregated_by

--Metrics
, min(date_outreach_start_pst) as date_outreach_start
, max(date_outreach_start_pst) as date_outreach_end
, count(*) as total_touchpoints
, count(case when outreach_channel = 'email' then pseudonym_id end) as total_touchpoints_email
, count(case when outreach_channel = 'sms' then pseudonym_id end) as total_touchpoints_sms
, count(case when outreach_channel = 'push' then pseudonym_id end) as total_touchpoints_push
, count(case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as total_touchpoints_epc
, count(case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as total_touchpoints_prc
, count(distinct pseudonym_id) as distinct_customers
, count(distinct case when outreach_channel = 'email' then pseudonym_id end) as distinct_customers_email
, count(distinct case when outreach_channel = 'sms' then pseudonym_id end) as distinct_customers_sms
, count(distinct case when outreach_channel = 'push' then pseudonym_id end) as distinct_customers_push
, count(distinct case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as distinct_customers_epc
, count(distinct case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as distinct_customers_prc
, count(distinct case when flag_start  = 1 then pseudonym_id end) as distinct_customers_start
, count(distinct case when flag_complete  = 1 then pseudonym_id end) as distinct_customers_complete
, count(distinct case when flag_reject  = 1 then pseudonym_id end) as distinct_customers_reject
, count(distinct case when flag_file_success  = 1 then pseudonym_id end) as distinct_customers_file_success
, count(distinct case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(distinct case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(distinct case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(distinct case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(distinct case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(distinct case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(distinct case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(distinct case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from py
group by 1
;

--only looking at touchpoints --- exclude web_hook 
DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_month_tytd;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_month_tytd as
with cy as (
select
  tax_year
, tax_day

--Metrics
, min(date_outreach_start_pst) as date_outreach_start
, max(date_outreach_start_pst) as date_outreach_end
from cgan_ustax_ws.saves_cch_003_append_diwm
where flag_tax_year_current = 1
    and outreach_channel != 'web_hook'
group by 1,2
)  
, py as (
select distinct a.*
from cgan_ustax_ws.saves_cch_003_append_diwm as a 
inner join cy 
    on a.tax_day <= cy.tax_day
    and a.flag_tax_year_current = 0  
    and a.outreach_channel != 'web_hook'
)  
select 
  tax_year
, month(date_outreach_start_pst) as month

--Metrics
, min(date_outreach_start_pst) as date_outreach_start
, max(date_outreach_start_pst) as date_outreach_end
, count(*) as total_touchpoints
, count(case when outreach_channel = 'email' then pseudonym_id end) as total_touchpoints_email
, count(case when outreach_channel = 'sms' then pseudonym_id end) as total_touchpoints_sms
, count(case when outreach_channel = 'push' then pseudonym_id end) as total_touchpoints_push
, count(case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as total_touchpoints_epc
, count(case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as total_touchpoints_prc
, count(distinct pseudonym_id) as distinct_customers
, count(distinct case when outreach_channel = 'email' then pseudonym_id end) as distinct_customers_email
, count(distinct case when outreach_channel = 'sms' then pseudonym_id end) as distinct_customers_sms
, count(distinct case when outreach_channel = 'push' then pseudonym_id end) as distinct_customers_push
, count(distinct case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as distinct_customers_epc
, count(distinct case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as distinct_customers_prc
, count(distinct case when flag_start  = 1 then pseudonym_id end) as distinct_customers_start
, count(distinct case when flag_complete  = 1 then pseudonym_id end) as distinct_customers_complete
, count(distinct case when flag_reject  = 1 then pseudonym_id end) as distinct_customers_reject
, count(distinct case when flag_file_success  = 1 then pseudonym_id end) as distinct_customers_file_success
, count(distinct case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(distinct case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(distinct case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(distinct case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(distinct case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(distinct case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(distinct case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(distinct case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from cgan_ustax_ws.saves_cch_003_append_diwm
where flag_tax_year_current = 1
  and outreach_channel != 'web_hook'
group by 1,2

union

select 
  tax_year
, month(date_outreach_start_pst) as month

--Metrics
, min(date_outreach_start_pst) as date_outreach_start
, max(date_outreach_start_pst) as date_outreach_end
, count(*) as total_touchpoints
, count(case when outreach_channel = 'email' then pseudonym_id end) as total_touchpoints_email
, count(case when outreach_channel = 'sms' then pseudonym_id end) as total_touchpoints_sms
, count(case when outreach_channel = 'push' then pseudonym_id end) as total_touchpoints_push
, count(case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as total_touchpoints_epc
, count(case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as total_touchpoints_prc
, count(distinct pseudonym_id) as distinct_customers
, count(distinct case when outreach_channel = 'email' then pseudonym_id end) as distinct_customers_email
, count(distinct case when outreach_channel = 'sms' then pseudonym_id end) as distinct_customers_sms
, count(distinct case when outreach_channel = 'push' then pseudonym_id end) as distinct_customers_push
, count(distinct case when outreach_channel_subtype = 'expert-placed' then pseudonym_id end) as distinct_customers_epc
, count(distinct case when outreach_channel_subtype = 'pre-recorded' then pseudonym_id end) as distinct_customers_prc
, count(distinct case when flag_start  = 1 then pseudonym_id end) as distinct_customers_start
, count(distinct case when flag_complete  = 1 then pseudonym_id end) as distinct_customers_complete
, count(distinct case when flag_reject  = 1 then pseudonym_id end) as distinct_customers_reject
, count(distinct case when flag_file_success  = 1 then pseudonym_id end) as distinct_customers_file_success
, count(distinct case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(distinct case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(distinct case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(distinct case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(distinct case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(distinct case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(distinct case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(distinct case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from py
group by 1,2
;
*/
