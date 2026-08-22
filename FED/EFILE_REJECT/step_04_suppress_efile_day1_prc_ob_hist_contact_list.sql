--used var called dummy for vendor from 2.26.25 onwards
DROP TABLE IF EXISTS cgan_ustax_ws.efile_day9_epc_contact_list_ty25_stg;
CREATE EXTERNAL TABLE cgan_ustax_ws.efile_day9_epc_contact_list_ty25_stg ( 
 dummy STRING,
 dummy2 string,
 ChannelType string, 
 Address string, 
 EndpointStatus string, 
 intuCallType string,
 UserId string, 
 auth_id string,
 FirstName string, 
 LastName string, 
 date_qualified  string,
 state_code  string, 
 cjo_file_name string, 
 email string
      )
       
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
"separatorChar" = ",",
"escapeChar" ="\\"
)
STORED AS
INPUTFORMAT
  'org.apache.hadoop.mapred.TextInputFormat'
OUTPUTFORMAT
  'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION
 's3://idl-cgan-ustax-processing-cgan-prd/efile_rejects_epc/efile_rejects_epc_ty25/efile_rejects_epc_ty25_cjo_contact_list_customers_day_9/'
 TBLPROPERTIES (
  's3select.format'='csv'
  ,'has_encrypted_data'='false'
  ,'skip.header.line.count'='1'
  );

-- CREATE TABLE cgan_ustax_ws.efile_day9_epc_contact_list_ty25 as
Insert INTO cgan_ustax_ws.efile_day9_epc_contact_list_ty25
select 
 pseudonym_id,
 auth_id,
 date_qualified,
CURRENT_TIMESTAMP AS Last_modified
from cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_consent a;

-- CREATE TABLE  cgan_ustax_ws.efile_rejects_epc_ty25_cjo_final_concentrix_days_historical as

INSERT INTO cgan_ustax_ws.efile_day9_epc_contact_list_ty25_daily (
    auth_id,
    pseudonym_id,
    date_qualified
)
SELECT 
    s.userid,
    s.intucalltype,
    s.lastname
FROM cgan_ustax_ws.efile_day9_epc_contact_list_ty25_stg s
WHERE 
    s.userid <> 'User.UserAttributes.IntuAuthId'
    AND s.intucalltype <> 'User.UserId'
    AND s.lastname <> 'date_qualified'
    AND NOT EXISTS (
        SELECT 1
        FROM cgan_ustax_ws.efile_day9_epc_contact_list_ty25_daily t
        WHERE t.auth_id = s.userid
          AND t.pseudonym_id = s.intucalltype
          AND t.date_qualified = s.lastname
    );

Insert INTO  cgan_ustax_ws.efile_rejects_epc_ty25_cjo_final_concentrix_days_historical
select 
 pseudonym_id,
 auth_id,
CURRENT_TIMESTAMP AS Last_modified
from cgan_ustax_ws.efile_rejects_epc_ty25_cjo_final_concentrix_days_2_and_9 a;

-- INSERT INTO cgan_ustax_ws.efile_rejects_epc_ty25_cjo_final_concentrix_days_daily (
--     auth_id,
--     pseudonym_id,
--     date_qualified
-- )
-- SELECT 
--     src.auth_id,
--     src.pseudonym_id,
--     src.date_qualified
-- FROM (
--     SELECT auth_id, pseudonym_id, date_qualified
--     FROM cgan_ustax_ws.efile_day1_epc_contact_list_ty25_daily
    
--     UNION ALL
    
--     SELECT auth_id, pseudonym_id, date_qualified
--     FROM cgan_ustax_ws.efile_day9_epc_contact_list_ty25_daily
-- ) src
-- WHERE NOT EXISTS (
--     SELECT 1
--     FROM cgan_ustax_ws.efile_rejects_epc_ty25_cjo_final_concentrix_days_daily d
--     WHERE d.auth_id = src.auth_id
--       AND d.pseudonym_id = src.pseudonym_id
--       AND d.date_qualified = src.date_qualified
-- );

