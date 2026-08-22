drop table if exists cgan_ustax_ws.Saves_efile_reject_ty25_01_base;
create table cgan_ustax_ws.Saves_efile_reject_ty25_01_base as
-- =====================================================================
-- E-file reject TY25 — AJO analytics outcomes
-- Grain: one row per qualified person (pseudonym_id / auth_id) from the
--        AJO analytics destination. Every CTE below is pre-aggregated to
--        its own key so no join can fan the result out.
-- =====================================================================
WITH base AS (                              -- qualified population (the spine)
    SELECT
        pseudonym_id
      , CAST(auth_id AS STRING)                                            AS auth_id
      , eligible_date_min_pst                                             AS date_qualified
      , CAST(eligible_date_min_pst AS DATE)                               AS date_qualified_dt
      , CASE WHEN entered_analytics_holdout = 1 THEN 'Holdout' ELSE 'Test' END AS test_group
    FROM cgan_ustax_ws.Saves_efile_reject_ty25_00_ajo_analytics_destination
    WHERE auth_id IS NOT NULL
)

-- Braze email: keep ONE row per pseudonym (earliest send) so it can't fan out.
, email AS (
    SELECT
        pseudonym_id
      , email_recipe_rollup
      , error_code                                                         AS email_error_code
      , date_em_sent
    FROM (
        SELECT
            em.*
          , ROW_NUMBER() OVER (
                PARTITION BY em.pseudonym_id
                ORDER BY em.date_em_sent                                   -- swap to DESC for latest email
            ) AS rn
        FROM cgan_ustax_ws.Saves_efile_reject_ty25_00_braze_em em
    )
    WHERE rn = 1
)

-- Product analytics: naturally one row per pseudonym per tax year.
, product AS (
    SELECT
        pseudonym_id
      , DATE(first_fed_efile_attempted_date_adj)                          AS date_fed_efile_attempt
      , DATE(first_fed_efile_rejected_date)                               AS date_fed_efile_reject
      , tto_segment_rollup
      , completed_sku_rollup
      , first_fed_efile_attempted_date_adj
      , first_fed_efile_rejected_date
    FROM tax_rpt.product_analytics_master
    WHERE tax_year = 2025
)

-- Monetization: one row per auth per tax year.
, monetization AS (
    SELECT
        CAST(auth_id AS STRING)                                           AS auth_id
      , rt_attach_flag
      , rt_revenue_flag
      , total_refund_transfer_revenue
      , fde_attach_flag
      , total_fde_revenue
      , total_revenue
    FROM tax_rpt.monetization_analytics_master
    WHERE tax_year = 2025
)

-- Successful federal filing ON/AFTER the person qualified.
-- Aggregated to ONE row per auth_id (replaces the fan-out join + window MIN).
, fed_filing_success AS (
    SELECT
        b.auth_id
      , MIN(CAST(f.filingStatusDate AS DATE))                             AS date_fed_file_success
      , 1                                                                  AS flag_file_success
    FROM base b
    JOIN incometax_taxfiling_filing.filing f
      ON CAST(f.taxFilerAuthId AS STRING) = b.auth_id
     AND f.taxYear      = 2025
     AND f.filingType   = 'IRS-IIT-FILING'
     AND f.filingStatus IN ('FILED_PRINT', 'SUCCEEDED_AGENCY')
     AND CAST(f.filingStatusDate AS DATE) >= b.date_qualified_dt
    GROUP BY b.auth_id
)

-- Suppression set: filed successfully BEFORE they qualified (anti-join set).
, filed_before_qualify AS (
    SELECT DISTINCT b.auth_id
    FROM base b
    JOIN incometax_taxfiling_filing.filing f
      ON CAST(f.taxFilerAuthId AS STRING) = b.auth_id
     AND f.taxYear      = 2025
     AND f.filingType   = 'IRS-IIT-FILING'
     AND f.filingStatus IN ('FILED_PRINT', 'SUCCEEDED_AGENCY')
     AND CAST(f.filingStatusDate AS DATE) < b.date_qualified_dt
)

-- Re-auth: a marketing session on/after qualification (flag only, so DISTINCT).
, reauth AS (
    SELECT DISTINCT b.auth_id
    FROM base b
    JOIN tax_rpt.marketing_session_analytics_master msam
      ON CAST(msam.auth_id AS STRING) = b.auth_id
     AND msam.tax_year = 2025
     AND b.date_qualified_dt <= DATE(FROM_UTC_TIMESTAMP(msam.session_auth_timestamp, 'America/Los_Angeles'))
)

