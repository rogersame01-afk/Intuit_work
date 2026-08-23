# Databricks notebook source
# MAGIC %md
# MAGIC # Load Audience to Historical S3

# COMMAND ----------

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
S3_LOCATION = "cgcs_sub_par_experiences/subpar_ty24_cch/sub_par_ty24/ty24_audience" #"analyst_data/ademeo/test_data_ob_dialer_api" 
S3_TARGET_FILE_NAME = f"sub_par_ty24_em-{datetime.datetime.now().strftime('%Y%m%d%H')}.csv"  


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
    Table - cgan_ustax_ws.saves_sub_par_historical_log_20250623
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

    # Write the DataFrame to a table named cgan_ustax_ws.saves_sub_par_historical_log_20250623
    df.write.mode("overwrite").format("delta").option("mergeSchema", "true").saveAsTable("cgan_ustax_ws.saves_sub_par_historical_log_20250623")

# Log stage
log_runtime("start")

# Query latest log
df = spark.sql("select DATE_FORMAT(from_utc_timestamp(runtime_ts_utc, 'PST'), 'yyyy-MM-dd HH:mm:ss') as runtime_ts_pst, is_superglue_run, script_name, stage, run_timezone from cgan_ustax_ws.saves_sub_par_historical_log_20250623 order by 1 desc limit 10")
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
    SELECT DISTINCT
      external_id as pseudonym_id
    , issue_type 
    , date_issue 
    , date_qualified 
    , cell 
    , ('cso541_' || cell) as mpm_cell 
    , DATE_FORMAT(date_qualified, 'yyyyMMdd') as dt 
    , 'cso541' as mpm 
    FROM cgan_ustax_ws.sub_par_ty24_04_em_base_final
   where date_qualified = current_date()
   and external_id != 'external_id'
""")

# Convert to pandas DataFrame
pd_df_s3 = df_s3.toPandas()


# Display the first few rows of the Spark DataFrame
# df_s3.show()  # Use .show() for Spark DataFrame instead of .head()
pd_df_s3.head()

# COMMAND ----------


csv = pd_df_s3.to_csv()
s3_resp_add = S3_CLIENT.put_object(Bucket=S3_TARGET_BUCKET, 
                                  Key=generate_object_key(S3_LOCATION, S3_TARGET_FILE_NAME, False), 
                                Body=csv)

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

# COMMAND ----------

# MAGIC %md
# MAGIC # Send email audience to Braze API 

# COMMAND ----------

pip install requests

# COMMAND ----------

import requests
import json
from pyspark.sql import Row

# Braze REST API key and endpoint
BRAZE_API_KEY = "4a7beb42-16fa-46d1-a1cd-5ca053d62ed5"
BRAZE_ENDPOINT = "https://rest.iad-03.braze.com"  # Update region if needed

headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {BRAZE_API_KEY}"
}

# COMMAND ----------


## Instead basing this data off of a spark sql table: 
# Step 1: Query the table
df = spark.sql("select distinct external_id, ('cso541_' || cast(cell as string)) as mpm_cell from cgan_ustax_ws.sub_par_ty24_04_em_base_final where date_qualified = cast(current_timestamp as date)")
#df = spark.sql("SELECT distinct digitalIdentityPseudonymId as external_id, 'testing_value' as testabc_20250429 FROM intuit_foundation_identityandcustomer360_unified_dwh.person_account where digitalIdentityPseudonymId = 'pseudonym_id'") # example for reference

# Step 2: Convert to list of dictionaries
data = df.toPandas().to_dict(orient="records")

# Step 3: Inspect result
print(data)


# COMMAND ----------

BATCH_SIZE = 75  # You can tune this value to stay under Braze's payload size limit

# Function to send data to Braze
def send_to_braze(users_batch):
    payload = {"attributes": users_batch}
    response = requests.post(
        f"{BRAZE_ENDPOINT}/users/track",
        headers=headers,
        data=json.dumps(payload)
    )
    if response.status_code == 201:
        print(f"✅ Sent batch of {len(users_batch)} users")
    else:
        print(f"❌ Failed batch: {response.status_code} - {response.text}")

# COMMAND ----------

# Collect data from Spark DataFrame and send to Braze
users_list = df.toPandas().to_dict(orient="records")
# Send in batches
for i in range(0, len(users_list), BATCH_SIZE):
    batch = users_list[i:i + BATCH_SIZE]
    send_to_braze(batch)

# COMMAND ----------

# MAGIC %sql
# MAGIC --select cell, count(*) as total, count(distinct external_id) as distinct_customers from cgan_ustax_ws.ty24_fbar_pnf_audience_em_base_final where date_qualified = cast(current_timestamp as date) group by 1 order by 1
