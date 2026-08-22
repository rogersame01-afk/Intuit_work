drop table if exists cgan_ustax_ws.Saves_state_efile_reject_ty25_01_base;
create table cgan_ustax_ws.Saves_state_efile_reject_ty25_01_base as
WITH base_cast AS (
  SELECT
      pseudonym_id
    , auth_id
    , date_qualified
    , date_qualified_dt
    , test_group
  FROM (
    SELECT
        pseudonym_id
      , CAST(auth_id AS STRING)                                                  AS auth_id
      , eligible_date_min_pst                                                    AS date_qualified
      , CAST(eligible_date_min_pst AS DATE)                                      AS date_qualified_dt
      , CASE WHEN analytics_holdout_journey = 1 THEN 'Holdout' ELSE 'Test' END  AS test_group
      , ROW_NUMBER() OVER (
          PARTITION BY pseudonym_id
          ORDER BY eligible_date_min_pst
        )                                                                        AS rn
    FROM cgan_ustax_ws.Saves_states_efile_reject_ty25_00_ajo_analytics_destination
    WHERE auth_id IS NOT NULL
  )
  WHERE rn = 1
)
, state_filing_agg AS (
  SELECT
      CAST(taxFilerAuthId AS STRING)                                             AS auth_id
    , MIN(CAST(filingStatusDate AS DATE))                                        AS earliest_state_filing_date
  FROM incometax_taxfiling_filing.filing
  WHERE taxYear      = 2025
    AND filingType LIKE '%-IIT-FILING'      -- state individual income tax filings (e.g. CA-IIT-FILING)
    AND filingType <> 'IRS-IIT-FILING'      -- exclude Federal
    AND filingStatus IN ('SUCCEEDED_AGENCY', 'FILED_PRINT')
  GROUP BY 1
)
, state_efile_status AS (
  SELECT
      CAST(st.auth_id AS STRING)                                                 AS auth_id
    , MIN(DATE(st.efile_status_timestamp))                                       AS date_state_efile_attempt
    , MIN(CASE WHEN st.efile_status_code_id = 5
               THEN DATE(st.efile_status_timestamp) END)                         AS date_state_efile_reject
  FROM tax_dm.fact_efile_status st
  INNER JOIN tax_dm.dim_filing_type ft
    ON st.filing_type_id = ft.filing_type_id
  WHERE st.tax_year        = 2025
    AND ft.filing_type LIKE '%IIT-FILING'   -- individual income tax
    AND ft.filing_type NOT LIKE 'FCB%'      -- exclude FCB
    AND st.filing_type_id <> '244'          -- <> Federal = State
    AND st.auth_id <> -1
  GROUP BY 1
)
, reauth AS (
  SELECT
      CAST(auth_id AS STRING)                                                       AS auth_id
    , MAX(DATE(from_utc_timestamp(SESSION_AUTH_TIMESTAMP, 'America/Los_Angeles')))  AS last_session_date_pst
  FROM tax_rpt.MARKETING_SESSION_ANALYTICS_MASTER
  WHERE tax_year = 2025
  GROUP BY 1
)
, braze_email AS (
  SELECT pseudonym_id, audience_segment, date_em_sent
  FROM (
    SELECT
        pseudonym_id
      , audience_segment
      , date_em_sent
      , ROW_NUMBER() OVER (
          PARTITION BY pseudonym_id
          ORDER BY date_em_sent
        )                                                                        AS rn
    FROM cgan_ustax_ws.TY25_efile_reject_cjo_state_00_braze_email
  )
  WHERE rn = 1
)
, braze_sms AS (
  SELECT pseudonym_id, delivered_flag, first_send_dt_la
  FROM (
    SELECT
        pseudonym_id
      , delivered_flag
      , first_send_dt_la
      , ROW_NUMBER() OVER (
          PARTITION BY pseudonym_id
          ORDER BY first_send_dt_la
        )                                                                        AS rn
    FROM cgan_ustax_ws.TY25_efile_reject_cjo_state_00_braze_sms
  )
  WHERE rn = 1
)
, pam AS (
  SELECT pseudonym_id, tto_segment_rollup, completed_sku_rollup
  FROM (
    SELECT
        pseudonym_id
      , tto_segment_rollup
      , completed_sku_rollup
      , ROW_NUMBER() OVER (
          PARTITION BY pseudonym_id
          ORDER BY pseudonym_id
        )                                                                        AS rn
    FROM tax_rpt.product_analytics_master
    WHERE tax_year = 2025
  )
  WHERE rn = 1
)
, mam AS (
  SELECT auth_id, rt_attach_flag, rt_revenue_flag, total_refund_transfer_revenue
       , fde_attach_flag, total_fde_revenue, total_revenue
  FROM (
    SELECT
        CAST(auth_id AS STRING)                                                  AS auth_id
      , rt_attach_flag
      , rt_revenue_flag
      , total_refund_transfer_revenue
      , fde_attach_flag
      , total_fde_revenue
      , total_revenue
      , ROW_NUMBER() OVER (
          PARTITION BY auth_id
          ORDER BY auth_id
        )                                                                        AS rn
    FROM tax_rpt.monetization_analytics_master
    WHERE tax_year = 2025
  )
  WHERE rn = 1
)
SELECT
    b.pseudonym_id
  , b.auth_id
  , b.date_qualified
  , b.test_group
  , em.audience_segment
  , CASE WHEN em.pseudonym_id IS NOT NULL THEN 1 ELSE 0 END                     AS flag_email
  , em.date_em_sent
  , s.delivered_flag                                                             AS sms_delivered_flag
  , s.first_send_dt_la                                                           AS date_sms_sent
  , ss.date_state_efile_attempt
  , CASE
      WHEN sfa.earliest_state_filing_date >= b.date_qualified_dt
      THEN sfa.earliest_state_filing_date
    END                                                                          AS date_state_file_success
  , ss.date_state_efile_reject
  , pam.tto_segment_rollup
  , pam.completed_sku_rollup
  , mam.rt_attach_flag
  , mam.rt_revenue_flag
  , mam.total_refund_transfer_revenue
  , mam.fde_attach_flag
  , mam.total_fde_revenue
  , mam.total_revenue
  , CASE WHEN ra.auth_id IS NOT NULL THEN 1 ELSE 0 END                          AS flag_reauth
  , CASE WHEN ss.date_state_efile_attempt IS NOT NULL THEN 1 ELSE 0 END         AS flag_state_file_attempt
  , CASE WHEN ss.date_state_efile_reject  IS NOT NULL THEN 1 ELSE 0 END         AS flag_state_efile_rejected
  , CASE
      WHEN sfa.earliest_state_filing_date >= b.date_qualified_dt THEN 1 ELSE 0
    END                                                                          AS flag_state_file_success