SELECT
    base.pseudonym_id
  , base.auth_id
  , base.date_qualified
  , base.test_group

    -- Email
  , email.email_recipe_rollup
  , email.email_error_code
  , CASE WHEN email.pseudonym_id IS NOT NULL THEN 1 ELSE 0 END            AS flag_email
  , email.date_em_sent

    -- Filing outcomes
  , product.date_fed_efile_attempt
  , fs.date_fed_file_success
  , product.date_fed_efile_reject
  , product.tto_segment_rollup
  , product.completed_sku_rollup

    -- Monetization
  , mon.rt_attach_flag
  , mon.rt_revenue_flag
  , mon.total_refund_transfer_revenue
  , mon.fde_attach_flag
  , mon.total_fde_revenue
  , mon.total_revenue

    -- Flags
  , CASE WHEN reauth.auth_id IS NOT NULL                    THEN 1 ELSE 0 END AS flag_reauth
  , CASE WHEN product.first_fed_efile_attempted_date_adj IS NOT NULL THEN 1 ELSE 0 END AS flag_file_attempt
  , CASE WHEN product.first_fed_efile_rejected_date IS NOT NULL      THEN 1 ELSE 0 END AS flag_efile_rejected
  , COALESCE(fs.flag_file_success, 0)                                    AS flag_file_succes

FROM base
LEFT JOIN email               ON base.pseudonym_id = email.pseudonym_id
LEFT JOIN product             ON base.pseudonym_id = product.pseudonym_id
LEFT JOIN monetization  mon   ON base.auth_id      = mon.auth_id
LEFT JOIN fed_filing_success fs ON base.auth_id    = fs.auth_id
LEFT JOIN reauth              ON base.auth_id      = reauth.auth_id
LEFT JOIN filed_before_qualify sup ON base.auth_id = sup.auth_id
WHERE sup.auth_id IS NULL      -- suppress anyone who filed before qualifying
AND base.auth_id IS NOT NULL
;              
drop table if exists cgan_ustax_ws.Saves_efile_reject_ty25_01_base_aggr;
create table cgan_ustax_ws.Saves_efile_reject_ty25_01_base_aggr
USING PARQUET AS
SELECT 
    test_group,
    email_recipe_rollup,
    email_error_code,
    date_qualified,
    date_fed_efile_attempt,
    date_fed_file_success,
    date_fed_efile_reject,
    tto_segment_rollup,
    completed_sku_rollup,
    flag_email,
    rt_attach_flag,
    rt_revenue_flag,
    fde_attach_flag,
    COUNT(*)                                                                          AS total_records,
    COUNT(DISTINCT pseudonym_id)                                                      AS total_customers,
    COUNT(DISTINCT CASE WHEN flag_reauth = 1            THEN pseudonym_id END)        AS total_reauth,
    COUNT(DISTINCT CASE WHEN flag_file_attempt = 1      THEN pseudonym_id END)        AS total_file_attempt,
    COUNT(DISTINCT CASE WHEN flag_file_succes = 1      THEN pseudonym_id END)        AS total_file_success,
    COUNT(DISTINCT CASE WHEN flag_efile_rejected = 1    THEN pseudonym_id END)        AS total_efile_rejected,
    COUNT(DISTINCT CASE WHEN rt_attach_flag = 1         THEN pseudonym_id END)        AS total_refund_transfer,
    COUNT(DISTINCT CASE WHEN rt_revenue_flag = 1        THEN pseudonym_id END)        AS total_refund_transfer_revenue_customers,
    SUM(total_refund_transfer_revenue)                                                AS total_refund_transfer_revenue,
    COUNT(DISTINCT CASE WHEN fde_attach_flag = 1        THEN pseudonym_id END)        AS total_5de,
    SUM(total_fde_revenue)                                                            AS total_fde_revenue,
    SUM(total_revenue)                                                                AS total_revenue
FROM cgan_ustax_ws.Saves_efile_reject_ty25_01_base base
-- WHERE date_qualified NOT IN (
--     SELECT DISTINCT date_qualified
--     FROM cgan_ustax_ws.Saves_efile_reject_ty25_01_base_aggr
-- )
GROUP BY
    test_group, email_recipe_rollup, email_error_code, date_qualified,
    date_fed_efile_attempt, date_fed_file_success, date_fed_efile_reject,
    tto_segment_rollup, completed_sku_rollup, flag_email,
    rt_attach_flag, rt_revenue_flag, fde_attach_flag
