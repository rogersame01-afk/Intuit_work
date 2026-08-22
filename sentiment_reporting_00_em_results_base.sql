--retrieve all sentiment email results 
--NEED THE UPDATED CANVAS ID FOR TY24 CAMPAIGN
DROP TABLE IF EXISTS cgan_ustax_ws.sentiment_ty25_braze_em;
CREATE TABLE cgan_ustax_ws.sentiment_ty25_braze_em as 
select distinct
  a.external_user_id as pseudonym_id
, date(from_utc_timestamp(cast(a.time as timestamp), 'America/Los_Angeles')) as date_em_sent
, coalesce(a.canvas_name, c.campaign_name) as canvas_name
, coalesce(a.canvas_id, c.campaign_id) as canvas_id
, a.canvas_step_name
, max(case when c.external_user_id is not null then 1 else 0 end) over (partition by a.external_user_id) as em_clicked_flag

from tax_src.src_braze_turbotax_email_delivery as a
left join tax_src.src_braze_turbotax_email_click as c
        on a.external_user_id = c.external_user_id
        and a.canvas_name = c.canvas_name
        and a.canvas_id = c.canvas_id
        and c.url not like '%account-manager%'
where date(from_utc_timestamp(cast(a.time as timestamp), 'America/Los_Angeles')) >= date('2025-12-01') -- asked alexis about the date if it is necessary
and a.canvas_name like '%798_CSO_TY25_-Mid-Product-Sentiment-Outreach﻿-3k_k_medium_EM%' 
  and a.canvas_id='5de45202-b169-4165-9d27-4d25009da96f'
   
;
