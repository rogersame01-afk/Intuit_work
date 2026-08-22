-- ============================================================
-- 1) Build base table with completion flag
-- ============================================================
DROP TABLE IF EXISTS cgan_ustax_ws.ob_sentiment_test_results_base_ty25_2;

CREATE TABLE cgan_ustax_ws.ob_sentiment_test_results_base_ty25_2 AS
SELECT
    t.*,
    CASE WHEN first_completed_date IS NOT NULL THEN 1 ELSE 0 END AS flag_complete
FROM cgan_ustax_ws.ob_sentiment_test_results_base_ty25 t
WHERE first_start_date IS NOT NULL;


-- ============================================================
-- 2) Publish Bayesian results table
-- ============================================================
DROP TABLE IF EXISTS cgan_general_published.ty25_sentiment_bayesian_all_results;

CREATE TABLE cgan_general_published.ty25_sentiment_bayesian_all_results
USING PARQUET
AS
WITH base AS (
    SELECT DISTINCT
        pseudonym_id,
        DATE(date_qualified)                 AS cohort_date,
        test_group                           AS condition,
        'completes'                          AS metric,
        1.0 * flag_complete                  AS outcome,
        CAST(date_qualified AS DATE)         AS qualified_date
    FROM cgan_ustax_ws.ob_sentiment_test_results_base_ty25_2
    WHERE CAST(date_qualified AS DATE) != CURRENT_DATE
),

completes_v1 AS (
    SELECT DISTINCT
        pseudonym_id,
        'ty25_MPS_Sentiment_OB_v1'           AS experiment_id,
        cohort_date,
        condition,
        metric,
        outcome
    FROM base
    WHERE cohort_date < DATE('2025-03-28')
),

completes_v2 AS (
    SELECT DISTINCT
        pseudonym_id,
        'ty25_MPS_Sentiment_OB_v2'           AS experiment_id,
        cohort_date,
        condition,
        metric,
        outcome
    FROM base
    WHERE cohort_date >= DATE('2025-03-28')
),

completes_v1_connected_only AS (
    SELECT DISTINCT
        b.pseudonym_id,
        'ty25_MPS_Sentiment_OB_v1_connected_only' AS experiment_id,
        b.cohort_date,
        b.condition,
        b.metric,
        b.outcome
    FROM base b
    JOIN cgan_ustax_ws.ob_sentiment_test_results_base_ty25_2 t
      ON t.pseudonym_id = b.pseudonym_id
     AND DATE(t.date_qualified) = b.cohort_date
     AND t.test_group = b.condition
     AND (1.0 * t.flag_complete) = b.outcome
    WHERE b.cohort_date < DATE('2025-03-28')
      AND (b.condition = 'Holdout' OR (b.condition = 'Test' AND t.flag_completed_call = 1))
),

completes_v2_connected_only AS (
    SELECT DISTINCT
        b.pseudonym_id,
        'ty25_MPS_Sentiment_OB_v2_connected_only' AS experiment_id,
        b.cohort_date,
        b.condition,
        b.metric,
        b.outcome
    FROM base b
    JOIN cgan_ustax_ws.ob_sentiment_test_results_base_ty25_2 t
      ON t.pseudonym_id = b.pseudonym_id
     AND DATE(t.date_qualified) = b.cohort_date
     AND t.test_group = b.condition
     AND (1.0 * t.flag_complete) = b.outcome
    WHERE b.cohort_date >= DATE('2025-03-28')
      AND (b.condition = 'Holdout' OR (b.condition = 'Test' AND t.flag_completed_call = 1))
)

SELECT
    experiment_id,
    cohort_date,
    condition,
    metric,
    outcome
FROM completes_v1

UNION ALL
SELECT experiment_id, cohort_date, condition, metric, outcome
FROM completes_v2

UNION ALL
SELECT experiment_id, cohort_date, condition, metric, outcome
FROM completes_v1_connected_only

UNION ALL
SELECT experiment_id, cohort_date, condition, metric, outcome
FROM completes_v2_connected_only
;
