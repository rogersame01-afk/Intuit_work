-- success metric reject rate;
-- secondary metric S2C, RPV;

DROP TABLE IF EXISTS cgan_general_published.ty25_5084_users_combined;
CREATE TABLE cgan_general_published.ty25_5084_users_combined as 
with test as (
  SELECT pam.auth_id as auth_id
     , pam.pseudonym_id as pseudonym_id
     , pam.tax_year
     , IXP.experiment_name as test_name
     , case when treatment_name = 'A' then 'Control' else 'Test' end AS recipe_name
     , MIN(date((first_timestamp))) as first_assignment_date
     , MIN((first_timestamp)) as first_assignment_timestamp
  FROM ixp_dwh.ixp_first_assignment ixp 
  JOIN tax_rpt.product_analytics_master pam 
    ON ixp.id = pam.auth_id
      AND pam.tax_year = 2025
 WHERE 1=1
   AND ixp.experiment_id = 321815
   AND ixp.treatment_name IS NOT NULL
   AND ixp.version >= 4
   AND ixp.partitiondate >= DATE('2026-03-31')
 GROUP BY 1,2,3,4,5
),

aca_errors as (
    select re.auth_id
        , min(re.efile_status_timestamp) as first_efile_reject_timestamp
    from tax_dm.fact_efile_reject_error re
    left join tax_dm.dim_efile_reject_code rc
        on re.efile_reject_code_id = rc.efile_reject_code_id
    where re.filing_type_id = '244' 
        and rc.error_code = 'F8962-070'
        and re.tax_year = 2025
        and re.auth_id <> -1
    group by 1
),

units as (
    select pam.auth_id
        , pam.first_completed_date
    from tax_rpt.product_analytics_master pam
    where pam.tax_year = 2025
),

mam_payment as (
    select auth_id
        , tax_year
        , TOTAL_REVENUE
        , rt_attach_flag
        , fde_attach_flag
        , min_fde_attach_timestamp
     from tax_rpt.monetization_analytics_master
     where tax_year = 2025
)

select t.recipe_name as recipe
    , t.test_name
    , t.auth_id
    , t.first_assignment_timestamp
    , case when a.first_efile_reject_timestamp is not null then 1 else 0 end as reject_1095_flag
    , case when u.first_completed_date is not null then 1 else 0 end as completed_flag
    , mp.total_revenue
    , mp.rt_attach_flag
    , mp.fde_attach_flag
from test t
left join aca_errors a
    on t.auth_id = a.auth_id
        and a.first_efile_reject_timestamp >= t.first_assignment_timestamp
left join units u
    on t.auth_id = u.auth_id
        and u.first_completed_date >= t.first_assignment_timestamp
left join mam_payment mp
    on u.auth_id = mp.auth_id
;


DROP TABLE IF EXISTS cgan_general_published.ty25_5084_users_auth_level_combined;
CREATE TABLE cgan_general_published.ty25_5084_users_auth_level_combined as 
    select
          auth_id                                        
        , test_name                                                                     as experiment_id
        , date(first_assignment_timestamp)                                              as cohort_date
        , recipe                                                                        as condition 
        , '1095-A Reject Rate'                                                          as metric
        , 1.0 * ((count(distinct case when reject_1095_flag = 1 then auth_id end)) 
            / count(distinct auth_id))                                                  as outcome
    from cgan_general_published.ty25_5084_users_combined
    group by 1,2,3,4,5
    
    union

    select
          auth_id                                        
        , test_name                                                                     as experiment_id
        , date(first_assignment_timestamp)                                              as cohort_date
        , recipe                                                                        as condition 
        , 'S2C'                                                                         as metric
        , 1.0 * ((count(distinct case when completed_flag = 1 then auth_id end)) 
            / count(distinct auth_id))                                                  as outcome
    from cgan_general_published.ty25_5084_users_combined
    group by 1,2,3,4,5
    
    union
    
    select
          auth_id                                        
        , test_name                                                                     as experiment_id
        , date(first_assignment_timestamp)                                              as cohort_date
        , recipe                                                                        as condition 
        , 'RPV'                                                                         as metric
        , 1.0 * (sum(case when total_revenue is not null then total_revenue else 0 end) 
                 / count(distinct auth_id))                              
                                                                                        as outcome
    from cgan_general_published.ty25_5084_users_combined
    group by 1,2,3,4,5
;


DROP TABLE IF EXISTS cgan_general_published.ty25_5084_combined;
CREATE TABLE cgan_general_published.ty25_5084_combined as 
SELECT
  experiment_id,
  condition,
  metric,
  cohort_date,
  AVG(outcome) AS mean_outcome,
  STDDEV(outcome) AS std_outcome,
  COUNT(*) AS trials
FROM cgan_general_published.ty25_5084_users_auth_level_combined
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4
;
