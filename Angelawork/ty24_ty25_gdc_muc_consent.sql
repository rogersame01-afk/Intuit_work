drop table if exists cgan_ustax_published.Consents_by_AUTH_ty25_ty24;

create table cgan_ustax_published.Consents_by_AUTH_ty25_ty24 using parquet as -- using parquet so it is easy to query from

select * from 
(
SELECT 
         auth_id ,tax_year 
        ,MAX(gave_consent_Global_Disclosure_7216) AS gave_consent_Global_Disclosure_7216
        ,MAX(gave_consent_Global_Use_7216) AS gave_consent_Global_Use_7216
        
        ,MAX(gave_consent_RT_Disclosure_7216) AS gave_consent_RT_Disclosure_7216
        ,MAX(gave_consent_RT_Use_7216) AS gave_consent_RT_Use_7216
        
        ,MAX(gave_consent_CKMoney_Disclosure_7216) AS gave_consent_CKMoney_Disclosure_7216
        ,MAX(gave_consent_CKMoney_Use_7216) AS gave_consent_CKMoney_Use_7216

        ,MAX(gave_consent_RAD_Disclosure_7216) AS gave_consent_RAD_Disclosure_7216
        ,MAX(gave_consent_RAD_Use_7216) AS gave_consent_RAD_Use_7216
        
        ,MAX(gave_consent_Direct_debit_7216) AS gave_consent_Direct_debit_7216
               
FROM
  (
        SELECT
                CAST(a.ownerid AS varchar(1000)) AS auth_id
               ,CASE WHEN (a.purpose  = 'Global7216' AND a.consenttype = '7216-Disclosure') THEN 1 ELSE 0 END AS gave_consent_Global_Disclosure_7216
               ,CASE WHEN (a.purpose  = 'Personalization' AND a.consenttype = '7216-Use') THEN 1 ELSE 0 END AS gave_consent_Global_Use_7216
               
               ,CASE WHEN (a.purpose  = 'RT7216' AND a.consenttype = '7216-Disclosure') THEN 1 ELSE 0 END AS gave_consent_RT_Disclosure_7216
               ,CASE WHEN (a.purpose  = 'RT7216' AND a.consenttype = '7216-Use') THEN 1 ELSE 0 END AS gave_consent_RT_Use_7216
               
               ,CASE WHEN (a.purpose  = 'CKMoney7216' AND a.consenttype = '7216-Disclosure') THEN 1 ELSE 0 END AS gave_consent_CKMoney_Disclosure_7216
               ,CASE WHEN (a.purpose  = 'CKMoney7216' AND a.consenttype = '7216-Use') THEN 1 ELSE 0 END AS gave_consent_CKMoney_Use_7216
               
               ,CASE WHEN (a.purpose  = 'RAD7216' AND a.consenttype = '7216-Disclosure') THEN 1 ELSE 0 END AS gave_consent_RAD_Disclosure_7216
               ,CASE WHEN (a.purpose  = 'RAD7216' AND a.consenttype = '7216-Use') THEN 1 ELSE 0 END AS gave_consent_RAD_Use_7216
               
               ,CASE WHEN (a.purpose  = 'BalanceDue' AND a.consenttype = 'direct-debit') THEN 1 ELSE 0 END AS gave_consent_Direct_debit_7216
               
               ,a.consented
               ,CAST(b.tax_year AS BIGINT) AS tax_year
               ,row_number() OVER (PARTITION BY a.ownerid, b.tax_year, a.purpose, a.consenttype
                                   ORDER BY a.modifieddate DESC) AS auth_rn
         FROM dlprd.thrive_dwh.ctodev_consent_appevents a
         JOIN dlprd.common_dm.dim_cg_date b ON CAST(a.startdate AS DATE) = CAST(b.tax_pt_date AS DATE)
         WHERE 
                     a.purpose  IN ('Global7216', 'Personalization','RT7216','BalanceDue',
                                   'CKMoney7216','RAD7216')
                 AND a.consenttype IN ('7216-Use', '7216-Disclosure','direct-debit')
                 AND upper(cast(a.consented as varchar(1000))) = 'TRUE'
                 AND a.ownerid NOT IN ('test')
                 AND a.ownertype = 'USER' -- To get the AUTHIDs
                 AND CAST(a.ownerid AS varchar(1000)) is not null
                and CAST(b.tax_year as bigint) in (2024,2025) 
  ) consent_init
WHERE auth_rn = 1
group by 1,2
) Z;