FROM base_cast b

LEFT JOIN state_filing_agg sfa
  ON b.auth_id = sfa.auth_id
LEFT JOIN state_efile_status ss
  ON b.auth_id = ss.auth_id
LEFT JOIN braze_email em
  ON b.pseudonym_id = em.pseudonym_id
LEFT JOIN braze_sms s
  ON b.pseudonym_id = s.pseudonym_id
LEFT JOIN reauth ra
  ON b.auth_id = ra.auth_id
  AND ra.last_session_date_pst >= b.date_qualified_dt
LEFT JOIN pam
  ON b.pseudonym_id = pam.pseudonym_id
LEFT JOIN mam
  ON b.auth_id = mam.auth_id

-- Suppress customers who successfully filed state BEFORE they qualified
WHERE (sfa.earliest_state_filing_date IS NULL
       OR sfa.earliest_state_filing_date >= b.date_qualified_dt)
  AND b.auth_id IS NOT NULL;

-- =============================================================
-- STATE e-file reject TY25 — Tableau extract
-- Measures channel impact (Email @ day1, SMS @ day3) on refile success.
--
-- Design (sequential randomized / SMART):
--   Day 1 (reject/qualify):  Holdout = no contact   |  Test = email
--   Day 3 (still not refiled): a subset of emailed users receive SMS
--
-- Valid comparisons (build these in Tableau, do NOT mix the populations):
--   * EMAIL effect  -> test_group: 'Holdout' vs 'Test'  (full pop, day-1 ITT)
--   * SMS effect    -> flag_sms_sent 0 vs 1, FILTER sms_eligible_pop = 1
--                      (day-3 stalled emailed users only — never compare SMS to Holdout)
--
-- Grain: one row per pseudonym_id.
-- Day 0 = date_qualified (journey qualification, ~reject day).
--
-- Source: cgan_ustax_ws.Saves_state_efile_reject_ty25_01_base  (STATE schema)
-- =============================================================

