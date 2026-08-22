# Databricks notebook source
pip install --upgrade pandas

# COMMAND ----------

pip install requests_toolbelt

# COMMAND ----------

import pandas as pd
import datetime
import platform
import boto3
from pprint import pp
from pyspark.sql.functions import when
from requests_toolbelt.multipart.encoder import MultipartEncoder

# Define AWS Parameters and S3_CLIENT as a global variable
AWS_REGION = 'us-west-2'
USER_ROLE = "arn:aws:iam::412714670508:role/analyst_ustax_prd"
S3_CLIENT = None

# Define S3 Outputs 1.13 ask erin what to use for suffix contact id in the target file names
S3_TARGET_BUCKET = "idl-cgan-ustax-processing-cgan-prd"
S3_LOCATION = "efile_rejects_epc/efile_rejects_epc_ty25/efile_rejects_epc_ty25_cjo_contact_list_customers_day_9" #"analyst_data/ademeo/test_data_ob_dialer_api" 
S3_TARGET_FILE_NAME = f"435_-{datetime.datetime.now().strftime('%Y%m%d%H')}.csv"  
# 435 is the contact id for epc to CNX

# COMMAND ----------

# Extract notebook and script names
notebook_name = dbutils.notebook.entry_point.getDbutils().notebook().getContext().notebookPath().get()
script_name = notebook_name.split("/")[-1]

def log_runtime(stage):
    global S3_CLIENT
    """
    Logs the current runtime environment at a given stage of a script and creates an AWS session and S3 client
    
    Args:
    stage (str): The stage of the script run, either "start" or "end".
    
    Outputs:
    Table - cgan_ustax_ws.saves_outbound_dialer_pipeline_logs
    Variable - SUPERGLUE_RUN
    S3_CLIENT - AWS S3 client object
    """
    # Create a DataFrame to log runtime parameters
    data = [(stage, datetime.datetime.utcnow(), script_name, platform.system(), str(platform.uname()), notebook_name)]
    df = spark.createDataFrame(data, ["stage", "runtime_ts_utc", "script_name", "platform_system", "platform_uname", "notebook_name"])
    df = df.withColumn("environment_name", when(df.notebook_name.like("%/Repos/.internal/%"), "Superglue").otherwise("Databricks"))
    df = df.withColumn("is_superglue_run", when(df.environment_name == "Superglue", True).otherwise(False))
    df.createOrReplaceTempView("temp_df")
    df = spark.sql(""" SELECT *, current_timezone() as run_timezone FROM temp_df""")

    # Collect SUPERGLUE_RUN boolean value
    SUPERGLUE_RUN = df.select('is_superglue_run').collect()[0][0]

    # Check SUPEGLUE_RUN value and assume role based on condition
    if not SUPERGLUE_RUN:
        dbutils.credentials.assumeRole(USER_ROLE)
        AWS_CRED = dbutils.credentials.getCurrentCredentials()

        AWS_SESS = boto3.Session(
            aws_access_key_id=AWS_CRED["aws_access_key_id"],
            aws_secret_access_key=AWS_CRED["aws_secret_access_key"],
            aws_session_token=AWS_CRED["aws_session_token"],
            region_name=AWS_REGION)
    else:
        sts_client = boto3.client('sts')
        assumed_role_object = sts_client.assume_role(RoleArn=USER_ROLE, RoleSessionName="Asssumerole1")
        AWS_CRED = assumed_role_object['Credentials']

        AWS_SESS  = boto3.Session(
          aws_access_key_id= AWS_CRED['AccessKeyId'],
          aws_secret_access_key= AWS_CRED['SecretAccessKey'],
          aws_session_token = AWS_CRED['SessionToken'],
          region_name=AWS_REGION)

    # Establish S3 Connection
    S3_CLIENT = AWS_SESS.client(service_name='s3')

    # Write the DataFrame to a table named cgan_ustax_ws.saves_outbound_dialer_pipeline_logs
    df.write.mode("append").format("delta").option("mergeSchema", "true").saveAsTable("cgan_ustax_ws.saves_ob_dialer_pipeline_logs_20241219") # Subject to Change

# Log stage
log_runtime("start")

