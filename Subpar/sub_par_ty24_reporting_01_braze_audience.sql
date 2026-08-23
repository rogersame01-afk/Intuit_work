DROP TABLE IF EXISTS cgan_ustax_ws.sub_par_ty24_reporting_01_braze_audience;
CREATE TABLE cgan_ustax_ws.sub_par_ty24_reporting_01_braze_audience AS
select * from (
SELECT DISTINCT
  ROW_NUMBER() OVER (PARTITION BY a.pseudonym_id ORDER BY a.date_issue DESC) AS row_num,
  a.pseudonym_id,
  a.auth_id,
  a.issue_type,
  a.cell,
  a.date_issue,
  a.datetime_qualified,
  a.date_qualified,
  a.mpm,
  -- a.copy_type,
  a.dt,
  a.mpm_cell,

  -- email details
  a.flag_test, -- if customer gets email, should be in test group
  a.test_group, -- if customer gets email, should be in test group
  a.test_window,
  a.canvas_name,
  a.canvas_id,
  a.canvas_step_name,

  -- date that email was sent or delivered  
  a.dt_em_sent,
  d.dt_em_delivered,
  d.flag_delivered,
  c.flag_click,  
  c.flag_click_unsubscribe,

  CASE 
    WHEN a.canvas_step_name = 'em_CSO-541_001' THEN 'Late Night Callback No P-Code'
    WHEN a.canvas_step_name = 'em_CSO-541_002' THEN 'Late Night Callback With P-Code'
    WHEN a.canvas_step_name = 'em_CSO-541_003' THEN 'Long Wait Time No P-Code'
    WHEN a.canvas_step_name = 'em_CSO-541_004' THEN 'Long Wait Time With P-Code'
    WHEN a.canvas_step_name = 'em_CSO-541_005' THEN 'Call Transfer No P-Code'
    WHEN a.canvas_step_name = 'em_CSO-541_006' THEN 'Call Transfer With P-Code'
   END AS creative_group

   , case
    when a.canvas_step_name = 'em_CSO-541_001' then 'no discount'
    when a.canvas_step_name = 'em_CSO-541_002' then 'discount'
    when a.canvas_step_name = 'em_CSO-541_003' then 'no discount'
    when a.canvas_step_name = 'em_CSO-541_004' then 'discount'
    when a.canvas_step_name = 'em_CSO-541_005' then 'no discount'
    when a.canvas_step_name = 'em_CSO-541_006' then 'discount'
  end as recipe
, case
    when a.canvas_step_name = 'em_CSO-541_001' then 'late night callback'
    when a.canvas_step_name = 'em_CSO-541_002' then 'late night callback'
    when a.canvas_step_name = 'em_CSO-541_003' then 'long wait'
    when a.canvas_step_name = 'em_CSO-541_004' then 'long wait'
    when a.canvas_step_name = 'em_CSO-541_005' then 'call transfers'
    when a.canvas_step_name = 'em_CSO-541_006' then 'call transfers'
  end as cohort

FROM cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_send AS a 
LEFT JOIN cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_delivered AS d
  ON a.pseudonym_id = d.pseudonym_id
LEFT JOIN cgan_ustax_ws.sub_par_ty24_reporting_00_braze_email_click AS c
  ON a.pseudonym_id = c.pseudonym_id) where row_num=1;