drop table if exists cgan_ustax_ws.Consents_daily_clickstream_ty25;

CREATE TABLE cgan_ustax_ws.Consents_daily_clickstream_ty25 as
select * from
(
Select distinct
       pseudonym_id,
       a.tax_year,
       date(from_utc_timestamp(from_unixtime(event_ts), 'America/Los_Angeles')) as event_dt,
       (from_utc_timestamp(from_unixtime(event_ts), 'America/Los_Angeles')) as event_ts_adj,
       event_ts,
       scope_area,
       screen,
       ui_object_detail
FROM tax_src.fact_clickstream_psd a
where a.tax_year  in ( '2025')
 and   load_date >= '2025120100'
   and load_date < '2026123100'
and
(
lower(screen) like '%7216%use%' or lower(screen) like ('%gtkm%use%consent%' ) 
or lower(ui_object_detail) like ('%7216%use%agree%') or lower(ui_object_detail) like ('%7216%use%decline%')
or lower(ui_object_detail) like ('%7216%disclosure%agree%') or lower(ui_object_detail) like ('%7216%disclosure%decline%') or
lower(screen) like '%7216%disclosure%' or lower(screen) like ('%gtkm%disclosure%consent%' ) or
lower(screen) like '%refund%transfer%use%consent%' or 
lower(screen) like '%rt%registration%disclosure%consent%' or 
lower(screen) like '%fast%money%consent%' or 
lower(screen) like '%fast%money%disclosure%' or 
lower(screen) like '%direct%debit%consent%' or 
screen in ('ccConsent' ) or 

screen in ('consent_v3_RAD_Use','consent_v3_RAD-Use','ral-use-consent','rad-use-consent') or
screen in ('consent_v3_RAD_Disclosure','consent_v3_RAD-Disclosure','ral-disclosure-consent','rad-disclosure-consent') or

screen in ('consent_v3_CKMoney_Use','consent_v3_CKMoney-Use','refund-ck-money-use-consent','CKMoney-Use_right_panel_v2') or
screen in ('consent_v3_CKMoney_Disclosure','consent_v3_CKMoney-Disclosure','consent_v3_CKMoney-Disclosure',
           'refund-ck-money-disclosure-consent','CKMoney-Disclosure_right_panel_v2','refund-ck-money-all-consents',
           'refund-ck-money-disclosure-consent' 
           ) or

lower(screen) like '%consent%file%common%view%id%' or 
lower(screen) like '%tax%id%activation%consent%' 
              or
(  
lower(scope_area) LIKE '%file%'
  OR lower(scope_area) LIKE '%shopping%'
   OR lower(scope_area) LIKE '%payment%processing%'
    OR lower(scope_area) LIKE '%social%flow%'
    OR lower(scope_area) LIKE '%post%file%'
  OR screen in ('filing_mojo_landing','fnf_landing','apple_pay','cart','ryo',
                'Google_Pay','payment.payOptions.PaymentMethod.CreditCard','payment-confirmation-view','/unified/2023/index/tto')
  OR lower(screen) like '%refund%transfer%use%consent%' or 
lower(screen) like '%refund-transfer-use-consent%dont%agree%' or 
lower(screen) like '%rt%registration%disclosure%consent%' or 
lower(screen) like '%fast%money%consent%' or 
lower(screen) like '%fast%money%disclosure%' or 
lower(screen) like '%direct%debit%consent%' or 
screen in ('ccConsent' ) or 

screen in ('consent_v3_CKMoney_Use','consent_v3_CKMoney-Use','refund-ck-money-use-consent','CKMoney-Use_right_panel_v2') or
screen in ('consent_v3_CKMoney_Disclosure','consent_v3_CKMoney-Disclosure','consent_v3_CKMoney-Disclosure',
           'refund-ck-money-disclosure-consent','CKMoney-Disclosure_right_panel_v2','refund-ck-money-all-consents',
           'refund-ck-money-disclosure-consent' 
           ) or

lower(screen) like '%consent%file%common%view%id%' or 
lower(screen) like '%tax%id%activation%consent%' 
)
)
       ) Z
