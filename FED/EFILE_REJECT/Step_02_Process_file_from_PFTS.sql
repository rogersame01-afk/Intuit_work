--2.26 need to uncomment suppression file on 2.28, done on 228
--4.23 changed row 11 to 3 to keep data from sat and sun on monday, also added code to check for resolution since we want to call unresolved only on monday
--4.20 live ops will not make calls starting may 1 removed code to split file between concentrix and live ops 
--7.1 Added PFTSv2 and commented out PFTSv1
  
DROP TABLE IF EXISTS  cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo;
CREATE TABLE  cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo as
select * from cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2
where DATEDIFF(CURRENT_DATE, date(dt)) <= 4;



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

 left join (select distinct pseudonym_id from cgan_ustax_ws.efile_day9_epc_contact_list_ty25) suppress1 
	on stg.pseudonym_id = suppress1.pseudonym_id
left join (select distinct auth_id from   cgan_ustax_ws.efile_day9_epc_contact_list_ty25) suppress2  
	on stg.auth_id = suppress2.auth_id


where	    suppress1.pseudonym_id is null
	and suppress2.auth_id is null   

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

-- Pick ONE row per pseudonym_id first
by_pid AS (
  SELECT *
  FROM (
    SELECT
      s.*,
      ROW_NUMBER() OVER (
        PARTITION BY pseudonym_id
        ORDER BY first_name, email, phone
      ) AS rn_pid
    FROM src s
  ) t
  WHERE rn_pid = 1
),

-- Then ensure ONE row per phone (only for non-null phones)
by_phone AS (                          
  SELECT *
  FROM (
    SELECT
      p.*,
      ROW_NUMBER() OVER (
        PARTITION BY phone
        ORDER BY first_name, email, pseudonym_id
      ) AS rn_phone
    FROM by_pid p
  ) t
  WHERE phone IS NOT NULL AND rn_phone = 1
)                                      

-- Final SELECT
SELECT * FROM by_phone; 

DROP TABLE IF EXISTS cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_consent;
CREATE TABLE cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_consent AS
WITH marketing_preference_latest AS (
  SELECT 
    phone,
    isPreferenceOptedIn
  FROM (
    SELECT
      ownerId AS phone,
      INTUIT.preferences['/marketing-notifications/call'] AS isPreferenceOptedIn,
      ROW_NUMBER() OVER (
        PARTITION BY LOWER(ownerId), ownerType, region, preferenceType, channel
        ORDER BY INTUIT.metadata['lastUpdatedTime'] DESC
      ) AS rn
    FROM 
      intuit_customergrowthandengagement_customerlifecycledatamanagement_marketingpreferences.marketingpreferencescomposite_history
    WHERE 
      ownerType = 'PHONE'
      AND region = 'US'
      AND preferenceType = 'marketing-preferences'
      AND channel = 'CALL'
      AND INTUIT IS NOT NULL
      AND INTUIT.preferences IS NOT NULL
      AND INTUIT.metadata IS NOT NULL
      AND map_contains_key(INTUIT.preferences, '/marketing-notifications/call')
      AND map_contains_key(INTUIT.metadata, 'lastUpdatedTime')
  ) s
  WHERE rn = 1
),

consent_phone AS (
  SELECT phone 
  FROM marketing_preference_latest 
  WHERE isPreferenceOptedIn = 'false'
)

SELECT
  d.*,
  'Concentrix' AS Vendor
FROM cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_final d
LEFT JOIN consent_phone cp
  ON d.phone = cp.phone
WHERE cp.phone IS NULL;
