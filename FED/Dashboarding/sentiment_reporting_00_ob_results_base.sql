--216 PV code from https://intuit-e2-570264151593-prd.cloud.databricks.com/editor/notebooks/274412487355266?o=8126228270435530#command/7003588618546723
--217 added email delivered and clicks
--218 add completed date to summary file
--225 erin requested we send email the day after instead of 2 days later so changed to be effective 2.25 in email creation code. will report here on two seperate cohorts
--step 1 append call results from cct to historical file, keeping data only from 2/12 onwards
--310 included non agent handled data and created flag
--319 added table for bayesian analysis to put on dashboard 
--https://intuit-e2-570264151593-prd.cloud.databricks.com/editor/notebooks/808339398635564?o=8126228270435530#command/808339398635647
--320 included in historical file as it was sent to dialer but due to dnc issue we did not send to dialer. exclude 320 from results
--0401 42 onwards two email creatives one original one with pic of survey
--0423 added cc_id to 1st dataset for kyle analysis
DROP TABLE IF EXISTS cgan_ustax_ws.ob_sentiment_call_results_base_ty25;
CREATE TABLE cgan_ustax_ws.ob_sentiment_call_results_base_ty25 AS
SELECT DISTINCT
    r.pseudonym_id,
    r.date_qualified, 
    r.response_id,
    r.test_group,
    r.qualified_auth_id,
    CASE 
        WHEN r.test_group = 'Test' THEN 'B - MP OB & Email' 
        ELSE 'A - (Holdout) No intervention or outreach' 
    END AS recipe,
    CASE 
        WHEN ob_contacted_cct.auth_id IS NOT NULL 
            AND ob_contacted_cct.ob_campaign_disposition_cd = 'HUMAN_ANSWERED' THEN 1 
        ELSE 0 
    END AS ob_call_connected_to_customer,
    ob_contacted_cct.date_sent,
    ob_contacted_cct.agent_handled_flag,
    ob_contacted_cct.cc_id
FROM cgan_ustax_ws.nlac_ob_sentiment_contact_list_ty25 AS r 
LEFT JOIN (
    -- Migrated to care_7216_rpt.rpt_contacts_center: auth_id->customer_auth_id, tax_year->tax_year_nbr,
    -- bu->contact_business_unit_code_str, leg_queue->leg_queue_str, agent_handle_flg->expert_handled_flag,
    -- contact_start_ts->contact_start_utc_ts
    SELECT DISTINCT
        cct.customer_auth_id AS auth_id,
        cct.ob_campaign_disposition_cd,
        MIN(cct.contact_start_utc_ts) AS date_sent,
        MAX(cct.expert_handled_flag) AS agent_handled_flag,
        MIN(cct.cc_id) AS cc_id
    FROM care_7216_rpt.rpt_contacts_center cct
    WHERE cct.tax_year_nbr = 2025
        AND cct.contact_business_unit_code_str = 'cg'
        AND cct.leg_queue_str = 'cg-us_ps_sentiment_campaign'
    GROUP BY 1, 2
) AS ob_contacted_cct
ON CAST(r.qualified_auth_id AS STRING) = CAST(ob_contacted_cct.auth_id AS STRING);


--step 2
--Join to PAM and pick up necessary attributes -- start and complete dates, revenue, sku's for current and prior year. 
--also append sentiment and q2 verbatim from qualtrics as it was not retained on historical file


--survey
DROP TABLE IF EXISTS cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_raw_ty25_hist;
CREATE TABLE cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_raw_ty25_hist AS
select * from 
(
select
          a.responseid as response_id --unique identifier of the actual survey response that the customer submits
        , a.responsesubmitdate as date_end --the timestamp of when the customer submitted the survey
        , a.primaryid as auth_id
        , max(case 
                when q.questionname = 'Q1' AND a.question_response = 'Dont Ask' THEN 'Negative'
                when q.questionname = 'Q1' AND a.question_response = 'Not So Good' THEN 'Neutral'
                when q.questionname = 'Q1' AND a.question_response = 'Happy' THEN 'Positive'
                end) as sentiment
        ,max(case when q.questionname = 'Q1' then q.questiontext end) as q1_survey_question
        ,max(case when q.questionname = 'Q1' then a.question_response end) as q1_response
        , max(case 
	  when q.questionname = 'Q2' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	  when q.questionname = 'Q3' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	  when q.questionname = 'Q4' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	  end) 
	as q2_survey_question
        ,max(case when q.questionname IN ('Q2','Q3','Q4') and a.question_response is not null and trim(a.question_response) != '' then a.question_response end) as q2_response
from ent_qualtrics_dwh.di_qual_survey_questions as q 
left join ent_qualtrics_dwh.di_qual_resp_raw as a
        on q.surveyid = a.surveyid
                and q.questionid = a.question_id
where a.finished = '1' --customer completed the survey
	--Mid-Product survey_id filter
        and a.surveyid = 'SV_e4MDm0UcxcsN98a'
	--customer submitted survey in past  days
        and datediff(cast(current_timestamp as date), cast(responsesubmitdate as date)) <= 365  
group by 
          a.responseid
        , a.responsesubmitdate 
        , a.primaryid 
        , a.product 
        
        , a.surveyid 
        , q.surveyname)
	
