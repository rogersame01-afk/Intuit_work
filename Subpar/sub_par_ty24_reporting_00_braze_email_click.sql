DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_click;

CREATE TABLE cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_click AS
SELECT DISTINCT
    a.pseudonym_id,
    a.issue_type,
    a.cell,
    a.date_issue,
    a.datetime_qualified,
    a.date_qualified,
    a.mpm,
  --  a.copy_type,
    a.dt,
    a.mpm_cell,

    -- Email click tracking metrics
    CASE 
        WHEN cl.external_user_id IS NOT NULL AND cl.url NOT LIKE '%account-manager%' THEN 1 
        ELSE 0 
    END AS flag_click,  

    CASE 
        WHEN cl.external_user_id IS NOT NULL AND cl.url LIKE '%account-manager%' THEN 1 
        ELSE 0 
    END AS flag_click_unsubscribe

FROM cgan_ustax_ws.sub_par_ty24_00_em_historical AS a
LEFT JOIN tax_src.src_braze_turbotax_email_send AS em
    ON a.pseudonym_id = em.external_user_id   
    AND em.year = 2025  
    AND em.canvas_id = '581c52df-01e9-46b8-b0cc-3d3d63739140'
LEFT JOIN tax_src.src_braze_turbotax_email_click AS cl
    ON cl.external_user_id = em.external_user_id
    AND em.canvas_id = cl.canvas_id
    AND em.canvas_step_name = cl.canvas_step_name
    -- Click within 7 days of the touchpoint
    -- AND DATEDIFF(
    --     day, 
    --     FROM_UTC_TIMESTAMP(TIMESTAMP 'epoch' + em.time * INTERVAL '1 second', 'America/Los_Angeles'),
    --     FROM_UTC_TIMESTAMP(TIMESTAMP 'epoch' + cl.time * INTERVAL '1 second', 'America/Los_Angeles')
    -- ) BETWEEN 0 AND 7
    ;
