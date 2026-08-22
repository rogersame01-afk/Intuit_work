# Databricks notebook source -- this worked on feb 15 1am without where statement so now trying it with the with statement after rerunning steps 1 and 2 job
# lets hope it works with the where statement in line and I removed the current date as a field  -- yayy it worked
#from here - https://intuit-e2-570264151593-prd.cloud.databricks.com/editor/notebooks/3308466846699200?o=8126228270435530#command/7018619763966792

# COMMAND ----------

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
S3_LOCATION = "cgcs_nlac_ob_sentiment/cgcs_nlac_ob_sentiment_ty25/cgcs_nlac_ob_sentiment_ty25_mp/cgcs_nlac_ob_sentiment_ty25_mp_contact_list" #"analyst_data/ademeo/test_data_ob_dialer_api" 
S3_TARGET_FILE_NAME = f"798_-{datetime.datetime.now().strftime('%Y%m%d%H')}.csv"  

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
    df.write.mode("append").format("delta").option("mergeSchema", "true").saveAsTable("cgan_ustax_ws.saves_ob_dialer_pipeline_logs_20250101")

# Log stage
log_runtime("start")

# Query latest log
df = spark.sql("select DATE_FORMAT(from_utc_timestamp(runtime_ts_utc, 'PST'), 'yyyy-MM-dd HH:mm:ss') as runtime_ts_pst, is_superglue_run, script_name, stage, run_timezone from cgan_ustax_ws.saves_ob_dialer_pipeline_logs_20250101 order by 1 desc limit 10")
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

# MAGIC %md
# MAGIC # Create Historical File 
# MAGIC Create outbound audience as dataframe for loading into s3 folder. this will contain both test and control

# COMMAND ----------

from datetime import datetime

# Print current timestamp
print(datetime.now())

# Spark SQL Query
df_s3 = spark.sql("""
    SELECT  
        ' ' AS dummy,
        'VOICE' AS ChannelType, 
        phone AS Address, 
        'ACTIVE' AS EndpointStatus, 
        pseudonym_id AS UserId, 
        first_name AS FirstName, 
        last_name AS LastName, 
        'SENTIMENT' AS intuCallType, 
        `date_qualified`, 
       -- current_date() AS date_today,
        response_id, 
        test_group, 
        auth_id, 
        email_address
    FROM   cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_final 
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

# MAGIC %md
# MAGIC checking that we can convert into csv successfully

# COMMAND ----------

try:
    # Convert DataFrame to CSV string
    content = pd_df_s3.to_csv(index=False)

    # Check if content is not empty
    if content.strip():  # Strip removes any leading/trailing whitespace to ensure it's truly empty
        print("DataFrame successfully converted to CSV.")
        # Further actions with 'content' (e.g., saving to a file or sending over API)
        # Example: Save to file
        with open("output.csv", "w") as f:
            f.write(content)
        print("CSV content saved to 'output.csv'.")
    else:
        print("Warning: The CSV content is empty. Check your DataFrame.")

except Exception as e:
    print(f"Error converting DataFrame to CSV: {e}")

# COMMAND ----------
# Check the current day of the week (0 = Monday, 6 = Sunday)
current_day = datetime.today().weekday()

if current_day >= 5:
    # Saturday (5) or Sunday (6)
    print("Today is a weekend. Skipping file upload.")
else:
    # Monday–Friday: Proceed with upload
    csv = pd_df_s3.to_csv()
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

# MAGIC %md
# MAGIC
