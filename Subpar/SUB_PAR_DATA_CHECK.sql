
-- Drop & (re)create the staging external table over S3 CSVs

-- DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_em_historical_stg_narrow;
-- CREATE EXTERNAL TABLE cgan_ustax_ws.sub_par_ty24_00_em_historical_stg_narrow ( 
--       extra_leading_col  string   -- absorbs unnamed first column if present
--     , external_id        string
--     , issue_type         string
--     , date_issue         string
--     , date_qualified     string
--     , cell               string
--     , mpm_cell           string
--     , dt                 string
--     , mpm                string
-- )
-- ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
-- WITH SERDEPROPERTIES (
--     'separatorChar' = ',',
--     'quoteChar'     = '"',
--     'escapeChar'    = '\\'
-- )
-- STORED AS
--     INPUTFORMAT  'org.apache.hadoop.mapred.TextInputFormat'
--     OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
-- LOCATION
--     's3://idl-cgan-ustax-processing-cgan-prd/cgcs_sub_par_experiences/subpar_ty24_cch/sub_par_ty24/ty24_audience/'
-- TBLPROPERTIES (
--       's3select.format'        = 'csv'
--     , 'has_encrypted_data'     = 'false'
--     , 'skip.header.line.count' = '1'
-- );

-- Build the normalized table
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_em_historical_stage;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_00_em_historical_stage AS

