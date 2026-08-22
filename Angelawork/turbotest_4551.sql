-- replace the table name with your experiment_id
DROP TABLE IF EXISTS cgan_ustax_ws.ty25_cg_experimentation_data_224297;
CREATE TABLE cgan_ustax_ws.ty25_cg_experimentation_data_224297 AS
    (
        WITH input_data AS
        (
            -- Your input required here
            SELECT
                224297              AS recipe_id,
                2                   AS version,
                'Angela'          AS analyst_name,
                'Watson'            AS product_manager_name,
                DATE('2025-06-03')  AS test_start_date, 
                DATE('2025-10-31')  AS test_end_date,
                2024                AS tax_year,
                'A'           AS Control, -- replace the value with the exact name of your control recipe
                'B'                 AS Treatment_1, -- replace the value with the exact name of the you treatment recipe
                null                As Treatment_2, -- leave it as null if you dont have third recipe
                null                As Treatment_3, -- leave it as null if you dont have fourth recipe
                'ty24_4551' AS bayesian_table_name -- update this field with the name of your bayesian table used at the end of this sheet
      
     ),

    -- no inputs required after this -- please update the bayesian table name at the end of the sheet
    test as (
            SELECT DISTINCT
                (select tax_year from input_data) as tax_year,
                ixp.id as auth_id,
                pam.pseudonym_id,
                to_date(from_utc_timestamp(first_timestamp, 'America/Los_Angeles')) as first_assignment_timestamp,
                from_utc_timestamp(first_timestamp, 'America/Los_Angeles') as first_assignment_timestamp_utc,
                treatment_id as recipe,
                treatment_name as recipe_name,
                experiment_id as recipe_id,
                case when lower(treatment_name) = (select lower(control) from input_data) then 'Control' 
                when lower(treatment_name) = (select lower(Treatment_1) from input_data) then 'Treatment 1'
                when lower(treatment_name) = (select lower(Treatment_2) from input_data) then 'Treatment 2' 
                when lower(treatment_name) = (select lower(Treatment_3) from input_data) then 'Treatment 3' 
                else null end as recipe_name_1,
                experiment_name as test_name,
                (select product_manager_name from input_data) as product_manager_name,
                (select analyst_name from input_data) as analyst_name,
                version,
                (select bayesian_table_name from input_data) as bayesian_table_name,
                (select test_start_date from input_data) as test_start_timestamp,
                (select test_end_date from input_data) as test_end_timestamp

            FROM
                ixp_dwh.ixp_first_assignment ixp 
                inner join tax_rpt.product_analytics_master pam 
                on ixp.id = pam.auth_id
                and pam.tax_year = (select tax_year from input_data)
            WHERE
                (experiment_id = (SELECT recipe_id FROM input_data))
                and treatment_name is not null
                and version = (select version from input_data)
                and partitiondate >= (select test_start_date from input_data)
            ),

        hypothesis AS
        (
            SELECT 
                experiment_id,
                max(hypothesis) as hypothesis
            FROM ixp_dwh.experiment_proposals
            WHERE experiment_id = (SELECT recipe_id FROM input_data)
            GROUP BY 1

        ),

        diwm_entitlements AS
        (
            SELECT DISTINCT
                tax_year,
                auth_id
            FROM tax_rpt.tto_service_level_entitlement_analytics_master
            WHERE entitlement_sku_group_code LIKE '%DIWM%'
            AND tax_year = ( SELECT tax_year FROM input_data)
            group by 1,2
        ),

        offer_location_analytics_master AS
        (
            SELECT
                auth_id,
                tax_year,
                max_see_flag,
                max_take_flag,
                max_detach_flag,
                max_attach_flag,
                plus_see_flag,
                plus_take_flag,
                plus_detach_flag,
                plus_attach_flag,
                diwm_see_flag,
                diwm_take_flag,
                diwm_attach_flag,
                fs_see_flag,
                fs_take_flag,
                fs_attach_flag,
                wb_see_flag,
                wb_take_flag,
                wb_detach_flag,
                wb_attach_flag,
                required_upgrade_see_flag,
                required_upgrade_take_flag
            FROM
                cgan_ustax_published.offer_location_analytics_master_ytd
            WHERE
                tax_year = (SELECT tax_year FROM input_data)
        ),

        rt_attach AS (
            SELECT  auth_id,
                    tax_year,
                    max(CASE WHEN mam.num_refund_transfer_attach > 0 THEN 1 ELSE 0 END) AS rt_attach_flag,
                    max(CASE WHEN mam.fde_attach_flag > 0 THEN 1 ELSE 0 END) AS fde_attach_flag
            FROM tax_rpt.monetization_analytics_master_ytd mam
            WHERE 
            tax_year = (SELECT tax_year FROM input_data)
            AND num_refund_transfer_attach > 0  
            group by 1,2
        ),

        product_analytics_master as 
        (
           SELECT
                auth_id ,
                tax_year,
                vauth_flag,
                prs_score AS PAM_prs,
                first_vauth_date,
                vauth_platform_type,
                first_start_date,
                first_start_date_adj,
                first_completed_date,
                first_completed_date_adj,
                start_sku,
                start_sku_rollup,
                completed_sku,
                completed_sku_rollup,
                tto_start_flag AS start_flag,
                neauth_app_type,
                start_app_type,
                vauth_app_type,
                completed_flag,
                tto_segment,
                tto_segment_rollup,
                pseudonym_id,
                total_revenue,
                first_fed_efile_accepted_date_adj,
                first_fed_efile_attempted_date_adj,
                case when num_schd>0 then 'Investor' else 'Not an Investor' end as Investor,
                case when num_schc>0 then 'Self Employed' else 'Not Self Employed' end as Self_Employed,
                case when (num_schc>0 or num_schd>0) then 'Complex' else 'Simple' end as Complex,
                case when num_scha = 0 then 'Standardized Deductions' 
                        when num_scha > 0 then 'Itemized Deductions' 
                        else 'Other' end as itemized_flag,
                case when pam.first_fed_efile_rejected_date is not null then 1 else 0 end as efile_reject_flag,
                case when pam.first_fed_efile_attempted_date is not null then 1 else 0 end as efile_attempt_flag,
                case when pam.first_fed_efile_accepted_date is not null then 1 else 0 end as efile_accept_flag,
                case when pam.first_fed_efile_rejected_date is not null and pam.first_fed_efile_accepted_date is not null then 1 else 0 end as efile_refile_success_flag
                FROM 
                    tax_rpt.product_analytics_master pam
                WHERE
                tax_year = (SELECT tax_year FROM input_data)

        ),

        mps as
        (
        select mps.tax_year,
                mps.auth_id,
                max(case when responseid is not null then 1 else 0 end) as mps_response_flag,
                count(distinct case when promoter=1 then responseid end) as mps_promoter,
                count(distinct case when negative=1 then responseid end) as mps_detractor,
                count(distinct case when neutral=1 then responseid end) as mps_neutral,
                count(distinct case when neutral=1 or promoter=1 or negative=1 then responseid end) as mps_overall  
                FROM
                cgan_ustax_published.cg_us_tto_mps_7216 mps
                WHERE
                tax_year = (SELECT tax_year FROM input_data)
                group by 1,2
        ),

        contact AS 
        (
        SELECT  cct.tax_year,
                cct.auth_id,
       -- High Level
                MAX(CASE WHEN cct.offered_flg = 1 THEN 1 ELSE 0 END) AS offered_flag,
                MAX(CASE WHEN cct.customer_handle_flg = 1 THEN 1 ELSE 0 END) AS handled_flag,
                SUM(CASE WHEN cct.offered_flg = 1 THEN 1 ELSE 0 END) AS offered_cnt,
                SUM(CASE WHEN cct.customer_handle_flg = 1 THEN 1 ELSE 0 END) AS handled_cnt,
       -- TA(DE) vs PE
                MAX(CASE WHEN cct.offered_flg = 1 AND cct.interaction_skill_seg = 'TA' THEN 1 ELSE 0 END) AS TA_offered_flag,
                MAX(CASE WHEN cct.offered_flg = 1 AND cct.interaction_skill_seg IN ('TS','PS') THEN 1 ELSE 0 END) AS PE_offered_flag,       
       -- Location 
                MAX(CASE WHEN (cct.leg_queue LIKE '%cg-us_ta_initialconsult%'OR cct.leg_queue LIKE '%_fue%') THEN 1 ELSE 0 END) AS FUE_offered_flag,
                MAX(CASE WHEN cct.customer_handle_flg = 1 AND (cct.leg_queue LIKE '%cg-us_ta_initialconsult%'OR leg_queue LIKE '%_fue%') THEN 1 ELSE 0 END) AS FUE_handled_flag,
                MAX(CASE WHEN cct.leg_queue like 'cg-us_er_%'  THEN 1 ELSE 0 END) AS ER_offered_flag,
                MAX(CASE WHEN cct.customer_handle_flg = 1 AND cct.leg_queue like 'cg-us_er_%' THEN 1 ELSE 0 END) AS ER_handled_flag,
                MAX(CASE WHEN cct.interaction_skill_function = 'TTL' 
                     AND cct.leg_queue NOT LIKE '%cg-us%fs%'
                     AND leg_queue NOT LIKE '%cg-us%fullservice%'
                     AND leg_queue NOT LIKE '%cg-us_ta_qrt%'
                     AND leg_queue NOT LIKE '%cg-us_ta_triage%'
                     AND leg_queue NOT LIKE '%initialconsult%'
                     AND leg_queue NOT LIKE '%_fue%'
                     AND leg_queue NOT LIKE 'cg-us_er_%'
                     AND leg_queue NOT LIKE '%cg-us%selfemployed%'
                     AND leg_queue NOT LIKE '%cg-us%investor%'
                     AND leg_queue NOT LIKE '%cg-us%ups%'  THEN 1 ELSE 0 END) AS AYG_offered_flag,
                   MAX(CASE WHEN cct.customer_handle_flg = 1 --AND cct.interaction_skill_seg = 'TA'
                        AND leg_queue NOT LIKE '%cg-us%fs%'
                        AND leg_queue NOT LIKE '%cg-us%fullservice%'
                        AND leg_queue NOT LIKE '%cg-us_ta_qrt%'
                        AND leg_queue NOT LIKE '%cg-us_ta_triage%'
                        AND leg_queue NOT LIKE '%initialconsult%'
                        AND leg_queue NOT LIKE '%_fue%'
                        AND leg_queue NOT LIKE 'cg-us_er_%'
                        AND leg_queue NOT LIKE '%cg-us%selfemployed%'
                        AND leg_queue NOT LIKE '%cg-us%investor%'
                        AND leg_queue NOT LIKE '%cg-us%ups%'  THEN 1 ELSE 0 END) AS AYG_handled_flag,
                   AVG(cct.talk_seconds_dur + cct.hold_seconds_dur + cct.acw_seconds_dur)/60 AS AHT,
                   AVG(cct.queue_seconds_dur)/60 AS wait_time,
                   COUNT(DISTINCT CASE WHEN np_num_promoter_flg = 1 AND (cgt.dropped_case_ind = 0 OR cgt.dropped_case_ind IS NULL) AND cgt.sur_duration_in_seconds != 0 THEN response_id END) AS np_num_promoter,
                   COUNT(DISTINCT CASE WHEN np_num_detractor_flg = 1 AND (cgt.dropped_case_ind = 0 OR cgt.dropped_case_ind IS NULL) AND cgt.sur_duration_in_seconds != 0 THEN response_id END) AS np_num_detractor,
                   COUNT(DISTINCT CASE WHEN np_response_flg = 1 AND (cgt.dropped_case_ind = 0 OR cgt.dropped_case_ind IS NULL) AND cgt.sur_duration_in_seconds != 0 THEN response_id END) AS np_denom

            FROM ent_care_7216_dwh.rpt_cct_interactions cct
            -- join PAM
            JOIN tax_rpt.product_analytics_master pam
                 ON pam.auth_id  = cct.auth_id 
                 AND pam.tax_year = cct.tax_year
                 AND (DATE(from_utc_timestamp(cct.contact_start_ts, 'America/Los_Angeles')) <= DATE(from_utc_timestamp(pam.first_completed_date, 'America/Los_Angeles')) OR pam.first_completed_date is null) -- pre-complete contact

            -- join test
             JOIN test
                 ON test.auth_id = cct.auth_id 
                 AND test.tax_year = cct.tax_year
                 AND ((from_utc_timestamp(cct.contact_start_ts, 'America/Los_Angeles')))>= first_assignment_timestamp_utc -- post_assignment_contact

           -- join EAM 
            JOIN tax_rpt.tto_service_level_entitlement_analytics_master eam
               ON eam.auth_id = cct.auth_id 
               AND eam.tax_year = cct.tax_year
               AND cct.contact_start_ts >= eam.first_entitlement_sku_group_datetime  -- contact in DIWM
               AND entitlement_sku_group_code LIKE '%DIWM%' 

           -- join with tnps table 
            LEFT JOIN cgan_ustax_published.cg_us_tto_tnps_dash_slk cgt
            ON eam.auth_id  = cgt.cy_contact_auth
               AND eam.tax_year = cgt.tax_year
               AND cgt.response_created_datetime >= eam.first_entitlement_sku_group_datetime  -- response in DIWM
            WHERE cct.tax_year = (SELECT tax_year FROM input_data)
                  AND cct.bu = 'cg'
                  AND cct.offered_flg = 1
                  AND (cct.interaction_skill_function IN ('TTL') OR (cct.interaction_skill_function = 'Care' AND cct.leg_queue LIKE '%diwm%'))
                  AND cct.forecast_group_name NOT IN ('NON-FCST FS OUTBOUND', 'NON-FCST TTL OUTBOUND', 'TTL TIP', 'Test Queue')
            GROUP BY 1,2    

        ),


 ps_contacts as 
    (
SELECT 
      cct.tax_year, 
      cct.auth_id, 
      SUM(CASE WHEN cct.offered_flg = 1 THEN 1 ELSE 0 END) AS ps_offered_cnt,
      MAX(CASE WHEN cct.offered_flg = 1 THEN 1 ELSE 0 END) as ps_offered_flag,
      AVG(cct.talk_seconds_dur + cct.hold_seconds_dur + cct.acw_seconds_dur)/60 AS ps_AHT,
      SUM(CASE
         WHEN (cct.dropped_case_ind = 0 OR cct.dropped_case_ind IS NULL)
         AND voc.sur_duration_in_seconds <> 0
         AND voc.ans_cr_val IS NOT NULL
         THEN voc.ans_cr_val ELSE 0 END) AS ps_ir_numer,
      COUNT(CASE
         WHEN (cct.dropped_case_ind = 0 OR cct.dropped_case_ind IS NULL)
         AND voc.sur_duration_in_seconds <> 0
         AND voc.ans_cr_val IS NOT NULL
         THEN 1 END) AS ps_ir_denom

      FROM ent_care_7216_dwh.rpt_cct_interactions cct  
  
      JOIN tax_rpt.product_analytics_master pam
            ON pam.auth_id  = cct.auth_id
            AND pam.tax_year = cct.tax_year
            AND (to_date(from_utc_timestamp(cct.contact_start_ts, 'America/Los_Angeles')) <= to_date(from_utc_timestamp(pam.first_completed_date, 'America/Los_Angeles')) OR pam.first_completed_date IS NULL)
      JOIN test
           ON test.auth_id = cct.auth_id
           AND test.tax_year = cct.tax_year
           AND to_date(from_utc_timestamp(cct.contact_start_ts, 'America/Los_Angeles')) >= test.first_assignment_timestamp
           
      JOIN (select distinct queue_name, customer_ecosystem_desc, business_unit_code,forecast_group_name
            from ent_dim_dwh.dim_queue_forecast_group_scd d 
            WHERE d.business_unit_code = 'CG'
            AND region_code = 'US'
            AND d.forecast_group_name IN (
          'PE DIY DESKTOP','PE DIY ESCALATION','PE DIY FREE','PE DIY IDFRAUD','PE DIY LOGIN','PE DIY PAID','PE DIY PAID WIP','PE DIY POST''PE DIY POST WIP',
          'PE DIY SPANISH','PE DIY SPANISH WIP','PE LOYALTY CHAT','PE PROACTIVE PHONE SPEC','PE RETENTION',
          'PE TTL AYG','PE TTL AYG WIP','PE TTL CHAT','PE TTL CHAT WIP'
           )
          AND d.customer_ecosystem_desc in ('PS','TS')

          ) d
         ON TRIM(UPPER(cct.leg_queue)) = TRIM(UPPER(d.queue_name))


      LEFT JOIN
        (SELECT
            (unix_timestamp(response_submitted_datetime)
               - unix_timestamp(response_created_datetime)) AS sur_duration_in_seconds,
             converted_issue_resolution_score_nbr  AS ans_cr_val,
             contact_id,
             tax_year
             FROM
                 care_rpt.rpt_survey_submission_tnps
             WHERE src_survey_id IN ('SV_5cAo5o3WPC85KMB','SV_e9bmOw0gtW1hyNE','SV_1R1AS4hvHt3YctL')
             AND tax_year = (SELECT tax_year FROM input_data)
             ) voc
        ON cct.agent_source_key = voc.contact_id
        AND cct.tax_year = voc.tax_year
    
          WHERE d.business_unit_code = 'CG'
          AND cct.tax_year = (SELECT tax_year FROM input_data)
          AND cct.bu = 'cg'
          GROUP BY 1,2
),

        taxml
        as 
        (select  auth_id
                ,tax_year
                , case
                   when amount_refund > 0 then 'Refund'
                   when amount_refund = 0 then 'Zero balance'
                   when amount_refund < 0 then 'Bal Due'
            end as balance_refund_flag,
            case when  age_taxpayer < 18 then 'Minors or Birth Year Not Set'
            when tax_year - age_taxpayer < 1928 then 'Greatest Generation'
            when tax_year - age_taxpayer between 1928 and 1945 then 'Silent Generation'
            when tax_year - age_taxpayer between 1946 and 1964 then 'Baby Boomer Generation'
            when tax_year - age_taxpayer between 1965 and 1980 then 'Generation X'
            when tax_year - age_taxpayer between 1981 and 1996 then 'Millennial Generation'
            when tax_year - age_taxpayer between 1997 and 2012 then 'Generation Z'
            else 'Unknown' 
            end as customer_generation_bucket,
            AGI_GRP,
            filing_status
        from tax_src.agg_taxml_ytd
        where tax_year = (SELECT tax_year FROM input_data)
        ),

        marketing_channel as 
         (
        select 
            auth_id, 
            tax_year,
            max(CHANNEL_GROUP) as channel_group
            from tax_rpt.marketing_analytics_master
            where tax_year = (SELECT tax_year FROM input_data)
            group by 1,2
        ),

        SHAM as 
        (
            select 
            tax_year,
            auth_id,
            max(last_shopping_experience_before_start) as last_shopping_experience_before_start,
            max(last_sku_recommended) as last_sku_recommended
            FROM cgan_ustax_published.shopping_analytics_master
            where tax_year = (SELECT tax_year FROM input_data)
            group by 1,2
        ),

        workle_ytd as
        (   
            select 
            tax_year,
            pseudonym_id,
            gtkm_interaction_count,
            pi_interaction_count,
            fedtax_wages_interaction_count,
            fedtax_dnc_interaction_count,
            fedtax_other_interaction_count,
            fedtax_review_interaction_count,
            statetax_interaction_count,
            final_review_interaction_count,
            fnf_interaction_count,
            null_tab_interaction_count,
            total_start_to_complete_interaction_count
             from cgan_ustax_published.agg_auth_tab_interactions a
                        where tax_year = (SELECT tax_year FROM input_data)
                        and reporting_date =
            (SELECT CASE
                WHEN MAX(reporting_date) >= (SELECT test_end_date FROM input_data)
                THEN (SELECT test_end_date FROM input_data)
                ELSE MAX(reporting_date)
              END
            FROM cgan_ustax_published.agg_auth_tab_interactions b
            WHERE b.pseudonym_id = a.pseudonym_id
            and tax_year = (SELECT tax_year FROM input_data))
          ),

        current_sku as 
        (
            select 
            sku.tax_year,
            sku.auth_id,
            max(sku.current_sku) as current_sku,
            max(case when lower(sku.current_sku) like '%free%' then 'DIY FREE'
                    when lower(sku.current_sku) like 'qb_%' OR lower(sku.current_sku) like '%solopreneur%' then 'BIZTAX'
                    when lower(sku.current_sku) like 'fs_%' then 'FS'
                    when lower(sku.current_sku) like '%ttl_basic%' then 'DIWM BASIC'
                    when lower(sku.current_sku) like 'ttl%' then 'DIWM NON-BASIC'
                    when lower(sku.current_sku) IN ('deluxe','deluxe_lite','premium') then 'DIY PAID'
                    when sku.current_sku = 'NO_PRODUCT_FAMILY' then 'NO_PRODUCT_FAMILY'
                    else null end) current_sku_rollup
            from cgan_ustax_published.sku_transition_entitlements_master sku
            where tax_year = (SELECT tax_year FROM input_data)
            group by 1,2
        ),

        abandonment as 
        (
            select 
            ma.auth_id,
            ma.tax_year,
            max(last_app_type) as last_app_type,
            max(case when pam.first_fed_efile_accepted_date_adj is not null OR pam.first_fed_efile_attempted_date_adj is not null then '10-Efiled'
            when pam.first_completed_date_adj is not null and pam.completed_sku is not null then '9-Completed'
            when ma.last_tab_name IN ('Review', 'Finish and File') then '8-FnF'
            when ma.last_tab_name = 'State Taxes' then '7-State Taxes'
            when ma.last_tab_name = 'Federal Taxes - Federal Review' then '6-Federal Review'
            when ma.last_tab_name = 'Federal Taxes - Other Tax Situations' then '5-Other Situations'
            when ma.last_tab_name = 'Federal Taxes - Deductions & Credits' then '4-Deductions & Credits'
            when ma.last_tab_name = 'Federal Taxes - Wages & Income' then '3-Wages & Income'
            when ma.last_tab_name = 'Personal Info - You & Your Family' then '2-Personal Info'
            when ma.last_tab_name = 'GTKM' OR pam.first_start_date_adj < current_date() then '1-Started & GTKM'
            else  '0-Authed' end) as latest_milestone
            from tax_rpt.tto_abandonment_master_ytd ma
            join product_analytics_master pam 
            on ma.auth_id = pam.auth_id 
            and ma.tax_year = pam.tax_year 
            where ma.tax_year = (SELECT tax_year FROM input_data)
            group by 1,2

        ),

        screen_views as 
       (
          select 
            s.tax_year,
            s.auth_id,
            max(case when tab_name = 'GTKM' then 1 else 0 end) as gtkm_flag,
            max(case when tab_name = 'Personal Info - You & Your Family' then 1 else 0 end) as pi_flag,
            max(case when tab_name = 'Federal Taxes - Wages & Income' then 1 else 0 end) as income_flag,
            max(case when tab_name = 'Federal Taxes - Deductions & Credits' then 1 else 0 end) as dnc_flag,
            max(case when tab_name = 'Federal Taxes - Other Tax Situations' then 1 else 0 end) as ots_flag,
            max(case when tab_name = 'Federal Taxes - Federal Review' then 1 else 0 end) as fed_review_flag,
            max(case when tab_name = 'State Taxes' then 1 else 0 end) as state_tax_flag,
            max(case when tab_name = 'Finish and File' then 1 else 0 end) as fnf_flag
            from tax_src.tto_abandonment_src s
            where s.tax_year = (SELECT tax_year FROM input_data)
            group by 1,2
      ),
    
-- logic for segments need to be updated
        Segments as 
        (
          select 
            seg.tax_year,
            seg.auth_id,
            -- max(seg.strategic_segment_hierarchy) as complete_segment,
            max(seg.strategic_segment_hierarchy) as customer_segment
          from cgan_ustax_ws.start_strategic_segments_rs seg
          where tax_year = (SELECT tax_year FROM input_data)
          group by 1,2
        ),

       digital_help as 
        (select 
            ss.entity_id,
            count(distinct case when interaction_ind = 1 and contact_ind = 0 then ss.group_record_key end) as total_resolved_sessions,
            count(distinct case when contact_ind = 0 then ss.group_record_key end) as total_help_sessions_no_contact,
            count(distinct case when contact_ind = 1 then ss.group_record_key end) as total_live_help_sessions,
            count(distinct ss.group_record_key) as total_help_sessions, -- SHR denominator ,
            count(distinct case when mp.milestone_progression_flag = 1 then ss.group_record_key end) as mpr_numerator,
            count(distinct mp.group_record_key) as mpr_denominator
        from care_7216_rpt.agg_sh_session_summary ss 
        inner join test t 
        on t.auth_id = ss.entity_id
            left join cg_cx_analytics.sh_summary_milestone_progression mp
            on mp.group_record_key = ss.group_record_key
            and mp.pt_event_date >= date(t.first_assignment_timestamp)
        where date(session_start_datetime) >= date(first_assignment_timestamp) -- post assignment help
        group by 1
        ),

        daily_unique_logins as 
        (select 
            m.auth_id, 
            m.tax_year,
            count(distinct to_date(from_utc_timestamp(session_auth_timestamp, 'America/Los_Angeles'))) as unique_logins
            from tax_rpt.marketing_session_analytics_master m
            inner join test t 
            on t.auth_id = m.auth_id
            and m.tax_year = (SELECT tax_year FROM input_data)
            and m.auth_type != 'No Auth'
            and (from_utc_timestamp(m.session_auth_timestamp, 'America/Los_Angeles')) >= first_assignment_timestamp_utc
            group by 1,2
         ),

        platform_switch as 
        (select 
            auth_id,
            max(platform_switch_flag) as platform_switch_flag,
            max(mobile_web_flag) as mobile_web_flag, 
            max(stationary_web_flag) as stationay_web_flag, 
            max(mobile_app_flag) as mobile_app_flag
        from cgan_ustax_ws.ty24_platform_switching_master_data
        group by 1),

        predicted_s2c as 
        (select tax_year,
                auth_id, 
                max_by(defector_probability, partition_date) as predicted_probability
              from cgan_ustax_ws.science_analytics_master_history
              where tax_year = (SELECT tax_year FROM input_data)
              group by 1,2 ),

        ade as 
        (
        select 
            auth_id, 
            tax_year,
            max(case when successful_ade = 1 then 1 else 0 end) as successful_ade_flag
            from cgan_ustax_published.datax_form_level_dm b 
            where b.tax_year = (SELECT tax_year FROM input_data)
            group by 1,2),

        LTV as 
        (select 
            auth_id, 
            tax_year,
            max(next_year_value) as predicted_next_year_revenue
            from cgan_ustax_ws.nyv_daily_predictions
            where tax_year = (SELECT tax_year FROM input_data)
            group by 1,2),

        errors as 
        (select 
            pseudonym_id,
            tax_year,
            max(case when elements is not null and error_location = 'FedReview' then 1 else 0 end) as fed_review_error_flag,
            max(case when elements is not null and error_location = 'FinalReview' then 1 else 0 end) as final_review_error_flag,
            max(case when elements is not null then 1 else 0 end) as error_flag
            from cgan_ustax_ws.errors_fed_final_unique_topics_ty24 
            where tax_year = (SELECT tax_year FROM input_data)
            group by 1,2
        )

        

        SELECT      

        -- Test metrics           
                t.tax_year,
                t.auth_id,
                t.pseudonym_id,
                t.first_assignment_timestamp,
                t.recipe,
                t.recipe_name,
                t.recipe_id,
                t.recipe_name_1,
                t.test_name,
                t.product_manager_name,
                t.analyst_name,
                t.test_start_timestamp,
                t.test_end_timestamp,
                t.bayesian_table_name,
                t.version as version_id,

        
        -- Hypothesis

                hyp.hypothesis,

        -- diwm_entitlements

                case when diwm.auth_id is not null then diwm.auth_id else null end as diwm_entitlement,
        
        -- OLAM
                olam.max_see_flag,
                olam.max_take_flag,
                olam.max_detach_flag,
                olam.plus_see_flag,
                olam.plus_take_flag,
                olam.plus_detach_flag,
                olam.plus_attach_flag,
                olam.max_attach_flag,
                olam.diwm_see_flag,
                olam.diwm_take_flag,
                olam.diwm_attach_flag,
                olam.fs_see_flag,
                olam.fs_take_flag,
                olam.fs_attach_flag,
                olam.wb_see_flag,
                olam.wb_take_flag,
                olam.wb_detach_flag,
                olam.wb_attach_flag,
                olam.required_upgrade_see_flag,
                olam.required_upgrade_take_flag,

        -- MAM 
                rt.rt_attach_flag,
                rt.fde_attach_flag,

        -- PAM

                pam.vauth_flag,
                pam.PAM_prs,
                pam.first_vauth_date,
                pam.vauth_platform_type,
                pam.first_start_date,
                pam.first_completed_date,
                pam.first_completed_date_adj,
                pam.start_sku,
                pam.start_sku_rollup,
                pam.completed_sku,
                pam.completed_sku_rollup,
                pam.start_flag,
                pam.neauth_app_type,
                pam.start_app_type,
                pam.vauth_app_type,
                pam.completed_flag,
                pam.tto_segment_rollup,
                pam.tto_segment,
                pam.total_revenue,
                pam.Investor,
                pam.Self_Employed,
                pam.Complex,
                pam.itemized_flag,
                pam.efile_reject_flag,
                pam.efile_attempt_flag,
                pam.efile_accept_flag,
                pam.efile_refile_success_flag,
          

        -- MPS 
                mps_promoter,
                mps_detractor,
                mps_neutral,
                mps_overall,
                mps_response_flag,

        -- Contact 
                -- High Level
                con.offered_flag,
                con.handled_flag,
                con.offered_cnt,
                con.handled_cnt,
                -- TA(DE) vs PE
                con.TA_offered_flag,
                con.PE_offered_flag,       
                -- Location
                con.FUE_offered_flag,
                con.FUE_handled_flag,
                con.ER_offered_flag,
                con.ER_handled_flag,
                con.AYG_offered_flag,
                con.AYG_handled_flag,
                con.AHT,
                con.wait_time,
                con.np_num_promoter,
                con.np_num_detractor,
                con.np_denom,

        -- ps_contacts 
                ps.ps_offered_cnt,
                ps.ps_offered_flag,
                ps_AHT,
                ps_ir_numer,
                ps_ir_denom,
    
        
        -- TaxML
                ml.balance_refund_flag,
                ml.customer_generation_bucket,
                ml.AGI_GRP,
                ml.filing_status,

        -- Marketing

                mak.channel_group,

        -- SHAM 

                sham.last_shopping_experience_before_start,
                sham.last_sku_recommended,
        
        -- Workle           
          
            workle.gtkm_interaction_count,
            workle.pi_interaction_count,
            workle.fedtax_wages_interaction_count,
            workle.fedtax_dnc_interaction_count,
            workle.fedtax_other_interaction_count,
            workle.fedtax_review_interaction_count,
            workle.statetax_interaction_count,
            workle.final_review_interaction_count,
            workle.fnf_interaction_count,
            workle.null_tab_interaction_count,
            workle.total_start_to_complete_interaction_count,

        -- Abandonment

           ma.latest_milestone,
           ma.last_app_type,

        -- current sku 

            sku.current_sku,
            case when sku.current_sku_rollup = 'NO_PRODUCT_FAMILY' then pam.start_sku_rollup else sku.current_sku_rollup end as current_sku_rollup,

        -- Segments 

           -- seg.complete_segment,
            seg.customer_segment,

        -- Digital Help
             
            dh.total_resolved_sessions,
            dh.total_help_sessions_no_contact,
            dh.total_live_help_sessions,
            dh.total_help_sessions,
            dh.mpr_numerator,
            dh.mpr_denominator,

       -- Platform Switch

             pl.platform_switch_flag,
             pl.mobile_web_flag, 
             pl.stationay_web_flag, 
             pl.mobile_app_flag,

      -- predicted s2c 
             
             def.predicted_probability,

      -- ade
            ade.successful_ade_flag,
      --ltv
           ltv.predicted_next_year_revenue,
    
      -- screen_views
            sv.gtkm_flag,
            sv.pi_flag,
            sv.income_flag,
            sv.dnc_flag,
            sv.ots_flag,
            sv.fed_review_flag,
            sv.state_tax_flag,
            sv.fnf_flag,

      -- errors 
            er.fed_review_error_flag,
            er.final_review_error_flag,
            er.error_flag,
    
      -- unique_logins 
           ul.unique_logins

        FROM 
        -- test data source
        test t
        left join hypothesis hyp on hyp.experiment_id = t.recipe_id

        -- product funnel 
        left join product_analytics_master pam on t.auth_id = pam.auth_id and t.tax_year = pam.tax_year 
        left join current_sku sku on t.auth_id = sku.auth_id and t.tax_year = sku.tax_year 
        left join abandonment ma on t.auth_id = ma.auth_id and t.tax_year = ma.tax_year 
        left join screen_views sv on t.auth_id = sv.auth_id and t.tax_year = sv.tax_year 
        left join workle_ytd workle on t.pseudonym_id = workle.pseudonym_id and t.tax_year = workle.tax_year 
        left join sham on t.auth_id = sham.auth_id and t.tax_year = sham.tax_year 
        left join platform_switch pl on pl.auth_id = t.auth_id
        left join predicted_s2c def on def.auth_id = t.auth_id and def.tax_year = t.tax_year
        left join errors er on er.pseudonym_id = t.pseudonym_id and er.tax_year = t.tax_year
        left join daily_unique_logins ul on ul.auth_id = t.auth_id and ul.tax_year = t.tax_year


        -- marketing 
        left join marketing_channel mak on t.auth_id = mak.auth_id and t.tax_year = mak.tax_year 

        -- customer profile 
        left join taxml ml on t.auth_id = ml.auth_id and t.tax_year = ml.tax_year 
        left join Segments seg on t.auth_id = seg.auth_id and t.tax_year = seg.tax_year 
        
        -- Assisted/Digital Help 
        left join diwm_entitlements diwm on t.auth_id = diwm.auth_id and t.tax_year = diwm.tax_year 
        left join contact con on t.auth_id = con.auth_id and t.tax_year = con.tax_year 
        left join digital_help dh on dh.entity_id = t.auth_id
        left join ps_contacts ps on t.auth_id = ps.auth_id and t.tax_year = ps.tax_year 

        --Survey 
        left join mps on t.auth_id = mps.auth_id and t.tax_year = mps.tax_year 

        -- monetization 
        left join offer_location_analytics_master olam on  t.auth_id = olam.auth_id and t.tax_year = olam.tax_year 
        left join rt_attach rt on  t.auth_id = rt.auth_id and t.tax_year = rt.tax_year 
        left join ade on t.auth_id = ade.auth_id and t.tax_year = ade.tax_year 
        left join ltv on t.auth_id = ltv.auth_id and t.tax_year = ltv.tax_year 

        where ( first_completed_date >= first_assignment_timestamp OR  first_completed_date IS NULL )
    );

-- -- Creating table for Bayesian
-- -- replace the table name with your experiment_id 
-- DROP TABLE IF EXISTS cgan_general_published.ty25_169730_bayesian; -- update bayesian table name
-- CREATE TABLE cgan_general_published.ty25_169730_bayesian AS -- update bayesian table name
-- select cast(recipe_id as varchar(40)) as experiment_id
--     ,date(first_assignment_timestamp) as cohort_date
--     ,recipe_name as condition
--     ,'Conversion Rate' as metric
--     ,completed_flag as outcome
-- from cgan_ustax_ws.ty25_cg_experimentation_data_169730; -- update with the table name you created above
          
