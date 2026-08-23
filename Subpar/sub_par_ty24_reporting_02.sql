DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_reporting_02_append;

CREATE TABLE cgan_ustax_ws.sub_par_ty24_reporting_02_append AS
SELECT 
    a.pseudonym_id,
    a.auth_id,
    a.issue_type,
    a.cell,
    a.date_issue,
    a.datetime_qualified,
    a.date_qualified,
    --a.campaign_name,
    a.mpm,
  --  a.copy_type,
    a.dt,
    a.mpm_cell,
    case when cohort='late night callback' and date(date_qualified)<='2025-02-10' then 1 else 0 end as discard,
    -- Email details
    a.flag_test, 
    a.test_group,
    a.test_window,
    a.canvas_name,
    a.canvas_id,
    a.canvas_step_name,
    a.creative_group,
    a.recipe,
    a.cohort,

    -- Date email was sent or delivered  
    a.dt_em_sent,
    a.dt_em_delivered,
    a.flag_delivered,
    a.flag_click,
    a.flag_click_unsubscribe,

    -- PAM details
    pam.tax_year,
    pam.first_fed_efile_accepted_date,
    pam.first_print_to_mail_date,
    pam.completed_sku,
    pam.completed_sku_rollup,
    pam.first_completed_date,
    pam.tto_segment_rollup,
    pam.tto_segment,
    pam.total_revenue AS pam_total_revenue,

    --new for ty24 add row number for pseudonym id
     ROW_NUMBER() OVER (PARTITION BY a.pseudonym_id ORDER BY date_qualified) AS rownum_pseudo,

    -- Completion flag
    MAX(IF(pam.first_completed_date IS NOT NULL, 1, 0)) OVER (PARTITION BY a.pseudonym_id) AS flag_complete,

    -- Date of completion
    MAX(pam.first_completed_date) OVER (PARTITION BY a.pseudonym_id) AS date_completed,

    -- Total revenue per pseudonym_id
    MAX(pam.total_revenue) OVER (PARTITION BY a.pseudonym_id) AS total_revenue,

    -- Re-authentication flag
    MAX(IF(msam.SESSION_AUTH_TIMESTAMP IS NOT NULL 
           AND CAST(a.date_qualified AS DATE) <= CAST(msam.SESSION_AUTH_TIMESTAMP AS DATE), 
           1, 0)) OVER (PARTITION BY a.pseudonym_id) AS flag_reauth,

    -- Completion within 7-day window
    MAX(IF(pam.first_completed_date IS NOT NULL
           AND DATEDIFF(CAST(pam.first_completed_date AS DATE), CAST(a.date_qualified AS DATE)) BETWEEN 0 AND 7, 
           1, 0)) OVER (PARTITION BY a.pseudonym_id) AS flag_complete_within_7_days,

    MAX(IF(pam.first_completed_date IS NOT NULL
           AND DATEDIFF(CAST(pam.first_completed_date AS DATE), CAST(a.date_qualified AS DATE)) BETWEEN 0 AND 7, 
           pam.first_completed_date, NULL)) OVER (PARTITION BY a.pseudonym_id) AS date_completed_within_7_days,

    MAX(IF(pam.first_completed_date IS NOT NULL
           AND DATEDIFF(CAST(pam.first_completed_date AS DATE), CAST(a.date_qualified AS DATE)) BETWEEN 0 AND 7, 
           pam.total_revenue, NULL)) OVER (PARTITION BY a.pseudonym_id) AS total_revenue_within_7_days,

    -- Re-authentication within 7 days
    MAX(IF(msam.SESSION_AUTH_TIMESTAMP IS NOT NULL
           AND DATEDIFF(CAST(msam.SESSION_AUTH_TIMESTAMP AS DATE), CAST(a.date_qualified AS DATE)) BETWEEN 0 AND 7, 
           1, 0)) OVER (PARTITION BY a.pseudonym_id) AS flag_reauth_within_7_days,

    -- Refund or balance due flag
    CASE 
        WHEN refund.amount_refund IS NULL THEN NULL
        WHEN refund.amount_refund > 0 THEN 'Refund'
        WHEN refund.amount_refund <= 0 THEN 'Bal Due' 
        ELSE NULL 
    END AS refund_bal_due_flag

FROM cgan_ustax_ws.sub_par_ty24_reporting_01_braze_audience AS a
LEFT JOIN tax_rpt.product_analytics_master AS pam
    ON a.pseudonym_id = pam.pseudonym_id
    AND pam.tax_year = 2024
LEFT JOIN tax_rpt.MARKETING_SESSION_ANALYTICS_MASTER AS msam
    ON CAST(a.auth_id AS STRING) = CAST(msam.auth_id AS STRING) 
    AND msam.tax_year = 2024 
LEFT JOIN tax_src.agg_taxml AS refund
    ON CAST(a.auth_id AS STRING) = CAST(refund.auth_id AS STRING)
    AND refund.tax_year = 2024;


--This step aggregates customers for the final reporting view
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_reporting_02_final;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_reporting_02_final AS
select 
  a.issue_type
, a.cell
, a.date_issue
, a.datetime_qualified
, a.date_qualified
, a.mpm
--, a.copy_type
, a.dt
, a.mpm_cell
, a.creative_group
, a.recipe
, a.cohort

--email details
, a.flag_test --if customer gets email, should be in test group
, a.test_group --if customer gets email, should be in test group
, a.test_window

--pam
, tax_year
, completed_sku
, completed_sku_rollup
, tto_segment_rollup
, tto_segment

--refund/bal due
, refund_bal_due_flag   

, count(pseudonym_id) as total_records
, count(distinct pseudonym_id) as customers
, count(distinct case when flag_delivered = 1 then pseudonym_id end) as em_delivered
, count(distinct case when flag_click = 1 then pseudonym_id end) as em_clicks
, count(distinct case when flag_click_unsubscribe = 1 then pseudonym_id end) as em_unsubscribes
, count(distinct case when flag_reauth = 1 then pseudonym_id end) as flag_reauth
, count(distinct case when flag_complete = 1 then pseudonym_id end) as flag_complete --complete within 7 days of outreach
, count(distinct case when first_completed_date is not null then pseudonym_id end) as flag_complete_all_season --customers that completed at any point in season
, sum(case when rownum_pseudo=1 then total_revenue else 0 end) as total_revenue

from cgan_ustax_ws.sub_par_ty24_reporting_02_append as a 
--where discard=0
group by 
  a.issue_type
, a.cell
, a.date_issue
, a.datetime_qualified
, a.date_qualified
, a.mpm
--, a.copy_type
, a.dt
, a.mpm_cell
, a.creative_group
, a.recipe
, a.cohort

--email details
, a.flag_test --if customer gets email, should be in test group
, a.test_group --if customer gets email, should be in test group
, a.test_window

--pam
, tax_year
, completed_sku
, completed_sku_rollup
, tto_segment_rollup
, tto_segment

--refund/bal due
, refund_bal_due_flag  
;