-- ============ Helpers as CTEs ============
WITH
-- ------------- 8-col source (narrow) -------------
n_base AS (
  SELECT
    n.*,
    lower(trim(n.issue_type)) AS issue_type_lc
  FROM cgan_ustax_ws.sub_par_ty24_00_em_historical_stg n
  WHERE
    -- drop headers that slipped in
    n.external_id    NOT RLIKE '^(?i)external_id$' AND
    n.issue_type     NOT RLIKE '^(?i)issue_type$' AND
    n.date_issue     NOT RLIKE '^(?i)date_issue$' AND
    n.date_qualified NOT RLIKE '^(?i)date_qualified$' AND
    n.cell           NOT RLIKE '^(?i)cell$' AND
    n.mpm_cell       NOT RLIKE '^(?i)mpm_cell$' AND
    n.dt             NOT RLIKE '^(?i)dt$' AND
    n.mpm            NOT RLIKE '^(?i)mpm$'
),
n_tag AS (
  SELECT
    *,
    -- where is the ID?
    CASE WHEN length(trim(external_id)) BETWEEN 33 AND 35 AND external_id RLIKE '^[A-Za-z0-9_-]+$' THEN 1 ELSE 0 END AS id_in_ext,
    CASE WHEN length(trim(issue_type )) BETWEEN 33 AND 35 AND issue_type  RLIKE '^[A-Za-z0-9_-]+$' THEN 1 ELSE 0 END AS id_in_iss,
    -- issue_type validity
    CASE WHEN issue_type_lc IN (
      '1. high wait times & abandoned',
      '2. late-night callback',
      '3. excessive transfers 3 or more same call'
    ) THEN 1 ELSE 0 END AS issue_ok
  FROM n_base
),
-- mapping A: assume NORMAL (ID in external_id)
n_map_a AS (
  SELECT
    trim(external_id) AS pseudonym_id,
    issue_type        AS issue_type,
    to_date(trim(date_issue)) AS date_issue,
    COALESCE(
      to_timestamp(trim(date_qualified), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd'T'HH:mm:ssXXX"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd HH:mm:ss"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd")
    ) AS datetime_qualified,
    to_date(COALESCE(
      to_timestamp(trim(date_qualified), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd'T'HH:mm:ssXXX"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd HH:mm:ss"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd")
    )) AS date_qualified,
    substring(regexp_replace(cell,'[\\r\\n]+',' '),1,1) AS cell,
    regexp_replace(mpm_cell,'[\\r\\n]+',' ')            AS mpm_cell,
    to_date(COALESCE(
      to_timestamp(trim(dt), 'yyyy-MM-dd'),
      to_timestamp(trim(dt), 'yyyy-MM-dd HH:mm:ss'),
      to_timestamp(trim(dt), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(dt), "yyyy-MM-dd'T'HH:mm:ssXXX")
    )) AS dt,
    regexp_replace(mpm,'[\\r\\n]+',' ')                 AS mpm,
    -- validation flags for A
    CASE WHEN length(trim(external_id)) BETWEEN 33 AND 35 AND external_id RLIKE '^[A-Za-z0-9_-]+$' THEN 1 ELSE 0 END AS a_id_ok,
    CASE WHEN lower(trim(issue_type)) IN (
      '1. high wait times & abandoned',
      '2. late-night callback',
      '3. excessive transfers 3 or more same call'
    ) THEN 1 ELSE 0 END AS a_issue_ok,
    1 AS source_is_narrow
  FROM n_base
),
-- mapping B: assume SHIFTED LEFT by 1 (ID in issue_type)
n_map_b AS (
  SELECT
    trim(issue_type)  AS pseudonym_id,
    date_issue        AS issue_type,
    to_date(trim(date_qualified)) AS date_issue,
    COALESCE(
      to_timestamp(trim(cell), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(cell), "yyyy-MM-dd'T'HH:mm:ssXXX"),
      to_timestamp(trim(cell), "yyyy-MM-dd HH:mm:ss"),
      to_timestamp(trim(cell), "yyyy-MM-dd")
    ) AS datetime_qualified,
    to_date(COALESCE(
      to_timestamp(trim(cell), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(cell), "yyyy-MM-dd'T'HH:mm:ssXXX"),
      to_timestamp(trim(cell), "yyyy-MM-dd HH:mm:ss"),
      to_timestamp(trim(cell), "yyyy-MM-dd")
    )) AS date_qualified,
    substring(regexp_replace(mpm_cell,'[\\r\\n]+',' '),1,1) AS cell,
    regexp_replace(dt,'[\\r\\n]+',' ')                      AS mpm_cell,
    to_date(trim(mpm))                                      AS dt,
    ''                                                      AS mpm,  -- shifted-out
    -- validation flags for B
    CASE WHEN length(trim(issue_type)) BETWEEN 33 AND 35 AND issue_type RLIKE '^[A-Za-z0-9_-]+$' THEN 1 ELSE 0 END AS b_id_ok,
    CASE WHEN lower(trim(date_issue)) IN (  -- after shift, date_issue column holds issue_type text
      '1. high wait times & abandoned',
      '2. late-night callback',
      '3. excessive transfers 3 or more same call'
    ) THEN 1 ELSE 0 END AS b_issue_ok,
    1 AS source_is_narrow
  FROM n_base
),
-- choose the best mapping per-row using validation
n_chosen AS (
  SELECT *
  FROM (
    SELECT
      a.*,
      -- prefer A if A validates; else prefer B if B validates; else neither (will go to rejects)
      CASE WHEN a.a_id_ok = 1 AND a.a_issue_ok = 1 THEN 1 ELSE 0 END AS a_valid
    FROM n_map_a a
  ) a
  JOIN (
    SELECT
      b.*,
      CASE WHEN b.b_id_ok = 1 AND b.b_issue_ok = 1 THEN 1 ELSE 0 END AS b_valid
    FROM n_map_b b
  ) b
  ON a.source_is_narrow = b.source_is_narrow
  -- pick A if valid; else B if valid; else later put to rejects
),
n_final AS (
  SELECT
    CASE WHEN a_valid=1 THEN a.pseudonym_id ELSE b.pseudonym_id END AS pseudonym_id,
    CASE WHEN a_valid=1 THEN a.issue_type   ELSE b.issue_type   END AS issue_type,
    CASE WHEN a_valid=1 THEN a.date_issue   ELSE b.date_issue   END AS date_issue,
    CASE WHEN a_valid=1 THEN a.datetime_qualified ELSE b.datetime_qualified END AS datetime_qualified,
    CASE WHEN a_valid=1 THEN a.date_qualified     ELSE b.date_qualified     END AS date_qualified,
    CASE WHEN a_valid=1 THEN a.cell               ELSE b.cell               END AS cell,
    CASE WHEN a_valid=1 THEN a.mpm_cell           ELSE b.mpm_cell           END AS mpm_cell,
    CASE WHEN a_valid=1 THEN a.dt                 ELSE b.dt                 END AS dt,
    CASE WHEN a_valid=1 THEN a.mpm                ELSE b.mpm                END AS mpm,
    -- keep a flag to know if we used the shifted mapping
    CASE WHEN a_valid=1 THEN 0 ELSE CASE WHEN b_valid=1 THEN 1 ELSE 9 END END AS used_shift
  FROM n_chosen
  WHERE (a_valid=1 OR b_valid=1)
),

-- ------------- 9-col source (wide) -------------
w_base AS (
  SELECT
    w.*,
    lower(trim(w.issue_type)) AS issue_type_lc
  FROM cgan_ustax_ws.sub_par_ty24_00_em_historical_stg_wide w
  WHERE
    w.external_id    NOT RLIKE '^(?i)external_id$' AND
    w.issue_type     NOT RLIKE '^(?i)issue_type$' AND
    w.date_issue     NOT RLIKE '^(?i)date_issue$' AND
    w.date_qualified NOT RLIKE '^(?i)date_qualified$' AND
    w.cell           NOT RLIKE '^(?i)cell$' AND
    w.mpm_cell       NOT RLIKE '^(?i)mpm_cell$' AND
    w.dt             NOT RLIKE '^(?i)dt$' AND
    w.mpm            NOT RLIKE '^(?i)mpm$' AND
    coalesce(w.extra_leading_col,'') != ''   -- ensure a 9-col row truly has that extra leading col
),
w_tag AS (
  SELECT
    *,
    CASE WHEN length(trim(extra_leading_col)) BETWEEN 33 AND 35 AND extra_leading_col RLIKE '^[A-Za-z0-9_-]+$' THEN 1 ELSE 0 END AS id_in_extra,
    CASE WHEN length(trim(external_id))       BETWEEN 33 AND 35 AND external_id       RLIKE '^[A-Za-z0-9_-]+$' THEN 1 ELSE 0 END AS id_in_ext,
    CASE WHEN issue_type_lc IN (
      '1. high wait times & abandoned',
      '2. late-night callback',
      '3. excessive transfers 3 or more same call'
    ) THEN 1 ELSE 0 END AS issue_ok
  FROM w_base
),
-- mapping A (NORMAL for wide: ID in external_id)
w_map_a AS (
  SELECT
    trim(external_id) AS pseudonym_id,
    issue_type        AS issue_type,
    to_date(trim(date_issue)) AS date_issue,
    COALESCE(
      to_timestamp(trim(date_qualified), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd'T'HH:mm:ssXXX"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd HH:mm:ss"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd")
    ) AS datetime_qualified,
    to_date(COALESCE(
      to_timestamp(trim(date_qualified), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd'T'HH:mm:ssXXX"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd HH:mm:ss"),
      to_timestamp(trim(date_qualified), "yyyy-MM-dd")
    )) AS date_qualified,
    substring(regexp_replace(cell,'[\\r\\n]+',' '),1,1) AS cell,
    regexp_replace(mpm_cell,'[\\r\\n]+',' ')            AS mpm_cell,
    to_date(COALESCE(
      to_timestamp(trim(dt), 'yyyy-MM-dd'),
      to_timestamp(trim(dt), 'yyyy-MM-dd HH:mm:ss'),
      to_timestamp(trim(dt), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(dt), "yyyy-MM-dd'T'HH:mm:ssXXX")
    )) AS dt,
    regexp_replace(mpm,'[\\r\\n]+',' ')                 AS mpm,
    -- validation
    CASE WHEN length(trim(external_id)) BETWEEN 33 AND 35 AND external_id RLIKE '^[A-Za-z0-9_-]+$' THEN 1 ELSE 0 END AS a_id_ok,
    CASE WHEN issue_ok=1 THEN 1 ELSE 0 END AS a_issue_ok,
    0 AS source_is_narrow
  FROM w_tag
),
-- mapping B (SHIFTED RIGHT by 1 in wide: ID in extra_leading_col)
w_map_b AS (
  SELECT
    trim(extra_leading_col) AS pseudonym_id,
    external_id             AS issue_type,
    to_date(trim(issue_type)) AS date_issue,
    COALESCE(
      to_timestamp(trim(date_issue), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(date_issue), "yyyy-MM-dd'T'HH:mm:ssXXX"),
      to_timestamp(trim(date_issue), "yyyy-MM-dd HH:mm:ss"),
      to_timestamp(trim(date_issue), "yyyy-MM-dd")
    ) AS datetime_qualified,
    to_date(COALESCE(
      to_timestamp(trim(date_issue), "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"),
      to_timestamp(trim(date_issue), "yyyy-MM-dd'T'HH:mm:ssXXX"),
      to_timestamp(trim(date_issue), "yyyy-MM-dd HH:mm:ss"),
      to_timestamp(trim(date_issue), "yyyy-MM-dd")
    )) AS date_qualified,
    substring(regexp_replace(date_qualified,'[\\r\\n]+',' '),1,1) AS cell,
    regexp_replace(cell,'[\\r\\n]+',' ')                          AS mpm_cell,
    to_date(trim(mpm_cell))                                       AS dt,
    regexp_replace(dt,'[\\r\\n]+',' ')                            AS mpm,
    -- validation
    CASE WHEN length(trim(extra_leading_col)) BETWEEN 33 AND 35 AND extra_leading_col RLIKE '^[A-Za-z0-9_-]+$' THEN 1 ELSE 0 END AS b_id_ok,
    CASE WHEN lower(trim(external_id)) IN (
      '1. high wait times & abandoned',
      '2. late-night callback',
      '3. excessive transfers 3 or more same call'
    ) THEN 1 ELSE 0 END AS b_issue_ok,
    0 AS source_is_narrow
  FROM w_tag
),
w_chosen AS (
  SELECT *
  FROM (
    SELECT a.*, CASE WHEN a.a_id_ok=1 AND a.a_issue_ok=1 THEN 1 ELSE 0 END AS a_valid FROM w_map_a a
  ) a
  JOIN (
    SELECT b.*, CASE WHEN b.b_id_ok=1 AND b.b_issue_ok=1 THEN 1 ELSE 0 END AS b_valid FROM w_map_b b
  ) b
  ON a.source_is_narrow = b.source_is_narrow
),
w_final AS (
  SELECT
    CASE WHEN a_valid=1 THEN a.pseudonym_id ELSE b.pseudonym_id END AS pseudonym_id,
    CASE WHEN a_valid=1 THEN a.issue_type   ELSE b.issue_type   END AS issue_type,
    CASE WHEN a_valid=1 THEN a.date_issue   ELSE b.date_issue   END AS date_issue,
    CASE WHEN a_valid=1 THEN a.datetime_qualified ELSE b.datetime_qualified END AS datetime_qualified,
    CASE WHEN a_valid=1 THEN a.date_qualified     ELSE b.date_qualified     END AS date_qualified,
    CASE WHEN a_valid=1 THEN a.cell               ELSE b.cell               END AS cell,
    CASE WHEN a_valid=1 THEN a.mpm_cell           ELSE b.mpm_cell           END AS mpm_cell,
    CASE WHEN a_valid=1 THEN a.dt                 ELSE b.dt                 END AS dt,
    CASE WHEN a_valid=1 THEN a.mpm                ELSE b.mpm                END AS mpm,
    CASE WHEN a_valid=1 THEN 0 ELSE CASE WHEN b_valid=1 THEN 1 ELSE 9 END END AS used_shift
  FROM w_chosen
  WHERE (a_valid=1 OR b_valid=1)
),

-- union good rows and create a small reject set for anything that still fails rules
all_rows AS (
  SELECT * FROM n_final
  UNION ALL
  SELECT * FROM w_final
),
validated AS (
  SELECT *
  FROM all_rows
  WHERE
    length(pseudonym_id) BETWEEN 33 AND 35
    AND lower(trim(issue_type)) IN (
      '1. high wait times & abandoned',
      '2. late-night callback',
      '3. excessive transfers 3 or more same call'
    )
    AND length(trim(cell)) = 1
    AND date_issue IS NOT NULL
    AND date_qualified IS NOT NULL
    AND dt IS NOT NULL
),
rejects AS (
  SELECT *
  FROM all_rows
  WHERE
    NOT (
      length(pseudonym_id) BETWEEN 33 AND 35
      AND lower(trim(issue_type)) IN (
        '1. high wait times & abandoned',
        '2. late-night callback',
        '3. excessive transfers 3 or more same call'
      )
      AND length(trim(cell)) = 1
      AND date_issue IS NOT NULL
      AND date_qualified IS NOT NULL
      AND dt IS NOT NULL
    )
)

-- ============ FINAL WRITES ============
-- Main clean table
SELECT * FROM validated;
