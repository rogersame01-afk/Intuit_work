-- original data was pulled from here -- data was pulled daily for past 7 days. 
--https://github.intuit.com/ademeo/cgcs_customer_outreach/blob/master/sentiment/sentiment_ty23/daily_process/mid-product/01_preprosifter/sentiment_mp_ob_00_raw.sql
--https://github.intuit.com/ademeo/cgcs_customer_outreach/blob/master/sentiment/sentiment_ty23/daily_process/mid-product/01_preprosifter/sentiment_mp_ob_00_raw.sql
-- fields pulled included auth ids who completed the survey and were neutral or detractors along with responses to other questions
-- however, responses to other questions were not used elsewhere confirmed this with Kyle on 12.18, so we just need to know who completed survey and was neutral or detractor
-- one ask from erin was to have this run more frequently (kyle used to run daily) because the sooner we contacted the responders the better the outcome
--kraig provided 2 sources of data, I will compare to see which one is faster and provides more frequent data but  12/19 aligned with Alexis to use existing data source as-is
--existing datasource appears to be updating frequently as seen in notebook below
--https://intuit-e2-570264151593-prd.cloud.databricks.com/editor/notebooks/4213449641856827?o=8126228270435530#command/984484037925259
--previously there was a two day lag between survey response and ob call due to the need to run the data through prosifter but since we don't do that this year the lag will be just 1 day
--alexis and I decided that pulling data more frequently than once a day is not feasible since it will not be supported by superglue or the inhouse dialer functionality
--1.13 add in only keeping meh and its bad


--pull survey data from last 7 days from Qualtrics
DROP TABLE IF EXISTS cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_raw_ty25;
CREATE TABLE cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_raw_ty25 AS
select * from 
(
select
          a.responseid as response_id --unique identifier of the actual survey response that the customer submits
        , a.responsesubmitdate as date_end --the timestamp of when the customer submitted the survey
        , a.primaryid as auth_id
        , a.product 
        
        , a.surveyid as survey_id --unique identifier for the mid-product survey (i.e. 'SV_e4MDm0UcxcsN98a')
        , q.surveyname --name of the survey in Qualtrics (i.e. 'TTO Sentiment Feedback Survey')
        , max(case 
                when q.questionname = 'Q1' AND a.question_response = 'Dont Ask' THEN 'Negative'
                when q.questionname = 'Q1' AND a.question_response = 'Not So Good' THEN 'Neutral'
                when q.questionname = 'Q1' AND a.question_response = 'Happy' THEN 'Positive'
                end) as sentiment
        , max(case when q.questionname = 'Q1' then q.questiontext end) as q1_survey_question
        , max(case when q.questionname = 'Q1' then a.question_response end) as q1_response
        , max(case 
	      when q.questionname = 'Q2' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	      when q.questionname = 'Q3' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	      when q.questionname = 'Q4' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	      end) 
	      as q2_survey_question
        , max(case when q.questionname IN ('Q2','Q3','Q4') and a.question_response is not null and trim(a.question_response) != '' then a.question_response end) as q2_response
        , max(case 
	      when q.questionname = 'Q5' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	      when q.questionname = 'Q6' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	      when q.questionname = 'Q7' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext
	      end) 
	      as q3_survey_question
        , max(case when q.questionname IN ('Q5','Q6','Q7') and a.question_response is not null and trim(a.question_response) != '' then a.question_response end) as q3_response
        , max(case when q.questionname = 'Q8' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext end) as q4_survey_question
        , max(case when q.questionname = 'Q8' and a.question_response is not null and trim(a.question_response) != '' then a.question_response end) as q4_response
        , max(case when q.questionname = 'Q9' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext end) as q5_survey_question
        , max(case when q.questionname = 'Q9' and a.question_response is not null and trim(a.question_response) != '' then a.question_response end) as q5_response
        , max(case when q.questionname = 'Q10' and a.question_response is not null and trim(a.question_response) != '' then q.questiontext end) as q6_survey_question
        , max(case when q.questionname = 'Q10' and a.question_response is not null and trim(a.question_response) != '' then a.question_response end) as q6_response
from ent_qualtrics_dwh.di_qual_survey_questions as q 
left join ent_qualtrics_dwh.di_qual_resp_raw as a
        on q.surveyid = a.surveyid
                and q.questionid = a.question_id
where a.finished = '1' --customer completed the survey
	--Mid-Product survey_id filter
        and a.surveyid = 'SV_e4MDm0UcxcsN98a'
	--customer submitted survey in past 5 days
        and datediff(cast(current_timestamp as date), cast(responsesubmitdate as date)) <= 5  
group by 
          a.responseid
        , a.responsesubmitdate 
        , a.primaryid 
        , a.product 
        
        , a.surveyid 
        , q.surveyname)
	
where sentiment in ('Negative','Neutral')
	
;

 