# Query latest log
df = spark.sql("select DATE_FORMAT(from_utc_timestamp(runtime_ts_utc, 'PST'), 'yyyy-MM-dd HH:mm:ss') as runtime_ts_pst, is_superglue_run, script_name, stage, run_timezone from cgan_ustax_ws.saves_ob_dialer_pipeline_logs_20241219 order by 1 desc limit 10")  # Subject to Change 
df = df.toPandas()
df.head()    

# COMMAND ----------

def generate_object_key(location, filename, make_unique=False):
  """
  Generate unique S3 object keys by adding timestamp 
  so not to overwrite existing files in target S3 location 
  Input:
    location: S3 target location string
    filename: filename in the format filename.ext (such as my_data.csv)
  Output: 
    complete S3 object key (such as my_folder/my_data-20220521-120000.csv)
  """
  # Generate timestamp
  if make_unique:
    ts = "_" + datetime.utcnow().strftime("%Y%m%d-%H%M%S")
    # Extract components of the filename
  else:
    ts = ""
    
  output_filename_parts = filename.split(".")

  # Return the actual filename
  return f"{location}/{output_filename_parts[0]}{ts}.{output_filename_parts[1]}"

# COMMAND ----------

from datetime import datetime

# Print current timestamp
print(datetime.now())

# Spark SQL Query
# values from https://docs.google.com/spreadsheets/d/1k804Z_jxE_WGAaH9XhAGe1e9eVbJNqxBn8Q1S2KqGog/edit?gid=0#gid=0 
df_s3 = spark.sql("""
    SELECT  
        vendor AS dummy,
        'VOICE' AS ChannelType, 
        formatted_phone_number AS Address, 
        'ACTIVE' AS EndpointStatus, 
        'FED_EFILE_REJECT' AS intuCallType, 
        pseudonym_id as UserId, 
        auth_id, 
        first_name AS FirstName, 
        last_name AS LastName, 
        `date_qualified`, 
   --     `date_qualified_timestamp`,
        state_code, 
        cjo_file_name,
 --       prerecorded_call, -- not applicable for epc since we have one file for both new and returning customers
         email
    FROM cgan_ustax_ws.efile_rejects_epc_day9_ty25_cjo_consent
   where `date_qualified`=current_date()
""")



# Convert to pandas DataFrame
pd_df_s3 = df_s3.toPandas()

# Rename columns in the pandas DataFrame
pd_df_s3 = pd_df_s3.rename(columns={
    'UserId': 'User.UserId', 
    'FirstName': 'User.UserAttributes.FirstName', 
    'LastName': 'User.UserAttributes.LastName', 
    'intuCallType': 'User.UserAttributes.intuCallType', 
    'auth_id': 'User.UserAttributes.IntuAuthId',
    'email': 'User.UserAttributes.Email'
})

# Add the current timestamp as a new column -- we don't need this so commenting it out, need to fix the code in step 04 in sql to reflect
# pd_df_s3['qualified_ts'] = datetime.now()

# Reset the index to ensure no unexpected row numbers
# pd_df_s3 = pd_df_s3.reset_index(drop=True)

# Display the first few rows of the Spark DataFrame
# df_s3.show()  # Use .show() for Spark DataFrame instead of .head()
pd_df_s3.head()

# COMMAND ----------

current_day = datetime.today().weekday()

if current_day == 6:
    # Sunday (6)
    print("Today is Sunday. Skipping file upload.")
else:
    # Monday–Saturday: Proceed with upload
    csv = pd_df_s3.to_csv(index=False, escapechar='\\')
    s3_resp_add = S3_CLIENT.put_object(
        Bucket=S3_TARGET_BUCKET,
        Key=generate_object_key(S3_LOCATION, S3_TARGET_FILE_NAME, False),
        Body=csv
    )
    pp(s3_resp_add['ResponseMetadata'])

# COMMAND ----------

# Review S3 files
s3_resp_add2 = S3_CLIENT.list_objects(Bucket=S3_TARGET_BUCKET, Prefix=S3_LOCATION)

# Extract the list of objects from the S3 response
objects_list = s3_resp_add2.get('Contents', None)

print(f"Object lists for s3://{S3_TARGET_BUCKET}/{S3_LOCATION}")

# Check if the objects list is not empty
if objects_list:
    for obj in objects_list:
        print(f"Key: {obj['Key']}, LastModified: {obj['LastModified']}, Size: {obj['Size']} bytes")
else:
    print(" ===> no files !!!")

# COMMAND ----------

row_count = pd_df_s3.shape[0]
print(f"Number of rows: {row_count}")
