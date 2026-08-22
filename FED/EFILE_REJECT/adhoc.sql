--2.26 need to uncomment suppression file on 2.28, done on 228
--4.23 changed row 11 to 3 to keep data from sat and sun on monday, also added code to check for resolution since we want to call unresolved only on monday
--4.20 live ops will not make calls starting may 1 removed code to split file between concentrix and live ops 
--7.1 Added PFTSv2 and commented out PFTSv1
  
DROP TABLE IF EXISTS  cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo;
CREATE TABLE  cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo as
select b.*
  from cgan_ustax_ws.efile_day9_epc_contact_list_ty25_updated a
  join cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2 b
  on a.pseudonym_id = b.pseudonym_id
where date(Last_modified) ='2026-03-09';



-- step 02 new code for ty25 
-- append auth from person account table using pseudonym id to join

drop table if exists cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg;
create table cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg as
select distinct   
          fed.*
       -- ,b.emailaddresses.primaryEmailAddress as email_address_person_account
          ,b.accountid as auth_id
from cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo as fed
inner join intuit_foundation_identityandcustomer360_unified_dwh.person_account b 
    on cast(fed.pseudonym_id as string)=cast(b.digitalidentitypseudonymid as string)
      and b.profilestatus = 'ACTIVE'
      and b.accountid is not null
    --   and b.phonenumbers.primaryphonenumber is not null
   --   and b.phonenumbers.primaryphonenumber != ''
;

-- format phone number, suppress historical records by phone and pseudo use formatted phone from stg 

drop table if exists cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg2;
create table  cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg2 as
with formatted_stg as (
select stg.*, 
    CASE 
        WHEN stg.phone IS NOT NULL 
             AND TRIM(stg.phone) != ''
             AND LEFT(stg.phone, 1) != '+' 
             and length(stg.phone) = 10 --ensure international phone numbers aren't included in the file
        THEN CONCAT('+1', stg.phone) 
        ELSE stg.phone 
    END AS formatted_phone_number

 from cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg stg )

select stg.* from formatted_stg stg

--  left join (select distinct pseudonym_id from cgan_ustax_ws.efile_day9_epc_contact_list_ty25_updated) suppress1 
-- 	on stg.pseudonym_id = suppress1.pseudonym_id
-- left join (select distinct auth_id from   cgan_ustax_ws.efile_day9_epc_contact_list_ty25_updated) suppress2  
-- 	on stg.auth_id = suppress2.auth_id


-- where	    suppress1.pseudonym_id is null
-- 	and suppress2.auth_id is null   

 ;

drop table if exists cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg3;
CREATE TABLE cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg3 AS
SELECT *
 FROM (
    SELECT a.*
        ,coalesce(pam.first_fed_efile_accepted_date, pam.first_print_to_mail_date) as date_fed_file_success_new
    FROM cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg2 a
    LEFT JOIN tax_rpt.product_analytics_master pam
        on a.pseudonym_id = pam.pseudonym_id
            and pam.tax_year = 2025
) subquery
WHERE date_fed_file_success_new IS NULL;

-- dedupe records should not be any dupes but final check
-- create both date qualified and date qualified timestamps will be useful when pulling data from pam

drop table if exists cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_final;
create table cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_final as 
WITH src AS (
  SELECT
    s.*,
    CAST(current_timestamp AS DATE) AS date_qualified,
    current_timestamp AS ts_qualification
  FROM cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_stg3 s
),

-- Pick ONE row per pseudonym_id first (use a deterministic ordering if possible)
by_pid AS (
  SELECT *
  FROM (
    SELECT
      s.*,
      ROW_NUMBER() OVER (
        PARTITION BY pseudonym_id
        ORDER BY first_name, email, phone  -- REPLACE with a real deterministic field if available
      ) AS rn_pid
    FROM src s
  ) t
  WHERE rn_pid = 1
),

-- Then ensure ONE row per phone (only for non-null phones)
deduped AS (
  SELECT *
  FROM (
    SELECT
      p.*,
      ROW_NUMBER() OVER (
        PARTITION BY phone
        ORDER BY first_name, email, pseudonym_id -- REPLACE with deterministic field if available
      ) AS rn_phone
    FROM by_pid p
  ) t
  WHERE phone IS NULL OR rn_phone = 1
),

consent_phone AS (
  SELECT
    ownerid AS phone,
    1 AS flag_phone_consented
  FROM thrive_dwh.ctodev_consent_appevents
  WHERE ownertype = 'PHONE'
    AND consenttype = 'marketing-preferences'
    AND startdate IS NOT NULL
    AND consented = TRUE
  GROUP BY ownerid
),

consent_email AS (
  SELECT
    LOWER(ownerid) AS email,
    1 AS flag_email_consented
  FROM thrive_dwh.ctodev_consent_appevents
  WHERE ownertype = 'EMAIL'
    AND consenttype = 'marketing-preferences'
    AND startdate IS NOT NULL
    AND consented = TRUE
  GROUP BY LOWER(ownerid)
)

SELECT
  d.*,
  'Concentrix' AS Vendor,
  COALESCE(cp.flag_phone_consented, 0) AS flag_phone_consented,
  COALESCE(ce.flag_email_consented, 0) AS flag_email_consented
FROM deduped d
LEFT JOIN consent_phone cp
  ON d.phone = cp.phone
LEFT JOIN consent_email ce
  ON LOWER(d.email) = ce.email;

DROP TABLE IF EXISTS cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_consent;
CREATE TABLE cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_consent AS
select
  *
 from
cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_final
WHERE flag_phone_consented = 1
   OR flag_email_consented = 1;
