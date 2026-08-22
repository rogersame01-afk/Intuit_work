--notes by pooja 121824
--step 02 for mps survey - join the auths that responded as neutral or detractor on mps survey to the pam table and exclude those without pseudonym id and have not completed
--per alexis commented out 26-36 since we don't need to send file to prosifter 
--also commented out code for at risk flag in line 126 and the join to the table where this field is pulled from in lines 137 and 138
--1.12.25 removed replace function in line 53 as inhouse dialer requires +1 commented out 105-115 as not needed since we are not using prosifter this year
--1.13.25 replaced code from lines 51-119 with more efficient code in lines 122-190. reduces run time from 3 mins to 30 seconds, same output confirmed 
--1.13.25 added dedupe code from inhouse dialer notebook to bottom of this notebook starting at row 193
--1.13.25 added split into test and control from alteryx job to bottom of this notebook starting at row 203  
--1.13.25 made change to inhouse dialer notebook code to read only deduped records to s3 notebook and read only test records to inhouse dialer call file
--1.13.25 code for dedupe code and split into test and control tested in this notebook https://intuit-e2-570264151593-prd.cloud.databricks.com/editor/notebooks/3360161941849496?o=8126228270435530#command/3360161941863504
--1.14.25 added fname and lname not null in addition to phone number not null when creating cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25 but removed
--1.15.25 added additional source of data for fname and lname because this is requirement for dialer and the person account table has missing data
--1.15.25 addional source of data provided by Manoj Sahoo, awaiting confirmation from janani that it is ok to use tax_dm.helper_cv_get_pii
--1.15.25 need to check the phone flags once more on tax_dm.helper_cv_get_pii -- do this today 
--1.15.25 added code to only retain records where fname is populated
--1.20.25 tested code in notebook and verified it ran
--2.2.25  added code to pull email address for inhouse dialer file requested by matt miller since iep is unable to append directly from identity services call row 49/80
--2.2.25  added code to suppress soft launch records using phone and pseodonym_id
--3.26.25 after discusssion with broader team, changed split from 10 percent holdout to 50 percent holdout
--3.29.25 used ntile to ensure test and holdout are equally split ref https://chatgpt.com/c/67e8c6be-0838-800c-895e-767434bbee0d
--4.4.25  reverted to 10 percent holdout from 45
--4.15.25 just for 4.16 added code to only keep records from 4/15 for today's mail file due to no files sent on april 12 to 15 and high volume expected on 15
--4.16.25 removed condition of 4.15 only --
--01.22.26 add do not called and email consent to the logic

DROP TABLE IF EXISTS cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_pam_ty25;
CREATE TABLE cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_pam_ty25 AS
select distinct
          mp.*
        , pam.pseudonym_id as pseudonym_id
  	, max(case when pam.first_fed_efile_accepted_date is null and pam.first_print_to_mail_date is null then 1 else 0 end) over (partition by pam.pseudonym_id) as flag_file_success
	, pam.tax_year
from cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_raw_ty25 as mp
left join tax_rpt.product_analytics_master as pam
          on cast(mp.auth_id as string) = cast(pam.auth_id as string)
where pam.tax_year = 2025
	and pam.pseudonym_id is not null
	--only include pre-complete audience
	and pam.first_completed_date is null
	and pam.completed_flag = 0
 -- and date(mp.date_end)='2025-04-15'
;

--This table appends on all the customer PII contact information needed for outreach
DROP TABLE IF EXISTS cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_HELPER;
CREATE TABLE cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_HELPER AS
with pii as (select distinct   --1.12.25 removed replace function as inhouse dialer requires +1
          pam.auth_id
          ,b.phonenumbers.primaryphonenumber as phone
          ,b.givenname as first_name
          ,b.familyname as last_name
          ,b.postaladdresses.primarystate as state_code   
	  ,b.emailaddresses.primaryEmailAddress as email_address   
from cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_pam_ty25 as pam
inner join intuit_foundation_identityandcustomer360_unified_dwh.person_account b -- include only those with names;
    on cast(pam.auth_id as string)=cast(b.accountid as string)
      and b.profilestatus = 'ACTIVE'
      and b.accountid is not null
      and b.phonenumbers.primaryphonenumber is not null
      and b.phonenumbers.primaryphonenumber != ''
   
	    ),
        tax_ml as (select distinct
            pam.auth_id as auth_id
          , tax.resident_state as state_code
from cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_pam_ty25 as pam
inner join tax_src.agg_taxml as tax
        on cast(pam.auth_id as string) = cast(tax.auth_id as string)
where tax.tax_year = 2025
	and tax.resident_state is not null
          and tax.resident_state != ''),
  helper_pii as (
    SELECT  billingAccountInformation.accountId as auth_id, MAX(billingAccountInformation.personInformation.name.givenName) as first_name_helper, MAX(billingAccountInformation.personInformation.name.familyName) as last_name_helper
           FROM custeng_commerce_orderprocess.orderv2 WHERE   billingAccountInformation.accountId IS NOT NULL  --and phone_opt_out_ind != 'Y' and gpc_home_phone_opt_out_ind  != 'Y' removed per alexis on 1.16
           GROUP BY 1
 
         )
    select distinct
          pam.*
        , pii.phone
        , coalesce(pii.state_code, tax_ml.state_code) as state_code
        , coalesce(pii.first_name, helper_pii.first_name_helper) as first_name
        , coalesce(pii.last_name, helper_pii.last_name_helper) as last_name
	, email_address
from 
           cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_pam_ty25 as pam
inner join pii on pam.auth_id = pii.auth_id
left join tax_ml on pam.auth_id = tax_ml.auth_id
left join helper_pii on pii.auth_id=helper_pii.auth_id
--suppress those we have already sent out to; comment out day 1 and then uncomment
--left join historical file on pseudo and phone 
left join (select distinct pseudonym_id from cgan_ustax_ws.nlac_ob_sentiment_contact_list_historical_ty25) suppress1 
	on pam.pseudonym_id = suppress1.pseudonym_id
left join (select distinct qualified_auth_id from  cgan_ustax_ws.nlac_ob_sentiment_contact_list_historical_ty25) suppress2  
	on pii.auth_id = suppress2.qualified_auth_id


 
where coalesce(pii.first_name, helper_pii.first_name_helper) is not null 
--uncomment row 74 after day 1
--exclude customers in historical call lists based on pid and phone -- 
	and suppress1.pseudonym_id is null
	and suppress2.qualified_auth_id is null ;

DROP TABLE IF EXISTS cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_final_stg;

CREATE TABLE cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_final_stg AS
WITH deduped AS (
    SELECT
        d.*,
        CAST(current_timestamp AS DATE) AS date_qualified,
        current_timestamp AS ts_qualification
    FROM (
        SELECT
            h.*,
            ROW_NUMBER() OVER (PARTITION BY pseudonym_id ORDER BY first_name) AS rn,
            ROW_NUMBER() OVER (PARTITION BY phone ORDER BY first_name) AS rn_pid
        FROM cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_HELPER h
    ) d
    WHERE rn = 1 AND rn_pid = 1
),
deduped_2 AS (
    SELECT
        *,
        CASE WHEN RAND() <= 0.9 THEN 'Test' ELSE 'Holdout' END AS test_group
    FROM deduped
)
SELECT *
FROM deduped_2;

DROP TABLE IF EXISTS  cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_final;
CREATE TABLE  cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_final AS
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
FROM  cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_final_stg  d
LEFT JOIN consent_phone cp
  ON d.phone = cp.phone
WHERE cp.phone IS NULL;