drop table if exists cgan_ustax_ws.Saves_state_efile_reject_ty25_02_tableau;
create table cgan_ustax_ws.Saves_state_efile_reject_ty25_02_tableau as
WITH enriched AS (
  SELECT
      pseudonym_id
    , auth_id
    , test_group
    , audience_segment
    , tto_segment_rollup
    , completed_sku_rollup
    , date_qualified
    , CAST(date_qualified AS DATE)                                             AS day0_dt
    , date_state_efile_reject
    , date_state_efile_attempt
    , date_state_file_success
    , date_em_sent
    , date_sms_sent
    , flag_email
    , sms_delivered_flag
    , flag_reauth
    -- derive state flags from the date columns so this query does not depend
    -- on the base table carrying the flag_* columns
    , CASE WHEN date_state_efile_attempt IS NOT NULL THEN 1 ELSE 0 END          AS flag_state_file_attempt
    , CASE WHEN date_state_efile_reject  IS NOT NULL THEN 1 ELSE 0 END          AS flag_state_efile_rejected
    , CASE WHEN date_state_file_success  IS NOT NULL THEN 1 ELSE 0 END          AS flag_state_file_success
    , rt_attach_flag
    , rt_revenue_flag
    , total_refund_transfer_revenue
    , fde_attach_flag
    , total_fde_revenue
    , total_revenue
    -- SMS channel exposure (sent), independent of delivery
    , CASE WHEN date_sms_sent IS NOT NULL THEN 1 ELSE 0 END                    AS flag_sms_sent
    -- days from day 0 to successful refile (NULL if never refiled)
    , CASE WHEN date_state_file_success IS NOT NULL
           THEN DATEDIFF(date_state_file_success, CAST(date_qualified AS DATE))
      END                                                                      AS days_to_success
    -- days from day 0 to SMS send (diagnostic for timing checks)
    , CASE WHEN date_sms_sent IS NOT NULL
           THEN DATEDIFF(CAST(date_sms_sent AS DATE), CAST(date_qualified AS DATE))
      END                                                                      AS days_to_sms
  FROM cgan_ustax_ws.Saves_state_efile_reject_ty25_01_base
)
SELECT
    e.*

  -- ── Refile-success windows (relative to day 0) ──
  , CASE WHEN flag_state_file_success = 1 AND days_to_success <= 3  THEN 1 ELSE 0 END AS success_by_day3
  , CASE WHEN flag_state_file_success = 1 AND days_to_success <= 7  THEN 1 ELSE 0 END AS success_by_day7
  , CASE WHEN flag_state_file_success = 1 AND days_to_success <= 14 THEN 1 ELSE 0 END AS success_by_day14
  , CASE WHEN flag_state_file_success = 1 AND days_to_success <= 30 THEN 1 ELSE 0 END AS success_by_day30

  -- ── Terminal analysis arm (descriptive) ──
  , CASE
      WHEN test_group = 'Holdout'                          THEN '1_Holdout'
      WHEN test_group = 'Test' AND flag_email = 0          THEN '2_Test_no_email'
      WHEN flag_email = 1 AND flag_sms_sent = 0            THEN '3_Email_only'
      WHEN flag_email = 1 AND flag_sms_sent = 1            THEN '4_Email+SMS'
    END                                                                        AS analysis_arm

  -- ── SMS-eligible = day-3 stalled emailed users (the ONLY valid base for SMS vs no-SMS) ──
  --    emailed AND not yet successfully refiled by day 3
  , CASE
      WHEN flag_email = 1 AND (flag_state_file_success = 0 OR days_to_success > 3)
        THEN 1 ELSE 0
    END                                                                        AS sms_eligible_pop