;


drop table if exists cgan_ustax_ws.Consents_clickstream_flags_ty25_ty24;

CREATE TABLE cgan_ustax_ws.Consents_clickstream_flags_ty25_ty24 as
select * from
(
with base as
(select * from dlprd.cgan_ustax_ws.Consents_daily_clickstream_ty24
UNION ALL
select * from dlprd.cgan_ustax_ws.Consents_daily_clickstream_ty25)
SELECT
tax_year, pseudonym_id,

max(case when (screen  in ('7216-Disclosure_right_panel_v2','consent_v3_7216-Disclosure') or
               lower(screen) like '%7216%disclosure%'or
               lower(ui_object_detail) like ('%7216%disclosure%agree%')or
             lower(ui_object_detail) like ('%7216%disclosure%decline%'))
         then 1 else 0 end) as Global_7216_Disclosure_CS_View,

max(case when ((screen = '7216-Disclosure_right_panel_v2' AND ui_object_detail = '7216-Disclosure_decline' ) or 
            (screen = 'consent_v3_7216-Disclosure' AND ui_object_detail = '7216-Disclosure_decline') or
             lower(ui_object_detail) like ('%7216%disclosure%decline%')
         )
              then 1 else 0 end) as Global_7216_Disclosure_CS_Decline,

max(case when ((screen = '7216-Disclosure_right_panel_v2' AND ui_object_detail = '7216-Disclosure_agree-error') or
               (screen = '7216-Disclosure_right_panel_v2' AND ui_object_detail = '7216-Disclosure_agree' ) or
               (screen = 'consent_v3_7216-Disclosure' AND ui_object_detail = 'consent_agree' ) or
               lower(ui_object_detail) like ('%7216%disclosure%agree%'))
                 then 1 else 0 end) as Global_7216_Disclosure_CS_Agree,
                 
max(case when (screen  in ('7216-Use_right_panel_v2' ,'gtkm_multi_use_consent') or
               lower(screen) like '%7216%use%' or
             lower(ui_object_detail) like ('%7216%use%decline%') or
               lower(ui_object_detail) like ('%7216%use%agree%') )
              then 1 else 0 end) as Global_7216_Use_CS_View,

max(case when ((screen = '7216-Use_right_panel_v2' AND ui_object_detail = '7216-Use_decline' ) or
               (screen = 'gtkm_multi_use_consent' AND ui_object_detail = '7216_Consent-views-No-Thanks' )or
             lower(ui_object_detail) like ('%7216%use%decline%')         
         ) 
                then 1 else 0 end) as Global_7216_Use_CS_Decline,

max(case when ((screen = '7216-Use_right_panel_v2' AND ui_object_detail = '7216-Use_agree-error' ) or
                (screen = '7216-Use_right_panel_v2' AND ui_object_detail = '7216-Use_agree' )or
               lower(ui_object_detail) like ('%7216%use%agree%')
         )
                  then 1 else 0 end) as Global_7216_Use_CS_Agree,

max(case when screen  in ('refund-transfer-use-consent-view') then 1 else 0 end) as RT_Use_CS_View,

max(case when ((screen = 'refund-transfer-use-consent-view' AND ui_object_detail = 'refund-transfer-use-consent-cancel')  or
               (screen = 'refund-transfer-use-consent-dontAgree' AND ui_object_detail = 'refund-transfer-use-consent-dontAgree-continue')  or
               (screen = 'refund-transfer-use-consent-view' AND ui_object_detail like 'refund-transfer-use-consent%dont%Agree%')  or
               (screen = 'refund-transfer-use-consent-view' AND ui_object_detail like 'refund-transfer-use-consent%decline%'))
                  then 1 else 0 end) as RT_Use_CS_Decline,
         
max(case when ((screen='refund-transfer-use-consent-view' and ui_object_detail= 'refund-transfer-use-consent-continue' ) OR
              (screen = 'refund-transfer-use-consent-view' AND ui_object_detail = 'refund-transfer-use-consent-agree' ) ) 
                   then 1 else 0 end) as RT_Use_CS_Agree,

max(case when screen  in ('rt-registration-disclosure-consent-view' ) then 1 else 0 end) as RT_Disclosure_CS_View,
max(case when ((screen = 'rt-registration-disclosure-consent-view' AND ui_object_detail = 'rt-registration-disclosure-consent-choice-dont-agree') or
               (screen = 'rt-registration-disclosure-consent-view' AND ui_object_detail = 'rt-registration-disclosure-consent%cancel%') or
               (screen = 'rt-registration-disclosure-consent-view' AND ui_object_detail = 'rt-registration-disclosure-consent-decline'))
                   then 1 else 0 end) as RT_Disclosure_CS_Decline, 
max(case when ((screen = 'rt-registration-disclosure-consent-view' AND ui_object_detail = 'rt-registration-disclosure-consent-choice-agree' ) or 
               (screen = 'rt-registration-disclosure-consent-view' AND ui_object_detail = 'rt-registration-disclosure-consent-agree' ))
                  then 1 else 0 end) as RT_Disclosure_CS_Agree,

max(case when screen  in ('CKMoney-Disclosure_right_panel_v2' ,'consent_v3_CKMoney-Disclosure', 'refund-ck-money-disclosure-consent') 
                         then 1 else 0 end) as CkMoney_Disclosure_CS_View,
max(case when ((screen = 'CKMoney-Disclosure_right_panel_v2' AND ui_object_detail = 'CKMoney-Disclosure_decline'  ) or
               (screen = 'consent_v3_CKMoney-Disclosure' AND ui_object_detail = 'CKMoney-Disclosure_decline' ) or 
               (screen = 'refund-ck-money-disclosure-consent' AND ui_object_detail = 'refund-ck-money-disclosure-consent-dontAgree'))  
               then 1 else 0 end) as CKMoney_Disclosure_CS_Decline,

max(case when ((screen = 'CKMoney-Disclosure_right_panel_v2' AND ui_object_detail = 'CKMoney-Disclosure_agree-error'  ) or 
               (screen = 'CKMoney-Disclosure_right_panel_v2' AND ui_object_detail = 'CKMoney-Disclosure_agree'   ) or
               (screen = 'consent_v3_CKMoney-Disclosure' AND ui_object_detail = 'consent_agree'   ) or
               (screen = 'refund-ck-money-disclosure-consent' AND ui_object_detail = 'refund-ck-money-disclosure-consent-agree' )) 
                then 1 else 0 end) as CKMoney_Disclosure_CS_Agree,

max(case when screen  in ('CKMoney-Use_right_panel_v2', 'consent_v3_CKMoney-Use') 
                         then 1 else 0 end) as CkMoney_Use_CS_View,
max(case when ((screen = 'CKMoney-Use_right_panel_v2' AND ui_object_detail = 'CKMoney-Use_decline'  ) or 
               (screen = 'consent_v3_CKMoney-Use' AND ui_object_detail = 'CKMoney-Use_decline' )) 
                then 1 else 0 end) as CKMoney_Use_CS_Decline,

max(case when ((screen = 'CKMoney-Use_right_panel_v2' AND ui_object_detail = 'CKMoney-Use_agree-error'   ) or 
               (screen = 'CKMoney-Use_right_panel_v2' AND ui_object_detail = 'CKMoney-Use_agree'  ) or  
               (screen = 'consent_v3_CKMoney-Use' AND ui_object_detail = 'consent_agree' )) 
                then 1 else 0 end) as CKMoney_Use_CS_Agree,

max(case when screen  in ('consent_v3_RAD-Disclosure', 'ral-disclosure-consent') 
                         then 1 else 0 end) as RAD_Disclosure_CS_View,
                         
max(case when ((screen = 'consent_v3_RAD-Disclosure' AND ui_object_detail = 'RAD-Disclosure_decline'  ) or  
               (screen = 'ral-disclosure-consent' AND ui_object_detail = 'ral-disclosure-consent-dontAgree' )) 
                then 1 else 0 end) as RAD_Disclosure_CS_Decline,

max(case when ((screen = 'consent_v3_RAD-Disclosure' AND ui_object_detail = 'consent_agree') or 
               (screen = 'ral-disclosure-consent' AND ui_object_detail = 'ral-disclosure-consent-agree' )) 
                then 1 else 0 end) as RAD_Disclosure_CS_Agree,

max(case when screen  in ('consent_v3_RAD-Use', 'ral-use-consent') 
                         then 1 else 0 end) as RAD_Use_CS_View,
                         
max(case when ((screen = 'consent_v3_RAD-Use' AND ui_object_detail = 'RAD-Use_decline' )or
               (screen = 'ral-use-consent' and ui_object_detail = 'ral-use-consent-dontAgree' )) 
                then 1 else 0 end) as RAD_Use_CS_Decline,

max(case when ((screen = 'consent_v3_RAD-Use' AND ui_object_detail = 'consent_agree' ) or 
               (screen = 'ral-use-consent' and ui_object_detail = 'ral-use-consent-agree')) 
                then 1 else 0 end) as RAD_Use_CS_Agree, 

max(case when screen  in ('ccConsent') 
                         then 1 else 0 end) as CC_Consent_CS_View,
                                                  
max(case when ((screen = 'ccConsent' AND ui_object_detail = 'action-dontagree' )or
               (screen = 'ccConsent' AND ui_object_detail = 'action-prev-0' ))
                then 1 else 0 end) as CC_CS_Decline,
max(case when ((screen = 'ccConsent' AND ui_object_detail = 'action-next' ) or 
               (screen = 'ccConsent' AND ui_object_detail like 'action%next%' )or 
               (screen = 'ccConsent' AND ui_object_detail = 'ccConsent-action-agree-button' ) or 
              (screen = 'ccConsent' AND ui_object_detail like 'ccConsent%agree%' )) 
                then 1 else 0 end) as CC_CS_Agree,

max(case when screen  in ('consent-to-file-common-view-id') 
                         then 1 else 0 end) as State_Consent_CS_View,
max(case when ((screen = 'consent-to-file-common-view-id' AND ui_object_detail = 'consent-file-common-back'  ) or 
               (screen = 'consent-to-file-common-view-id' AND ui_object_detail = 'consent-to-file-common-back' ) or  
               (screen = 'consent-to-file-common-view-id' AND ui_object_detail = 'consent-to-file-common-back-label-action' ) or  
               (screen = 'consent-to-file-common-view-id' AND ui_object_detail = 'consent-file-continue-back'  ) or 
               (screen = 'consent-to-file-common-view-id' AND ui_object_detail = 'Not now' )) 
                then 1 else 0 end) as State_CS_Decline,
               
max(case when ((screen = 'consent-to-file-common-view-id' AND ui_object_detail = 'consent-to-file-common-continue-label-action'  ) or  
               (screen = 'consent-to-file-common-view-id' AND ui_object_detail like 'consent-to-file%%agree'   ) or 
               (screen = 'consent-to-file-common-view-id' AND ui_object_detail = 'consent-to-file-common-continue' )) 
                then 1 else 0 end) as State_CS_Agree,
         
max(case when screen  in ('consent_v3_fast-money-consent') 
                         then 1 else 0 end) as FiveDE_Use_CS_View,
max(case when (screen = 'consent_v3_fast-money-consent' AND ui_object_detail = 'fast-money-consent_decline' ) 
                then 1 else 0 end) as FiveDE_Use_CS_Decline,
max(case when (screen = 'consent_v3_fast-money-consent' AND ui_object_detail = 'consent_agree' ) 
                then 1 else 0 end) as FiveDE_Use_CS_Agree,

max(case when screen  in ('consent_v3_fast-money-disclosure') 
                         then 1 else 0 end) as FiveDE_Disclosure_CS_View,
max(case when (screen = 'consent_v3_fast-money-disclosure' AND ui_object_detail = 'fast-money-disclosure_decline' ) 
                then 1 else 0 end) as FiveDE_Disclosure_CS_Decline,
max(case when (screen = 'consent_v3_fast-money-disclosure' AND ui_object_detail = 'consent_agree')
                then 1 else 0 end) as FiveDE_Disclosure_CS_Agree, 

max(case when screen  in ('direct-debit-consent') 
                         then 1 else 0 end) as DirectDebit_Consent_CS_View,
max(case when ((screen = 'direct-debit-consent' AND ui_object_detail = 'direct-debit-action-dontagree-button'  ) or  
               (screen = 'direct-debit-consent' AND ui_object_detail = 'direct-debit-action-dontagree-label-action' )) 
                then 1 else 0 end) as DirectDebit_CS_Decline,
max(case when ((screen = 'direct-debit-consent' AND ui_object_detail = 'direct-debit-action-agree-button' ) or
               (screen = 'direct-debit-consent' AND ui_object_detail = 'direct-debit-action-next-button' ))
                then 1 else 0 end) as DirectDebit_CS_Agree,

max(case when screen  in ('tax-id-activation-consent-view' ) 
                         then 1 else 0 end) as CSID_Consent_CS_View,
max(case when ((screen = 'tax-id-activation-consent-view' AND ui_object_detail = 'tax-id-activation-consent-choice-dont-agree' ) or
               (screen = 'tax-id-activation-consent-view' AND ui_object_detail = 'tax-id-activation-consent-decline' ) or
               (screen = 'tax-id-activation-consent-view' AND ui_object_detail = 'tax-id-activation-consent-cancel' ) )
                then 1 else 0 end) as CSID_CS_Decline,
max(case when ((screen = 'tax-id-activation-consent-view' AND ui_object_detail = 'tax-id-activation-consent-agree' ) or
               (screen = 'tax-id-activation-consent-view' AND ui_object_detail = 'tax-id-activation-consent-choice-agree' )) 
                then 1 else 0 end) as CSID_CS_Agree
                
                from base                
                group by 1,2
                ) Z;