;
            

/*drop table if exists cgan_ustax_ws.Saves_efile_reject_ty25_01_base_aggr;
CREATE TABLE cgan_ustax_ws.Saves_efile_reject_ty25_01_base_aggr AS
SELECT 
    -- Dimensions
      base.test_group
    , base.email_recipe_rollup
    , base.email_error_code
    , base.error_code
    , base.date_qualified
    , base.date_fed_efile_attempt
    , base.date_fed_file_success
    , base.date_fed_efile_reject
    , base.tto_segment_rollup
    , base.completed_sku_rollup
    , base.flag_email
    , base.rt_attach_flag
    , base.rt_revenue_flag
    , base.fde_attach_flag
    , base.flag_prc_call_list_to_dialer
    , base.flag_prc_ob_call_offered
    , base.flag_prc_ob_call_handled

    -- Volume metrics
    , COUNT(*)                                                              AS total_records
    , COUNT(DISTINCT base.pseudonym_id)                                     AS total_customers

    -- Performance metrics
    , COUNT(DISTINCT CASE WHEN base.flag_reauth = 1 
            THEN base.pseudonym_id END)                                     AS total_reauth
    , COUNT(DISTINCT CASE WHEN base.flag_file_attempt = 1 
            THEN base.pseudonym_id END)                                     AS total_file_attempt
    , COUNT(DISTINCT CASE WHEN base.flag_file_success = 1 
            THEN base.pseudonym_id END)                                     AS total_file_success
    , COUNT(DISTINCT CASE WHEN base.flag_efile_rejected = 1 
            THEN base.pseudonym_id END)                                     AS total_efile_rejected
    , COUNT(DISTINCT CASE WHEN base.rt_attach_flag = 1 
            THEN base.pseudonym_id END)                                     AS total_refund_transfer
    , COUNT(DISTINCT CASE WHEN base.rt_revenue_flag = 1 
            THEN base.pseudonym_id END)                                     AS total_refund_transfer_revenue_customers
    , SUM(base.total_refund_transfer_revenue)                               AS total_refund_transfer_revenue
    , COUNT(DISTINCT CASE WHEN base.fde_attach_flag = 1 
            THEN base.pseudonym_id END)                                     AS total_fde
    , SUM(base.total_fde_revenue)                                           AS total_fde_revenue
    , SUM(base.total_revenue)                                               AS total_revenue
    , COUNT(DISTINCT CASE WHEN base.flag_called_intuit = 1 
            THEN base.pseudonym_id END)                                     AS total_called_intuit
    -- Fixed: rej.error_code → base.error_code, b.auth_id → base.auth_id
    , COUNT(DISTINCT CASE WHEN base.error_code IS NOT NULL 
            THEN base.auth_id END)                                          AS total_rejects

FROM cgan_ustax_ws.Saves_efile_reject_ty25_01_base base

GROUP BY
      base.test_group
    , base.email_recipe_rollup
    , base.email_error_code
    , base.error_code                              
    , base.date_qualified
    , base.date_fed_efile_attempt
    , base.date_fed_file_success
    , base.date_fed_efile_reject
    , base.tto_segment_rollup
    , base.completed_sku_rollup
    , base.flag_email
    , base.rt_attach_flag
    , base.rt_revenue_flag
    , base.fde_attach_flag
    , base.flag_prc_call_list_to_dialer
    , base.flag_prc_ob_call_offered
    , base.flag_prc_ob_call_handled
;*/


-- DROP TABLE IF EXISTS cgan_general_published.Saves_efile_reject_ty25_01_em_bayesian;
-- CREATE TABLE cgan_general_published.Saves_efile_reject_ty25_01_em_bayesian USING PARQUET AS
-- with users_audience as (
-- select distinct
--           base.pseudonym_id                                        
--         , '001_efilerejectem'                                            as experiment_id   
--         , date(base.date_qualified)                                      as cohort_date
--         , base.email_recipe_rollup                                       as condition 
--         , 'Refile Success'                                               as metric
--         , max(coalesce(base.flag_file_success,0))
--               over (partition by base.pseudonym_id)                      as outcome
-- from cgan_ustax_ws.Saves_efile_reject_ty25_01_base as base  
-- where lower(base.test_group) = 'test'
--   and base.email_recipe_rollup is not null
--   and base.error_code_rollup = 'Top 9'
-- ) 
-- select 
--           experiment_id
--         , cohort_date
--         , condition
--         , metric
--         , 1.0 * outcome as outcome  
-- from users_audience
;
