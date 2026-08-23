/*--This step contains all customers that have already received the TY24 outreach for sub par experiences
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_em_historical_stg;
CREATE EXTERNAL TABLE cgan_ustax_ws.sub_par_ty24_00_em_historical_stg ( 
    external_id string
  , issue_type string
  , date_issue string
  , date_qualified string
  , cell string
  , mpm_cell string
  , dt string
  , mpm string
    )
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
"separatorChar" = ",",
"escapeChar" ="\\"
-- --- CHATGPT SUGGESTION
--   "separatorChar" = ",",
--   "quoteChar"     = "\"",
--   "escapeChar"    = "\\"
)
STORED AS
INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
--  's3://idl-cgan-ustax-processing-cgan-prd/cgcs_sub_par_experiences/subpar_ty23_cch/sub_par_ty23/ty23_audience/'
  's3://idl-cgan-ustax-processing-cgan-prd/cgcs_sub_par_experiences/subpar_ty24_cch/sub_par_ty24/ty24_audience/'
TBLPROPERTIES (
  's3select.format'='csv'
  ,'has_encrypted_data'='false'
  ,'skip.header.line.count'='1'
  );  

DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_em_historical;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_00_em_historical  AS
select     
    external_id as pseudonym_id 
  , issue_type 
  , cell 
  , cast(date_issue as date) as date_issue
  , cast(date_qualified as timestamp) as datetime_qualified
  , cast(cast(date_qualified as timestamp) as date) as date_qualified
  , mpm_cell
  , dt 
  , mpm 
from cgan_ustax_ws.sub_par_ty24_00_em_historical_stg
where external_id != 'external_id'
    and external_id != 'pseudonym_id'*/

-- Drop & (re)create the staging external table over S3 CSVs
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_em_historical_stg_wide;

CREATE EXTERNAL TABLE cgan_ustax_ws.sub_par_ty24_00_em_historical_stg_wide ( 
      extra_leading_col  string   -- absorbs unnamed first column if present
    , external_id        string
    , issue_type         string
    , date_issue         string
    , date_qualified     string
    , cell               string
    , mpm_cell           string
    , dt                 string
    , mpm                string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    'separatorChar' = ',',
    'quoteChar'     = '"',
    'escapeChar'    = '\\'
)
STORED AS
    INPUTFORMAT  'org.apache.hadoop.mapred.TextInputFormat'
    OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
    's3://idl-cgan-ustax-processing-cgan-prd/cgcs_sub_par_experiences/subpar_ty24_cch/sub_par_ty24/ty24_audience/'
TBLPROPERTIES (
      's3select.format'        = 'csv'
    , 'has_encrypted_data'     = 'false'
    , 'skip.header.line.count' = '1'
);

-- Build the normalized table
DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_00_em_historical_1;

CREATE TABLE cgan_ustax_ws.sub_par_ty24_00_em_historical_1 AS
WITH decide AS (
    SELECT
        t.*,
        CASE WHEN length(trim(extra_leading_col)) BETWEEN 33 AND 35 THEN 1 ELSE 0 END AS is_shifted
    FROM cgan_ustax_ws.sub_par_ty24_00_em_historical_stg_wide t
),
norm AS (
    SELECT
        CASE WHEN is_shifted = 1 THEN trim(extra_leading_col) ELSE trim(external_id) END                  AS pseudonym_id,
        CASE WHEN is_shifted = 1 THEN trim(external_id)       ELSE trim(issue_type)  END                  AS issue_type_raw,
        CAST( CASE WHEN is_shifted = 1 THEN issue_type        ELSE date_issue        END AS DATE )        AS date_issue,
        -- Keep the original ISO8601 string (parse later upstream if needed)
        CASE WHEN is_shifted = 1 THEN date_issue ELSE date_qualified END                                  AS datetime_qualified,
        CAST(
            CASE WHEN is_shifted = 1 THEN substr(date_issue,1,10) ELSE substr(date_qualified,1,10) END
            AS DATE
        ) AS date_qualified,
        substr(regexp_replace(CASE WHEN is_shifted = 1 THEN date_qualified ELSE cell END,'[\r\n]+',' '),1,1) AS cell,
        regexp_replace(CASE WHEN is_shifted = 1 THEN cell ELSE mpm_cell END,'[\r\n]+',' ')                AS mpm_cell,
        CAST( CASE WHEN is_shifted = 1 THEN mpm_cell ELSE dt END AS DATE )                                AS dt,
        regexp_replace(CASE WHEN is_shifted = 1 THEN dt ELSE mpm END,'[\r\n]+',' ')                       AS mpm
    FROM decide
)
SELECT
    pseudonym_id,
    -- Placeholder for future mapping (currently identity)
    CASE
        WHEN lower(issue_type_raw) IN (
            '1. high wait times & abandoned',
            '2. late-night callback',
            '3. excessive transfers 3 or more same call'
        ) THEN issue_type_raw
        ELSE issue_type_raw
    END AS issue_type,
    date_issue,
    datetime_qualified,
    date_qualified,
    cell,
    mpm_cell,
    dt,
    mpm
FROM norm
-- remove potential header artifacts
WHERE coalesce(pseudonym_id, '') NOT IN ('external_id','pseudonym_id');



