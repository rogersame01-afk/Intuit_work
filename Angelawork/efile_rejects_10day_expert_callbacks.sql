/* forecast for ty21 callbacks 10 days */

/*
"Timing: 10 days after being rejected

Audience
x TY21 Efile Reject (e-file acceptance = Null, print to mail date = Null) 
x All Fed Error Codes 
x Free + Paid
x DIY, excluding CK
Marketing Scrub: No, this is Service Recovery 
DNC: Internal DNC = no; Natl DNC = no
Phone number source = OII "							
*/

with tax_date as (
  select distinct td.tax_date
    , td.filing_year as tax_year
    , td.tax_day
  from dlprd.tax_dm.dim_tax_date td
  where td.filing_year = 2020
)

,

rejects as (
    select pam.auth_id
      ,pam.first_fed_efile_rejected_date
      ,pam.first_fed_efile_accepted_date
      ,pam.first_print_to_mail_date_adj
      ,(coalesce(pam.first_fed_efile_accepted_date,pam.first_print_to_mail_date_adj) - pam.first_fed_efile_rejected_date) as time_between_reject_and_resolution
      ,date_diff('day', pam.first_fed_efile_rejected_date, coalesce(coalesce(pam.first_fed_efile_accepted_date,pam.first_print_to_mail_date_adj),current_date)) days_between_reject_and_resolution
    from dlprd.tax_rpt.product_analytics_master_tax_rpt pam
    where pam.tax_year = 2020
      and pam.nonffa_flag = 1
      and pam.completed_flag = 1
      and completed_sku in(
        '200|Free TTO'
        ,'600|Paid Deluxe'
        ,'800|Paid Premier'
        ,'850|Paid Self Employed'
        ) -- DIY only, not CK;
      and pam.first_fed_efile_rejected_date is not null
      and date_diff('day', pam.first_fed_efile_rejected_date, coalesce(coalesce(pam.first_fed_efile_accepted_date,pam.first_print_to_mail_date_adj),current_date)) >= 10
  )

select tax_date.tax_date
  , count(distinct case when rejects.days_between_reject_and_resolution >= 10 and date(rejects.first_fed_efile_rejected_date) <= tax_date.tax_date then rejects.auth_id end)*.90 as aged_reject_count
from tax_date
left join rejects
  on tax_date.tax_date = date(rejects.first_fed_efile_rejected_date)
group by 1
order by 1
;