where sentiment in ('Negative','Neutral')	
;

-- join historical, survey and pam and email
DROP TABLE IF EXISTS cgan_ustax_ws.ob_sentiment_test_results_base_ty25;
CREATE TABLE cgan_ustax_ws.ob_sentiment_test_results_base_ty25 AS
SELECT *
FROM (
    SELECT DISTINCT
        base.*
        , cy_pam.pseudonym_id AS pam_pseudonym_id
        , h.sentiment
        , h.date_end AS survey_response_ts
        , CASE WHEN h.q2_response IS NOT NULL THEN 1 ELSE 0 END AS q2_has_verbatim
        , ob_call_connected_to_customer AS  flag_completed_call 
        , agent_handled_flag AS call_in_cct_table
        , cy_pam.total_revenue
        , cy_pam.tto_segment_rollup 
        , cy_pam.tto_segment_detail
        , cy_pam.first_start_date
        , cy_pam.first_completed_date
        , cy_pam.first_start_date_adj
        , cy_pam.first_completed_date_adj
        , cy_pam.completed_sku AS cy_completed_sku
        , cy_pam.completed_sku_rollup AS cy_completed_sku_rollup
        , cy_pam.start_sku AS cy_start_sku
        , cy_pam.start_sku_rollup AS cy_start_sku_rollup

        -- Email Engagement  
        , CASE WHEN email.pseudonym_id IS NOT NULL THEN 1 ELSE 0 END AS email_sent
        , email.em_clicked_flag

        , ROW_NUMBER() OVER (PARTITION BY base.pseudonym_id ORDER BY date_qualified) AS rownum_pseudo
        , ROW_NUMBER() OVER (PARTITION BY base.pseudonym_id ORDER BY test_group DESC) AS rownum_group

    FROM cgan_ustax_ws.ob_sentiment_call_results_base_ty25 AS base
    LEFT JOIN cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_raw_ty25_hist AS h 
        ON base.response_id = h.response_id
    LEFT JOIN tax_rpt.product_analytics_master AS cy_pam
        ON CAST(base.qualified_auth_id AS STRING) = CAST(cy_pam.auth_id AS STRING) 
        AND cy_pam.tax_year = 2025
    LEFT JOIN cgan_ustax_ws.sentiment_ty25_braze_em AS email
        ON base.pseudonym_id = email.pseudonym_id
)
WHERE rownum_group = 1 
    AND rownum_pseudo = 1;

--Step 3 Create aggregate table for final reporting table to access all customers in the test/holdout and their associated outreach flags.
--this will be used for tableau reporting
--added using hive so that table can be accessed in tableau

DROP TABLE IF EXISTS cgan_ustax_ws.ob_sentiment_test_results_aggr_ty25;
CREATE TABLE cgan_ustax_ws.ob_sentiment_test_results_aggr_ty25  using hive AS
SELECT
    test_group,
    recipe,
    date_qualified,
    flag_completed_call,
    CAST(date_sent AS DATE) AS ob_call_date,
    sentiment,
    q2_has_verbatim,
    call_in_cct_table,
    tto_segment_rollup,
    tto_segment_detail,
    -- CASE
    --     WHEN date_qualified <= DATE '2025-02-26' THEN 'Cohort 1'
    --     ELSE 'Cohort 2'
    -- END AS cohort_group,
    cy_completed_sku,
    cy_completed_sku_rollup,
    cy_start_sku,
    cy_start_sku_rollup,
    CAST(first_completed_date AS DATE) AS completed_date,
    -- customers / call funnel
    COUNT(DISTINCT pseudonym_id) AS total_customers,
    COUNT(DISTINCT CASE WHEN flag_completed_call = 1 THEN pseudonym_id END) AS connect,
    -- high-level s2c
    COUNT(DISTINCT CASE WHEN first_start_date IS NOT NULL THEN pseudonym_id END) AS starts,
    COUNT(DISTINCT CASE WHEN first_completed_date IS NOT NULL THEN pseudonym_id END) AS completes,
    SUM(total_revenue) AS total_revenue,
    SUM(email_sent) AS emails_delivered,
    SUM(em_clicked_flag) AS emails_clicked
FROM cgan_ustax_ws.ob_sentiment_test_results_base_ty25
WHERE first_start_date IS NOT NULL
GROUP BY
    test_group,
    recipe,
    date_qualified,
    flag_completed_call,
    CAST(date_sent AS DATE),
    sentiment,
    q2_has_verbatim,
    call_in_cct_table,
    tto_segment_rollup,
    tto_segment_detail,
    -- CASE
    --     WHEN date_qualified <= DATE '2025-02-26' THEN 'Cohort 1'
    --     ELSE 'Cohort 2'
    -- END,
    cy_completed_sku,
    cy_completed_sku_rollup,
    cy_start_sku,
    cy_start_sku_rollup,
    CAST(first_completed_date AS DATE);
