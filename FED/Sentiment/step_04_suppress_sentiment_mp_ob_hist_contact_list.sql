--This step provides the historical contact list based on the call lists provided to the OB Partner Concentrix for the TY23 Sentiment Experience
--TO-DO:
--Create new S3 bucket to house the historical records 
--Update S3 Bucket URL
--1.10.25 pooja created this s3 bucket for ty25 
--'s3://idl-cgan-ustax-processing-cgan-prd/cgcs_nlac_ob_sentiment/cgcs_nlac_ob_sentiment_ty25/cgcs_nlac_ob_sentiment_ty25_mp/cgcs_nlac_ob_sentiment_ty25_mp_contact_list/'
--need to test this out
--1.20.25 added pseudonum and auth id. as well as dummy because adding the timestamp field in python code created a row number which was saved as an unnamed column
--1.21.25 removed dummy since its not needed and I removed it in step 03 python code
--2.2.25 added email address matt miller request

DROP TABLE IF EXISTS cgan_ustax_ws.nlac_ob_sentiment_contact_list_ty25_stg;
CREATE EXTERNAL TABLE cgan_ustax_ws.nlac_ob_sentiment_contact_list_ty25_stg ( 
 dummy STRING,
 dummy2 string,
 ChannelType string, 
 Address string, 
 EndpointStatus string, 
 UserId string, 
 FirstName string, 
 LastName string, 
 intuCallType string, 
 date_qualified  string,
 response_id  string, 
 test_group string , 
 auth_id string,
 email_address string
      )
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
"separatorChar" = ",", 
  "quoteChar" = '"',
  "escapeChar" = "\\"
)
STORED AS
INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
  's3://idl-cgan-ustax-processing-cgan-prd/cgcs_nlac_ob_sentiment/cgcs_nlac_ob_sentiment_ty25/cgcs_nlac_ob_sentiment_ty25_mp/cgcs_nlac_ob_sentiment_ty25_mp_contact_list/'
TBLPROPERTIES (
  's3select.format'='csv'
  ,'has_encrypted_data'='false'
  ,'skip.header.line.count'='1'
  ); 
  
  DROP TABLE IF EXISTS cgan_ustax_ws.nlac_ob_sentiment_contact_list_ty25; 
CREATE TABLE cgan_ustax_ws.nlac_ob_sentiment_contact_list_ty25 as   
select   
  ChannelType ,  
 EndpointStatus , 
 UserId as pseudonym_id,  
 intuCallType , 
 date_qualified  ,
 response_id , 
 test_group , 
 auth_id as qualified_auth_id
from cgan_ustax_ws.nlac_ob_sentiment_contact_list_ty25_stg a
where a.UserId NOT IN ('testing','pseudonym_id','User.UserId')
;
-- DROP TABLE IF EXISTS cgan_ustax_ws.nlac_ob_sentiment_contact_list_historical_ty25; 
INSERT INTO cgan_ustax_ws.nlac_ob_sentiment_contact_list_historical_ty25
(
ChannelType,
pseudonym_id,
date_qualified,
qualified_auth_id,
test_group,
last_modified
)
SELECT
ChannelType,
pseudonym_id,
date_qualified,
qualified_auth_id,
test_group,
CAST(date_qualified AS DATE) as last_modified
FROM cgan_ustax_ws.nlac_ob_sentiment_contact_list_ty25 a;


