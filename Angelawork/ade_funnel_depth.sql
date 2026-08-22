drop table if exists cgan_ustax_ws.ty25_1095_ade_test_sw_mw_funnel_depth;
create table cgan_ustax_ws.ty25_1095_ade_test_sw_mw_funnel_depth as
with screen_view_2_0 as
(
    -- 2.0 EIN ENtry screen
   select distinct psd.pseudonym_id, '2.0' as ade_1095_screen_flag                            
    from tax_src.fact_clickstream_psd psd   
      where psd.tax_year = '2025'
        --  and from_utc_timestamp(from_unixtime(event_ts),'America/Los_Angeles') >= cast('2026-03-13 11:30:00' as TIMESTAMP)
        --  and from_utc_timestamp(from_unixtime(event_ts),'America/Los_Angeles') <= cast('2026-05-01 11:30:00' as TIMESTAMP)
        
   and psd.action = 'viewed'
         and scope = 'turbotax'
         and psd.scope_area = 'Federal Taxes|Deductions & Credits'
         and psd.screen = 'form1095a-marketplace-identifier-ownership-views-0'
         and load_date >= '2026031300'   
)

, screen_view_3_0 as
(
     -- 3.0 EinEntry screen below
   select distinct psd.pseudonym_id, '3.0' as ade_1095_screen_flag                                                      
       from tax_src.fact_clickstream_psd psd  
      where psd.tax_year = '2025'
        --  and from_utc_timestamp(from_unixtime(event_ts),'America/Los_Angeles') >= cast('2026-03-13 11:30:00' as TIMESTAMP)
        --  and from_utc_timestamp(from_unixtime(event_ts),'America/Los_Angeles') <= cast('2026-05-01 11:30:00' as TIMESTAMP)

          
   and psd.action = 'viewed'
         and scope = 'turbotax'
           and psd.sub_scope_area = 'intopic_acquiretopic'
         and psd.screen = 'acquiretaxdocuments_landing'
         and load_date >= '2026031300'    
  and screen_object_state LIKE '%1095A%'

)
,pam as
(
    select distinct pseudonym_id, auth_id 
    from tax_rpt.product_analytics_master_ytd pam
    where tax_year = 2025
)

select distinct auth_id, ade_1095_screen_flag  
from screen_view_2_0 s
inner join pam 
on s.pseudonym_id = pam.pseudonym_id

UNION 
select distinct auth_id, ade_1095_screen_flag  
from screen_view_3_0 s
inner join pam 
on s.pseudonym_id = pam.pseudonym_id
;