FROM enriched e;


-- =============================================================

-- Row grain: one row per (comparison, pseudonym_id).
--   A customer appears once in the Email block, and again in the SMS
--   block if they were day-3 stalled. ALWAYS keep exactly one
--   `comparison` in the filter shelf so COUNTD / SUM stay correct.
--
-- Panels  = same table, add an attach filter:
--   Overall -> (no attach filter)
--   FDE     -> fde_attach_flag = 1
--   RT      -> rt_attach_flag  = 1
--
-- Row-level fields for the dashboard date filters:
--   Date Qualified      -> date_qualified
--   Date Refile Success -> date_state_file_success
--
-- KPI recipes (computed in Tableau; `is_control` marks the ITH baseline
-- row: Holdout for Email effect, Email-only for SMS effect):
--   Customers                  = COUNTD([pseudonym_id])
--   Reauth %                   = SUM([flag_reauth])       / Customers
--   Refile Success             = SUM([flag_state_file_success])
--   Refile Success %           = SUM([flag_state_file_success]) / Customers
--   ___ % ITH                  = 100 * rate(arm) / rate(control arm)
--   Incremental Success alone  = ( rate(arm) - rate(control) ) * Customers(arm)
--   FDE / RT ARPC              = SUM(total_fde_revenue | total_refund_transfer_revenue)
--                                  / Customers            (with attach filter on)
--   Incremental Success FDE/RT = Incremental Success alone under the attach filter
--   Incremental Revenue        = Incremental Success FDE/RT * ARPC
-- =============================================================

drop table if exists cgan_ustax_ws.Saves_state_efile_reject_ty25_02_dashboard_source;
create table cgan_ustax_ws.Saves_state_efile_reject_ty25_02_dashboard_source
USING PARQUET
AS
-- Latest SMS marketing preference per phone (most recent record wins)
WITH sms_pref_latest AS (
  SELECT phone, isPreferenceOptedIn
  FROM (
    SELECT
        ownerId                                              AS phone
      , INTUIT.preferences['/marketing-notifications/sms']   AS isPreferenceOptedIn
      , ROW_NUMBER() OVER (
          PARTITION BY LOWER(ownerId), ownerType, region, preferenceType, channel
          ORDER BY INTUIT.metadata['lastUpdatedTime'] DESC
        )                                                     AS rn
    FROM intuit_customergrowthandengagement_customerlifecycledatamanagement_marketingpreferences.marketingpreferencescomposite_history
    WHERE ownerType      = 'PHONE'
      AND region         = 'US'
      AND preferenceType = 'marketing-preferences'
      AND channel        = 'SMS'
      AND INTUIT IS NOT NULL
      AND INTUIT.preferences IS NOT NULL
      AND INTUIT.metadata IS NOT NULL
      AND map_contains_key(INTUIT.preferences, '/marketing-notifications/sms')
      AND map_contains_key(INTUIT.metadata, 'lastUpdatedTime')
  ) s
  WHERE rn = 1
)
-- Map pseudonym_id -> primary phone (one row per pseudonym_id)
, phone_map AS (
  SELECT digitalidentitypseudonymid          AS pseudonym_id
       , pa.phonenumbers.primaryPhoneNumber  AS phone
  FROM intuit_foundation_identityandcustomer360_unified_dwh.person_account pa
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY digitalidentitypseudonymid ORDER BY pa.accountid DESC
  ) = 1
)
-- Users who explicitly DECLINED SMS marketing (latest preference = 'false')
, sms_declined AS (
  SELECT DISTINCT pm.pseudonym_id
  FROM phone_map pm
  INNER JOIN sms_pref_latest mp ON pm.phone = mp.phone
  WHERE mp.isPreferenceOptedIn = 'false'
)

