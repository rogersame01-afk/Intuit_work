DROP TABLE IF EXISTS cgan_ustax_ws.TY25_efile_reject_cjo_state_00_braze_email;
CREATE TABLE cgan_ustax_ws.TY25_efile_reject_cjo_state_00_braze_email AS
SELECT DISTINCT
    a.external_user_id                                                                    AS pseudonym_id
  , DATE(from_utc_timestamp(CAST(a.time AS TIMESTAMP), 'America/Los_Angeles'))            AS date_em_sent
  , COALESCE(a.canvas_name, a.campaign_name)                                              AS canvas_name
  , COALESCE(a.canvas_id,   a.campaign_id)                                                AS canvas_id
  , a.canvas_step_name
  , CASE
      WHEN a.canvas_step_name IN ('em_818_null_001', 'em_818_null_003') THEN 'Single State'
      WHEN a.canvas_step_name IN ('em_818_null_002', 'em_818_null_004') THEN 'Everyone Else'
    END                                                                                   AS audience_segment
  , CASE
      WHEN a.canvas_step_name IN ('em_818_null_001', 'em_818_null_003') THEN 'Variant 1'
      WHEN a.canvas_step_name IN ('em_818_null_002', 'em_818_null_004') THEN 'Variant 2'
    END                                                                                   AS canvas_variant                   -- ← state from upstream
  , MAX(CASE WHEN c.external_user_id IS NOT NULL AND c.url NOT LIKE '%account-manager%' THEN 1 ELSE 0 END)
      OVER (PARTITION BY a.external_user_id)                                              AS em_clicked_flag
  , MAX(CASE WHEN c.external_user_id IS NOT NULL AND c.url     LIKE '%account-manager%' THEN 1 ELSE 0 END)
      OVER (PARTITION BY a.external_user_id)                                              AS em_unsubscribe_flag

FROM tax_src.src_braze_turbotax_email_delivery AS a

LEFT JOIN tax_src.src_braze_turbotax_email_click AS c
  ON  a.external_user_id = c.external_user_id
  AND a.canvas_id        = c.canvas_id

LEFT JOIN cgan_ustax_ws.Saves_states_efile_reject_ty25_00_ajo_analytics_destination AS base
  ON a.external_user_id = base.pseudonym_id   -- ← pulls state per user

WHERE a.year         = 2026
  AND a.canvas_id    = '2f9b4865-857b-42ad-b54d-20fd627d2a79'
  AND a.canvas_name  LIKE '%818_CSO_TY25-State-efile-reject-Auto_3k_LOW_EM%'
  AND a.canvas_step_name IN (
      'em_818_null_001'
    , 'em_818_null_002'
    , 'em_818_null_003'
    , 'em_818_null_004'
  );
 DROP TABLE IF EXISTS cgan_ustax_ws.TY25_efile_reject_cjo_state_00_braze_sms;
CREATE TABLE cgan_ustax_ws.TY25_efile_reject_cjo_state_00_braze_sms as 
 select
    em.external_user_id as pseudonym_id,
    cast(em.time as timestamp) as ts_send,
    date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) as first_send_dt_la,
    case when d.external_user_id is not null then 1 else 0 end as delivered_flag
  from tax_src.src_braze_turbotax_sms_send em
 LEFT JOIN (
  SELECT DISTINCT
      external_user_id
    , canvas_id
    , canvas_step_name
  FROM tax_src.src_braze_turbotax_sms_delivery
) d
  ON d.external_user_id = em.external_user_id
 AND d.canvas_id        = em.canvas_id
 AND d.canvas_step_name = em.canvas_step_name
  where em.year = 2026
    and em.canvas_name ='818_CSO_TY25-State-efile-reject-Auto_3k_LOW_EM'
    and em.canvas_step_name ='sms_818_null_001';

