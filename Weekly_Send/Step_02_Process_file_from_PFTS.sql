--319 added prc day 2 final file here to combine with existing day 1 prc file
--319 day 2 prc will only start coming in on 321 friday so commenting out the code to combine day 1 prc to day 2 prc
--630 added 3 day lookback to account for weekend
DROP table if exists cgan_ustax_ws.efile_Baldue_weekly_new_ty25_cjo;
CREATE TABLE cgan_ustax_ws.efile_Baldue_weekly_new_ty25_cjo as 
select * from  cgan_ustax_ws.efile_rejects_directmail_weekly_ty25_cjo_staging_pftsv2_stg1
where cjo_file_name like '%TY25_FERCJO_directMail_balDue%'
and pseudonym_id != 'pseudonym_id';
--adding code below only for 315 and 316 then it needs to be commented out
-- AND CAST(dt AS DATE) >= CURRENT_DATE - INTERVAL '7' DAY;  

DROP table if exists cgan_ustax_ws.efile_Est_refund_weekly_new_ty25_cjo;
CREATE TABLE cgan_ustax_ws.efile_Est_refund_weekly_new_ty25_cjo as 
select * from  cgan_ustax_ws.efile_rejects_directmail_weekly_ty25_cjo_staging_pftsv2_stg1
where cjo_file_name like '%TY25_FERCJO_directMail_Est_refund%'
and pseudonym_id != 'pseudonym_id'
--adding code below only for 315 and 316 then it needs to be commented out
-- AND CAST(dt AS DATE) >= CURRENT_DATE - INTERVAL '7' DAY;   
;  

-- 1) Union the two weekly sources into one table
DROP table if exists cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo;
CREATE TABLE cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo AS
SELECT * FROM cgan_ustax_ws.efile_est_refund_weekly_new_ty25_cjo
UNION ALL
SELECT * FROM cgan_ustax_ws.efile_baldue_weekly_new_ty25_cjo
;

-- 2) Map pseudonym_id -> auth_id for active profiles (keep only rows with a match)
--    + 3) Suppress anyone already in historical
--    + 4) Deduplicate by pseudonym_id
--    + 5) Add qualified date/timestamp
DROP table if exists cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg;
CREATE TABLE cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg AS
WITH base AS (
  SELECT
      fed.*,
      b.accountid AS auth_id
  FROM cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo fed
  INNER JOIN intuit_foundation_identityandcustomer360_unified_dwh.person_account b
    ON CAST(fed.pseudonym_id AS STRING) = CAST(b.digitalidentitypseudonymid AS STRING)
   AND b.profilestatus = 'ACTIVE'
   AND b.accountid IS NOT NULL
),
unsuppressed AS (
  SELECT *
  FROM base stg
  WHERE NOT EXISTS (
    SELECT 1
    FROM cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_historical_ty25 h
    WHERE h.pseudonym_id = stg.pseudonym_id
  )
),
deduped AS (
  SELECT
      *,
      current_date()       AS date_qualified,
      current_timestamp()  AS date_qualified_timestamp,
      ROW_NUMBER() OVER (
        PARTITION BY pseudonym_id
        ORDER BY auth_id
      ) AS rn
  FROM unsuppressed
)
SELECT *
FROM deduped
WHERE rn = 1
;
DROP table if exists cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final;
CREATE TABLE  cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final AS
WITH cleaned AS (
  SELECT
    t.*,
    CASE
      WHEN t.street_addr_2 IS NOT NULL
        AND trim(t.street_addr_2) <> ''
        AND NOT (
          upper(trim(t.street_addr_2)) LIKE '#%' OR
          lower(trim(t.street_addr_2)) LIKE 'null%' OR
          upper(trim(t.street_addr_2)) LIKE 'APT%' OR
          upper(trim(t.street_addr_2)) LIKE 'PO BOX%' OR
          upper(trim(t.street_addr_2)) LIKE 'UNIT%' OR
          upper(trim(t.street_addr_2)) LIKE 'UNITE%'
        )
      THEN concat(
            trim(coalesce(t.turbotax_taxPrep_mailingAddress_street, '')),
            CASE
              WHEN t.turbotax_taxPrep_mailingAddress_street IS NULL
                OR trim(t.turbotax_taxPrep_mailingAddress_street) = ''
              THEN ''
              ELSE '\n'
            END,
            trim(t.street_addr_2)
          )
      ELSE t.turbotax_taxPrep_mailingAddress_street
    END AS turbotax_taxPrep_mailingAddress_street_out,

    CASE
      WHEN t.street_addr_2 IS NOT NULL
        AND trim(t.street_addr_2) <> ''
        AND NOT (
          upper(trim(t.street_addr_2)) LIKE '#%' OR
          lower(trim(t.street_addr_2)) LIKE 'null%' OR
          upper(trim(t.street_addr_2)) LIKE 'APT%' OR
          upper(trim(t.street_addr_2)) LIKE 'PO BOX%' OR
          upper(trim(t.street_addr_2)) LIKE 'UNIT%'
        )
      THEN NULL
      ELSE t.street_addr_2
    END AS street_addr_2_out
  FROM cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg t
),
filtered AS (
  SELECT *
  FROM cleaned
  WHERE
    cust_first_name IS NOT NULL
    AND cust_last_name IS NOT NULL   
    AND state_code IS NOT NULL
    AND city_name IS NOT NULL
    AND us_zip_code IS NOT NULL
    AND turbotax_taxPrep_mailingAddress_street IS NOT NULL

    -- Remove masked/test data rows
    AND NOT (
         REGEXP_LIKE(cust_first_name, '^[Xx]+$')
      OR REGEXP_LIKE(cust_last_name, '^[Xx]+$')
      OR REGEXP_LIKE(turbotax_taxPrep_mailingAddress_street_out, '[Xx]{3,}')
      OR REGEXP_LIKE(street_addr_2_out, '[Xx]{3,}')
      OR REGEXP_LIKE(city_name, '[Xx]{3,}')
    )
)
SELECT
  f.auth_id,
  f.pseudonym_id,
  f.cust_first_name,
  f.cust_last_name,
  f.turbotax_taxPrep_mailingAddress_street_out AS turbotax_taxPrep_mailingAddress_street,
  f.street_addr_2_out AS street_addr_2,
  f.city_name,
  f.state_code,
  f.us_zip_code,
  f.masked_login_name,
  f.cjo_file_name,
  f.direct_mail_type,
  f.date_qualified,
  f.date_qualified_timestamp
FROM filtered f
LEFT JOIN cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_historical_ty25 ah
  ON f.auth_id = ah.auth_id
 AND f.pseudonym_id = ah.pseudonym_id
WHERE ah.auth_id IS NULL;
