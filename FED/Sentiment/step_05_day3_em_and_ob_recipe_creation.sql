--ORINGIALLY WE RECEIVED A FILE FROM CONCENTRIX WHICH TOLD US WHO WAS CONTACTED ON ORIGINAL LIST
--WITH MOVE TO DIALER, AND TO AUTOMATE AND SOURCE DATA FROM A RELIABLE SOURCE WE ARE MOVING TO CHANGE THIS TO PULLING DATA FROM RPT_CCT_INTERACTIONS
--PER GUIDANCE RECEIVED FROM TABLE STEWARD PRAVEEN KURUP VIA SLACK ON 1.14.25 A COMBINATION OF 
--leg_direction='OUTBOUND'; talk_dur+hold_dur=0 and customer_handle_flg=0 indicate that the agent was not able to talk to the customer during that attempt  
--HOWEVER DIALER CALLS ARE CLASSISFIED AS API NOT OUTBOUND SO WE ARE CHANGING THE LOGIC TO JUST LEG QUEUE NAME, TALK+HOLD>60 IN THE CODE IN LINE 27 BELOW
--1.29.25 commented out line 29 since we know that cct only captures data for calls where system detected human not the ones where the call went to vm 
--1.29.25 added logic in line 27 that the call in cct had to be assigned to an agent to exclude the calls where the customer disconnected before speaking to an agent
--2.1.25 alteryx job needed recipe name so added that to the code
--2.8.25 tested and vetted this code
--2.25 erin requested email to be sent day after ob call updated code <=2 to run on 2.26 and then will change to =1 on 2.27
--2.26 changed days between call and email to 1 in code line 45 below per erin


DROP TABLE IF EXISTS cgan_ustax_ws.ob_sentiment_day3_ob_and_em_daily_test_ty25;
CREATE TABLE cgan_ustax_ws.ob_sentiment_day3_ob_and_em_daily_test_ty25 AS

SELECT 
    a.*, 
    CASE 
        WHEN a.test_group = 'Test' THEN 'B - MP OB & Email' 
        ELSE 'A - (Holdout) No intervention or outreach' 
    END AS recipe
FROM  cgan_ustax_ws.nlac_ob_sentiment_contact_list_ty25  a
INNER JOIN tax_rpt.product_analytics_master pam 
    ON a.pseudonym_id = pam.pseudonym_id


-- Join to identify customers who were on the call list but were not contacted
-- Migrated from decommissioned ent_care_7216_dwh.rpt_cct_interactions to care_7216_rpt.rpt_contacts_center
-- Column renames per migration doc:
--   auth_id -> customer_auth_id | tax_year -> tax_year_nbr | bu -> contact_business_unit_code_str
--   leg_queue -> leg_queue_str  | agent_handle_flg -> expert_handled_flag | dt -> contact_start_utc_date
--   ob_campaign_disposition_cd (unchanged)
LEFT JOIN (
    SELECT DISTINCT cct.customer_auth_id AS auth_id
    FROM care_7216_rpt.rpt_contacts_center cct
    WHERE cct.tax_year_nbr = 2025
        AND cct.contact_business_unit_code_str = 'cg' -- contact_business_unit_code_str preserves legacy CCT bu behavior
        AND cct.leg_queue_str = 'cg-us_ps_sentiment_campaign' -- Confirm campaign names in actual file
        AND cct.expert_handled_flag = 1
        AND cct.ob_campaign_disposition_cd = 'HUMAN_ANSWERED'
        -- AND cct.contact_start_utc_date >= '2026-01-24' -- Uncomment if needed
) AS ob_contacted_cct
ON pam.auth_id = ob_contacted_cct.auth_id
WHERE a.test_group = 'Test' 
    AND pam.tax_year = 2025
    AND pam.first_completed_date IS NULL
    and ob_contacted_cct.auth_id IS NULL -- Retain only those in the test group who were not contacted
    -- and a.flag_email_consented = 1 
--  comment out code below in rows 46 on 2.26, uncomment row 43 and change from 2 to 1
    and datediff(cast(current_timestamp as date), cast(date_qualified as date)) = 3
--      and datediff(cast(current_timestamp as date), cast(date_qualified as date)) BETWEEN 1 AND 2;
   ;