-- ─── COMPARISON 1: EMAIL effect (Day-1 ITT, full population) ───
SELECT
    '1_Email effect (Holdout vs Test)'                           AS comparison
  , test_group                                                   AS arm
  , CASE WHEN test_group = 'Holdout' THEN 1 ELSE 0 END           AS is_control
  , CASE WHEN test_group = 'Holdout' THEN 1 ELSE 2 END           AS arm_order
  , pseudonym_id
  , auth_id
  , date_qualified
  , date_state_file_success
  , days_to_success
  , audience_segment
  , tto_segment_rollup
  , completed_sku_rollup
  , flag_reauth
  , flag_state_file_success
  , success_by_day3
  , success_by_day7
  , success_by_day14
  , success_by_day30
  , rt_attach_flag
  , rt_revenue_flag
  , total_refund_transfer_revenue
  , fde_attach_flag
  , total_fde_revenue
  , total_revenue
FROM cgan_ustax_ws.Saves_state_efile_reject_ty25_02_tableau
WHERE test_group IN ('Holdout', 'Test')

UNION ALL

-- ─── COMPARISON 2: SMS effect (day-3 stalled emailed users only) ───
SELECT
    '2_SMS effect (day-3 stalled)'                               AS comparison
  , CASE WHEN flag_sms_sent = 1 THEN 'Email+SMS' ELSE 'Email only' END AS arm
  , CASE WHEN flag_sms_sent = 1 THEN 0 ELSE 1 END               AS is_control
  , CASE WHEN flag_sms_sent = 1 THEN 2 ELSE 1 END               AS arm_order
  , pseudonym_id
  , auth_id
  , date_qualified
  , date_state_file_success
  , days_to_success
  , audience_segment
  , tto_segment_rollup
  , completed_sku_rollup
  , flag_reauth
  , flag_state_file_success
  , success_by_day3
  , success_by_day7
  , success_by_day14
  , success_by_day30
  , rt_attach_flag
  , rt_revenue_flag
  , total_refund_transfer_revenue
  , fde_attach_flag
  , total_fde_revenue
  , total_revenue
FROM cgan_ustax_ws.Saves_state_efile_reject_ty25_02_tableau t
WHERE t.sms_eligible_pop = 1
  -- exclude users who declined SMS marketing (latest SMS preference = opted out)
  AND NOT EXISTS (
        SELECT 1 FROM sms_declined d
        WHERE d.pseudonym_id = t.pseudonym_id
      )
;


-- =============================================================
-- DASHBOARD SOURCE (PRE-AGGREGATED)  — optional alternate feed
-- Same comparison/arm/is_control shape as the customer-grain table,
-- but counts are already rolled up. Feed Tableau SUM() of these
-- building blocks (do NOT re-COUNTD). Grain is kept fine enough to
-- still filter by segment + both dashboard date filters.
--
-- Grain: comparison × arm × segment × date_qualified × date_state_file_success
--
-- Tableau (SUM the building blocks, then divide):
--   Reauth %          = SUM(reauths)   / SUM(customers)
--   Refile Success %  = SUM(success_ever) / SUM(customers)   (or success_by_dayN)
--   ___ % ITH         = 100 * rate(arm) / rate(control arm)      (is_control baseline)
--   Incremental alone = ( rate(arm) - rate(control) ) * SUM(customers[arm])
--   FDE ARPC          = SUM(fde_revenue) / SUM(customers)
--   Incremental Rev   = Incremental alone * ARPC
--
-- NOTE: because success counts are tied to date_state_file_success, a
-- "Date Refile Success" range filter also drops non-refilers (NULL date)
-- from SUM(customers). If you need the denominator to stay fixed while
-- only the numerator is date-filtered, use the customer-grain source
-- (_02_dashboard_source) instead.
-- =============================================================

drop table if exists cgan_ustax_ws.Saves_state_efile_reject_ty25_02_dashboard_agg;
create table cgan_ustax_ws.Saves_state_efile_reject_ty25_02_dashboard_agg as

