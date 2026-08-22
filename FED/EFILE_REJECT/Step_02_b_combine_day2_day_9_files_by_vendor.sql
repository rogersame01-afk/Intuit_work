drop table if exists cgan_ustax_ws.efile_rejects_epc_ty25_cjo_final_concentrix_days_2_and_9;
create table cgan_ustax_ws.efile_rejects_epc_ty25_cjo_final_concentrix_days_2_and_9
as 
WITH combined_data AS (
    SELECT * FROM cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_consent WHERE vendor='Concentrix'
    UNION ALL
    SELECT * FROM cgan_ustax_ws.efile_rejects_epc_day1_with_consent_ty25 WHERE vendor='Concentrix'
),
  
deduplicated AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY phone, pseudonym_id ORDER BY dt DESC) AS rn_new
    FROM combined_data
)
  
SELECT * FROM deduplicated WHERE rn_new = 1
  ;
