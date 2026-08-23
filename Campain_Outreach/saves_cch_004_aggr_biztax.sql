DROP TABLE IF EXISTS cgan_ustax_ws.saves_cch_004_aggr_biztax;
CREATE TABLE cgan_ustax_ws.saves_cch_004_aggr_biztax as
select 

--Campaign smartsheet attributes
  Type as outreach_type 
, Driver as outreach_driver
, Priority as outreach_priority
, Product as outreach_product
, "Campaign Name" as campaign_name
, Status as outreach_status
, Hypothesis as outreach_hypothesis
, CSO as outreach_cso
, ContactID as outreach_contactid
, "Send Schedule" as outreach_send_schedule
, "Link to Content (Email/Call Script" as outreach_content_link
, "Added to IEP Expert Outreach Hub?" as outreach_added_to_iep_expert_outreach_hub
, "Test?" as outreach_test
, "Test Recipes" as outreach_test_recipe
, "Customer Cohort" as outreach_customer_cohort
, "Refund Trigger" as outreach_refund_trigger
, "Financial Impact" as outreach_finance_impact
, "Email Ops Notes" as outreach_email_ops_notes
, "Requestor" as outreach_requestor
, Org as outreach_org
, "Slack Channel" as outreach_slack_channel
, "Date of SR Incident" as date_sr_incident
, "Time of SR Incident (Pacific)" as time_sr_incident
, "Created" as timestamp_added_to_smartsheet

--Touchpoint attributes
, timestamp_outreach_start_pst
, date_outreach_start_pst
, outreach_channel
, outreach_channel_type
, outreach_channel_subtype
, outreach_campaign_id_primary
, outreach_campaign_name
, outreach_campaign_id_secondary

, tax_year

--Customer Attributes
, start_sku_incorporated
, start_sku_sp
, start_sku_rollup_sp
, current_sku_incorporated
, completed_sku_incorporated
, completed_sku_sp

--Metrics
, count(*) as total_touchpoints
, count(distinct pseudonym_id) as distinct_customers
, count(case when flag_start_incorporated  = 1 then pseudonym_id end) as distinct_customers_start_incorporated
, count(case when flag_start_sp  = 1 then pseudonym_id end) as distinct_customers_start_sp
, count(case when flag_complete_incorporated  = 1 then pseudonym_id end) as distinct_customers_complete_incorporated
, count(case when flag_complete_sp  = 1 then pseudonym_id end) as distinct_customers_complete_sp
, count(case when flag_reauth  = 1 then pseudonym_id end) as distinct_customers_reauth
, count(case when flag_called_intuit = 1 then pseudonym_id end) as distinct_customers_called_intuit
, count(case when flag_called_within_7_days  = 1 then pseudonym_id end) as distinct_customers_called_intuit_within_7_days
, count(case when flag_outreach_delivered = 1 then pseudonym_id end) as distinct_customers_delivered
, count(case when outreach_engagement_type_primary = 'flag_open' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_open
, count(case when outreach_engagement_type_primary = 'flag_click' and outreach_engagement_value_primary = 1 then pseudonym_id end) as distinct_customers_click
, count(case when outreach_engagement_type_secondary = 'flag_bounce' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_bounce
, count(case when outreach_engagement_type_secondary = 'flag_sms_textback' and outreach_engagement_value_secondary = 1 then pseudonym_id end) as distinct_customers_sms_textback
from cgan_ustax_ws.saves_cch_003_append_biztax
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39
;