-- ─── COMPARISON 1: EMAIL effect (Day-1 ITT, full population) ───
SELECT
    '1_Email effect (Holdout vs Test)'                                         AS comparison
  , test_group                                                                 AS arm
  , CASE WHEN test_group = 'Holdout' THEN 1 ELSE 0 END                         AS is_control
  , CASE WHEN test_group = 'Holdout' THEN 1 ELSE 2 END                         AS arm_order
  , audience_segment
  , tto_segment_rollup
  , completed_sku_rollup
  , date_qualified
  , date_state_file_success
  , COUNT(DISTINCT pseudonym_id)                                               AS customers
  , COUNT(DISTINCT CASE WHEN flag_reauth = 1 THEN pseudonym_id END)            AS reauths
  , COUNT(DISTINCT CASE WHEN success_by_day3  = 1 THEN pseudonym_id END)       AS success_by_day3
  , COUNT(DISTINCT CASE WHEN success_by_day14 = 1 THEN pseudonym_id END)       AS success_by_day14
  , COUNT(DISTINCT CASE WHEN success_by_day30 = 1 THEN pseudonym_id END)       AS success_by_day30
  , COUNT(DISTINCT CASE WHEN flag_state_file_success = 1 THEN pseudonym_id END) AS success_ever
  , COUNT(DISTINCT CASE WHEN fde_attach_flag = 1 THEN pseudonym_id END)        AS fde_attach
  , SUM(total_fde_revenue)                                                     AS fde_revenue
  , COUNT(DISTINCT CASE WHEN rt_attach_flag = 1 THEN pseudonym_id END)         AS rt_attach
  , COUNT(DISTINCT CASE WHEN rt_revenue_flag = 1 THEN pseudonym_id END)        AS rt_revenue_customers
  , SUM(total_refund_transfer_revenue)                                         AS rt_revenue
  , SUM(total_revenue)                                                         AS total_revenue
FROM cgan_ustax_ws.Saves_state_efile_reject_ty25_02_tableau
WHERE test_group IN ('Holdout', 'Test')
GROUP BY
    test_group
  , audience_segment
  , tto_segment_rollup
  , completed_sku_rollup
  , date_qualified
  , date_state_file_success

UNION ALL

-- ─── COMPARISON 2: SMS effect (day-3 stalled emailed users only) ───
SELECT
    '2_SMS effect (day-3 stalled)'                                             AS comparison
  , CASE WHEN flag_sms_sent = 1 THEN 'Email+SMS' ELSE 'Email only' END         AS arm
  , CASE WHEN flag_sms_sent = 1 THEN 0 ELSE 1 END                             AS is_control
  , CASE WHEN flag_sms_sent = 1 THEN 2 ELSE 1 END                             AS arm_order
  , audience_segment
  , tto_segment_rollup
  , completed_sku_rollup
  , date_qualified
  , date_state_file_success
  , COUNT(DISTINCT pseudonym_id)                                               AS customers
  , COUNT(DISTINCT CASE WHEN flag_reauth = 1 THEN pseudonym_id END)            AS reauths
  , COUNT(DISTINCT CASE WHEN success_by_day3  = 1 THEN pseudonym_id END)       AS success_by_day3
  , COUNT(DISTINCT CASE WHEN success_by_day14 = 1 THEN pseudonym_id END)       AS success_by_day14
  , COUNT(DISTINCT CASE WHEN success_by_day30 = 1 THEN pseudonym_id END)       AS success_by_day30
  , COUNT(DISTINCT CASE WHEN flag_state_file_success = 1 THEN pseudonym_id END) AS success_ever
  , COUNT(DISTINCT CASE WHEN fde_attach_flag = 1 THEN pseudonym_id END)        AS fde_attach
  , SUM(total_fde_revenue)                                                     AS fde_revenue
  , COUNT(DISTINCT CASE WHEN rt_attach_flag = 1 THEN pseudonym_id END)         AS rt_attach
  , COUNT(DISTINCT CASE WHEN rt_revenue_flag = 1 THEN pseudonym_id END)        AS rt_revenue_customers
  , SUM(total_refund_transfer_revenue)                                         AS rt_revenue
  , SUM(total_revenue)                                                         AS total_revenue
FROM cgan_ustax_ws.Saves_state_efile_reject_ty25_02_tableau
WHERE sms_eligible_pop = 1
GROUP BY
    flag_sms_sent
  , audience_segment
  , tto_segment_rollup
  , completed_sku_rollup
  , date_qualified
  , date_state_file_success
;