drop table if exists cgan_ustax_ws.Consents_analytics_master_ty25_ty24;

CREATE TABLE cgan_ustax_ws.Consents_analytics_master_ty25_ty24 as
select * from
(
       
 with 
   pam AS (
    SELECT
      auth_id,
      tax_year,
        pseudonym_id
        FROM
      dlprd.tax_rpt.product_analytics_master
    WHERE
      tax_year  in (2025,2024 )
      ),
cs_consent as
(select * from cgan_ustax_ws.Consents_clickstream_flags_ty25_ty24 )
 ,
 event_consent as
   (select * FROM dlprd.cgan_ustax_published.Consents_by_AUTH_ty25_ty24  )  
    
select     pam.*,

case when (cs_consent.global_7216_disclosure_cs_view=1) then 1 else 0 end as global_7216_disclosure_consent_view,
case when (cs_consent.global_7216_disclosure_cs_decline=1) then 1 else 0 end as global_7216_disclosure_consent_decline,
case when (cs_consent.global_7216_disclosure_cs_agree =1 or event_consent.gave_consent_Global_Disclosure_7216 =1 )  then 1 else 0 end as global_7216_disclosure_consent_agree,

case when (cs_consent.global_7216_use_cs_view=1) then 1 else 0 end as global_7216_use_consent_view,
case when (cs_consent.global_7216_use_cs_decline=1) then 1 else 0 end as global_7216_use_consent_decline,
case when (cs_consent.global_7216_use_cs_agree =1 or event_consent.gave_consent_Global_Use_7216=1) then 1 else 0 end as global_7216_use_consent_agree,

case when (cs_consent.rt_use_cs_view=1) then 1 else 0 end as Refund_transfer_use_consent_view,
case when (cs_consent.rt_use_cs_decline=1) then 1 else 0 end as Refund_transfer_use_consent_decline,
case when (cs_consent.rt_use_cs_agree =1 or event_consent.gave_consent_RT_Use_7216=1) then 1 else 0 end as Refund_transfer_use_consent_agree,

case when (cs_consent.rt_disclosure_cs_view=1) then 1 else 0 end as Refund_transfer_disclosure_consent_view,
case when (cs_consent.rt_disclosure_cs_decline=1) then 1 else 0 end as Refund_transfer_disclosure_consent_decline,
case when (cs_consent.rt_disclosure_cs_agree =1 or event_consent.gave_consent_RT_Disclosure_7216=1) then 1 else 0 end as Refund_transfer_disclosure_consent_agree,

case when (cs_consent.ckmoney_use_cs_view=1) then 1 else 0 end as CkMoney_use_consent_view,
case when (cs_consent.ckmoney_use_cs_decline=1) then 1 else 0 end as CkMoney_use_consent_decline,
case when (cs_consent.ckmoney_use_cs_agree=1 or event_consent.gave_consent_CKMoney_Use_7216=1) then 1 else 0 end as CkMoney_use_consent_agree,

case when (cs_consent.ckmoney_disclosure_cs_view=1) then 1 else 0 end as CkMoney_disclosure_consent_view,
case when (cs_consent.ckmoney_disclosure_cs_decline=1) then 1 else 0 end as CkMoney_disclosure_consent_decline,
case when (cs_consent.ckmoney_disclosure_cs_agree =1 or event_consent.gave_consent_CKMoney_Disclosure_7216=1) then 1 else 0 end as CkMoney_disclosure_consent_agree,

case when (cs_consent.rad_use_cs_view=1) then 1 else 0 end as RAD_use_consent_view,
case when (cs_consent.rad_use_cs_decline=1) then 1 else 0 end as RAD_use_consent_decline,
case when (cs_consent.rad_use_cs_agree=1 or event_consent.gave_consent_RAD_Use_7216=1) then 1 else 0 end as RAD_use_consent_agree,

case when (cs_consent.rad_disclosure_cs_view=1) then 1 else 0 end as RAD_disclosure_consent_view,
case when (cs_consent.rad_disclosure_cs_decline=1) then 1 else 0 end as RAD_disclosure_consent_decline,
case when (cs_consent.rad_disclosure_cs_agree=1 or event_consent.gave_consent_RAD_Disclosure_7216=1) then 1 else 0 end as RAD_disclosure_consent_agree,

case when (cs_consent.cc_consent_cs_view=1) then 1 else 0 end as Credit_card_consent_view,
case when (cs_consent.cc_cs_decline=1) then 1 else 0 end as Credit_card_consent_decline,
case when (cs_consent.cc_cs_agree=1) then 1 else 0 end as Credit_card_consent_agree,

case when (cs_consent.state_consent_cs_view=1) then 1 else 0 end as State_consent_view,
case when (cs_consent.state_cs_decline=1) then 1 else 0 end as State_consent_decline,
case when (cs_consent.state_cs_agree=1) then 1 else 0 end as State_consent_agree,

case when (cs_consent.fivede_use_cs_view=1) then 1 else 0 end as fivede_use_consent_view,
case when (cs_consent.fivede_use_cs_decline=1) then 1 else 0 end as fivede_use_consent_decline,
case when (cs_consent.fivede_use_cs_agree=1) then 1 else 0 end as fivede_use_consent_agree,

case when (cs_consent.fivede_disclosure_cs_view=1) then 1 else 0 end as fivede_disclosure_consent_view,
case when (cs_consent.fivede_disclosure_cs_decline=1) then 1 else 0 end as fivede_disclosure_consent_decline,
case when (cs_consent.fivede_disclosure_cs_agree=1) then 1 else 0 end as fivede_disclosure_consent_agree,

case when (cs_consent.directdebit_consent_cs_view=1) then 1 else 0 end as Direct_debit_consent_view,
case when (cs_consent.directdebit_cs_decline=1) then 1 else 0 end as Direct_debit_consent_decline,
case when (cs_consent.directdebit_cs_agree=1 or event_consent.gave_consent_Direct_debit_7216=1) then 1 else 0 end as Direct_debit_consent_agree,

case when (cs_consent.csid_consent_cs_view=1) then 1 else 0 end as CSID_consent_view,
case when (cs_consent.csid_cs_decline=1) then 1 else 0 end as CSID_consent_decline,
case when (cs_consent.csid_cs_agree=1) then 1 else 0 end as CSID_consent_agree

from pam
   LEFT JOIN cs_consent on cast(pam.pseudonym_id as varchar(1000))=cast(cs_consent.pseudonym_id as varchar(1000)) and cast(pam.tax_year as bigint)=cast(cs_consent.tax_year as bigint)
   LEFT JOIN event_consent on cast(pam.auth_id as varchar(1000))=cast(event_consent.auth_id as varchar(1000)) and cast(pam.tax_year as bigint)=cast(event_consent.tax_year as bigint)
) 
Z;
