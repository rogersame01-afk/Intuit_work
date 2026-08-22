DROP TABLE IF EXISTS cgan_ustax_ws.dailer_catch_up_0411_0416_aw;

CREATE TABLE cgan_ustax_ws.dailer_catch_up_0411_0416_aw AS

WITH BASE_DAILER_USERS AS (
    SELECT DISTINCT 
        first_name, last_name, email AS email_address, pseudonym_id, DT, phone AS Address,
        'FED_EFILE_REJECT' AS intuCallType, 'ACTIVE' AS EndpointStatus
    FROM cgan_ustax_ws.efile_rejects_day1_epc_ty25_cjo_staging_pftsv2_stg_1
    WHERE dt BETWEEN '2026-04-11' AND '2026-04-16'

    UNION

    SELECT DISTINCT 
        first_name, last_name, email AS email_address, pseudonym_id, DT, phone AS Address,
        'FED_EFILE_REJECT' AS intuCallType, 'ACTIVE' AS EndpointStatus
    FROM cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2
    WHERE dt BETWEEN '2026-04-11' AND '2026-04-16'
),

BASE_DAILER_USERS_DEPUDED AS (
    SELECT DISTINCT
        a.first_name, a.last_name, a.email_address, a.Address, intuCallType, EndpointStatus,
        a.pseudonym_id,
        b.accountid AS auth_id,
        a.DT,
        ROW_NUMBER() OVER (PARTITION BY a.pseudonym_id ORDER BY a.DT DESC) AS row_num
    FROM BASE_DAILER_USERS a
    INNER JOIN intuit_foundation_identityandcustomer360_unified_dwh.person_account b
        ON CAST(a.pseudonym_id AS STRING) = CAST(b.digitalidentitypseudonymid AS STRING)
        AND b.profilestatus = 'ACTIVE'
        AND b.accountid IS NOT NULL
),

AUDIENCE_NOT_SENT_TO_DIALER AS (
    SELECT a.*
    FROM BASE_DAILER_USERS_DEPUDED a
    LEFT JOIN cgan_ustax_ws.tmp_ta_filingids_20260417 b
        ON a.auth_id = b.auth_id
    WHERE b.auth_id IS NULL
      AND row_num = 1
),

AUDIENCE_NOT_SENT_TO_DIALER_THAT_HAVE_NOT_REFILED AS (
    SELECT *
    FROM (
        SELECT
            a.*,
            COALESCE(pam.first_fed_efile_accepted_date, pam.first_print_to_mail_date) AS date_fed_file_success_new
        FROM AUDIENCE_NOT_SENT_TO_DIALER a
        LEFT JOIN tax_rpt.product_analytics_master pam
            ON a.pseudonym_id = pam.pseudonym_id
            AND pam.tax_year = 2025
    ) subquery
    WHERE date_fed_file_success_new IS NULL
),

RT_FDE_ATTACH AS (
    SELECT
        mam.auth_id,
        mam.fde_attach_flag,
        mam.rt_attach_flag
    FROM tax_rpt.monetization_analytics_master mam
    WHERE mam.tax_year = 2025
      AND (mam.rt_attach_flag = 1 OR mam.fde_attach_flag = 1)
)

SELECT
    A.*
FROM AUDIENCE_NOT_SENT_TO_DIALER_THAT_HAVE_NOT_REFILED A
LEFT JOIN RT_FDE_ATTACH B
    ON A.auth_id = B.auth_id
WHERE rt_attach_flag = 1 OR fde_attach_flag = 1;
