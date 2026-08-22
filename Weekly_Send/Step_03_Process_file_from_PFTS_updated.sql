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

drop table if exists cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg1;
CREATE TABLE cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg1 AS
SELECT *
 FROM (
    SELECT a.*
        ,coalesce(pam.first_fed_efile_accepted_date, pam.first_print_to_mail_date) as date_fed_file_success_new
    FROM cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo a
    LEFT JOIN tax_rpt.product_analytics_master pam
        on a.pseudonym_id = pam.pseudonym_id
            and pam.tax_year = 2025
) subquery
WHERE date_fed_file_success_new IS NULL;

-- 2) Map pseudonym_id -> auth_id for active profiles (keep only rows with a match)
--    + 3) Suppress anyone already in historical
--    + 4) Deduplicate by pseudonym_id
--    + 5) Add qualified date/timestamp
DROP TABLE IF EXISTS cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg2;
CREATE TABLE cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg2 AS
WITH base AS (
  SELECT
    fed.pseudonym_id,
    cust_first_name,
    cust_last_name,
    masked_login_name,
    cjo_file_name,
    direct_mail_type,
    b.accountid AS auth_id
  FROM cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg1 fed
  INNER JOIN intuit_foundation_identityandcustomer360_unified_dwh.person_account b
    ON CAST(fed.pseudonym_id AS STRING) = CAST(b.digitalidentitypseudonymid AS STRING)
   AND b.profilestatus = 'ACTIVE'
   AND b.accountid IS NOT NULL
),
base_address AS (
  SELECT
    orderAccountInformation.accountId,
    billingAccountInformation.address.address1 AS turbotax_taxPrep_mailingAddress_street,
    billingAccountInformation.address.address2 AS street_addr_2,
    billingAccountInformation.address.locality  AS city_name,
    billingAccountInformation.address.region    AS state_code,
    billingAccountInformation.address.postalCode AS us_zip_code
  FROM custeng_commerce_orderprocess.orderv2
),
base_w_address AS (
  SELECT
    b.pseudonym_id,
    b.cust_first_name,
    b.cust_last_name,
    b.masked_login_name,
    b.auth_id,
    b.cjo_file_name,
    b.direct_mail_type,
    ba.turbotax_taxPrep_mailingAddress_street,
    ba.street_addr_2,
    ba.city_name,
    ba.state_code,
    LEFT(ba.us_zip_code, 5) AS us_zip_code
  FROM base b
  JOIN base_address ba
    ON b.auth_id = ba.accountId
),
deduped AS (
  SELECT
    *,
    current_timestamp() AS date_qualified_timestamp,
    ROW_NUMBER() OVER (
      PARTITION BY pseudonym_id
      ORDER BY auth_id
    ) AS rn
  FROM base_w_address
)
SELECT *
FROM deduped
WHERE rn = 1;

DROP TABLE IF EXISTS cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_updated;
CREATE TABLE cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_updated AS
WITH filtered AS (
  SELECT *
  FROM cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_stg2
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
      OR REGEXP_LIKE(turbotax_taxPrep_mailingAddress_street, '[Xx]{3,}')
      -- OR REGEXP_LIKE(street_addr_2, '[Xx]{3,}')
      OR REGEXP_LIKE(city_name, '[Xx]{3,}')
    )
)
SELECT
  f.auth_id,
  f.pseudonym_id,
  f.cust_first_name,
  f.cust_last_name,
  f.turbotax_taxPrep_mailingAddress_street,
  f.street_addr_2,
  f.city_name,
  f.state_code,
  f.us_zip_code,
  f.masked_login_name,
  f.cjo_file_name,
  f.direct_mail_type,
  date(f.date_qualified_timestamp) as date_qualified,
  f.date_qualified_timestamp
FROM filtered f
LEFT JOIN cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_historical_ty25 ah
  ON f.auth_id = ah.auth_id
 AND f.pseudonym_id = ah.pseudonym_id
WHERE ah.auth_id IS NULL;
