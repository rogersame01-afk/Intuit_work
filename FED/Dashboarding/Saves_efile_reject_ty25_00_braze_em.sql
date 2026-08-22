DROP TABLE IF EXISTS cgan_ustax_ws.Saves_efile_reject_ty25_00_braze_em;
CREATE TABLE cgan_ustax_ws.Saves_efile_reject_ty25_00_braze_em as 
select distinct
  external_user_id as pseudonym_id
, date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) as date_em_sent
, coalesce(em.canvas_name, em.campaign_name) as canvas_name
, coalesce(em.canvas_id, em.campaign_id) as canvas_id
, em.canvas_step_name
, case
    when em.canvas_step_name IN ('em_60014_NULL_001') then 'F8962-070'
    when em.canvas_step_name IN ('em_60014_NULL_002') then 'IND-181-01'
    when em.canvas_step_name IN ('em_60014_NULL_003') then 'IND-031-04'
    when em.canvas_step_name IN ('em_60014_NULL_004') then 'F1040-516-01'
    when em.canvas_step_name IN ('em_60014_NULL_005') then 'IND-032-04'
    when em.canvas_step_name IN ('em_60014_NULL_006') then 'R0000-504-02'
    when em.canvas_step_name IN ('em_60014_NULL_007') then 'R0000-500-01'
    when em.canvas_step_name IN ('em_60014_NULL_008') then 'IND-507-01'
    when em.canvas_step_name IN ('em_60014_NULL_009') then 'IND-180-01'
    when em.canvas_step_name IN ('em_60014_NULL_010') then 'FW2-502'
    when em.canvas_step_name IN ('em_60014_NULL_011') then 'IND-517-02'
    when em.canvas_step_name IN ('em_60014_NULL_012') then 'SEIC-F1040-501-02'
    when em.canvas_step_name IN ('em_60014_NULL_013') then 'R0000-503-02'
    when em.canvas_step_name IN ('em_60014_NULL_014') then 'IND-524'
    when em.canvas_step_name IN ('em_60014_NULL_015') then 'IND-996'
    when em.canvas_step_name IN ('em_60014_NULL_016') then 'IND-452'
    when em.canvas_step_name IN ('em_60014_NULL_017') then 'All Error Codes - Refund'
    when em.canvas_step_name IN ('em_60014_NULL_018') then 'All Error Codes - Bal Due'
    end as error_code
/*    
, case
    when em.canvas_step_name IN () then 'Top 9'
    when em.canvas_step_name IN () then 'Top 10-16'
    end as error_code_rollup
*/    
, case
    when em.canvas_step_name IN ('em_60014_NULL_001','em_60014_NULL_002','em_60014_NULL_003'
                                ,'em_60014_NULL_004','em_60014_NULL_005','em_60014_NULL_006'
                                ,'em_60014_NULL_007','em_60014_NULL_008','em_60014_NULL_009'
                                ,'em_60014_NULL_010','em_60014_NULL_011','em_60014_NULL_012'
                                ,'em_60014_NULL_013','em_60014_NULL_014','em_60014_NULL_015'
                                ,'em_60014_NULL_016','em_60014_NULL_017','em_60014_NULL_018'
                                ) then 'EM Baseline'
    -- when em.canvas_step_name IN ('em_60014_NULL_001a','em_60014_NULL_002a','em_60014_NULL_003a'
    --                             ,'em_60014_NULL_004a','em_60014_NULL_005a','em_60014_NULL_006a'
    --                             ,'em_60014_NULL_007a','em_60014_NULL_008a','em_46961_null_009a'
    --                             ,'em_60014_NULL_010a','em_60014_NULL_011a','em_60014_NULL_012a'
    --                             ,'em_60014_NULL_013a','em_60014_NULL_014a','em_60014_NULL_015a'
    --                             ,'em_60014_NULL_016a'
    --                             ) then 'EM Text-Based'
    end as email_recipe_rollup    
from tax_src.src_braze_turbotax_email_delivery as em
where date(from_utc_timestamp(cast(em.time as timestamp), 'America/Los_Angeles')) >= date('2025-01-29')
    and em.canvas_step_name IN (
    'em_60014_NULL_001'
    ,'em_60014_NULL_002'
    ,'em_60014_NULL_003'
    ,'em_60014_NULL_004'
    ,'em_60014_NULL_005'
    ,'em_60014_NULL_006'
    ,'em_60014_NULL_007'
    ,'em_60014_NULL_008'
    ,'em_60014_NULL_009'
    ,'em_60014_NULL_010'
    ,'em_60014_NULL_011'
    ,'em_60014_NULL_012'
    ,'em_60014_NULL_013'
    ,'em_60014_NULL_014'
    ,'em_60014_NULL_015'
    ,'em_60014_NULL_016'
    ,'em_60014_NULL_017'
    ,'em_60014_NULL_018'
    )
;
