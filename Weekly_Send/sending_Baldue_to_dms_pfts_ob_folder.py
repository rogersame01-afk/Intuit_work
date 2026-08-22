# Databricks notebook source
%pip install --upgrade pandas

# COMMAND ----------

import platform
import datetime as dt
import boto3
import os
from pprint import pp

from pyspark.sql.functions import when, col
from pyspark.sql.types import StringType

# ----------------------------
# AWS + S3 configuration
# ----------------------------
AWS_REGION = "us-west-2"
USER_ROLE  = "arn:aws:iam::412714670508:role/analyst_ustax_prd"

S3_CLIENT = None
S3_TARGET_BUCKET = "pfts-processing-cgan-prd"
S3_LOCATION = "outbound_data/teamdms"

# NOTE: S3_TARGET_FILE_NAME is set later AFTER row_count is computed.

# COMMAND ----------

# Extract notebook and script names (Databricks)
notebook_name = dbutils.notebook.entry_point.getDbutils().notebook().getContext().notebookPath().get()
script_name = notebook_name.split("/")[-1]

def log_runtime(stage: str):
    """
    Logs runtime environment and creates AWS session + S3 client.
    Writes to Delta table: cgan_ustax_ws.saves_ty25_tax_efile_reject_weekly_send_letter_dm_202601
    """
    global S3_CLIENT

    data = [(
        stage,
        dt.datetime.utcnow(),
        script_name,
        platform.system(),
        str(platform.uname()),
        notebook_name
    )]

    df_log = spark.createDataFrame(
        data,
        ["stage", "runtime_ts_utc", "script_name", "platform_system", "platform_uname", "notebook_name"]
    )

    df_log = df_log.withColumn(
        "environment_name",
        when(col("notebook_name").like("%/Repos/.internal/%"), "Superglue").otherwise("Databricks")
    ).withColumn(
        "is_superglue_run",
        when(col("environment_name") == "Superglue", True).otherwise(False)
    )

    df_log.createOrReplaceTempView("temp_df")
    df_log = spark.sql("SELECT *, current_timezone() as run_timezone FROM temp_df")

    SUPERGLUE_RUN = df_log.select("is_superglue_run").collect()[0][0]

    if not SUPERGLUE_RUN:
        # Databricks credentials passthrough assume role
        dbutils.credentials.assumeRole(USER_ROLE)
        AWS_CRED = dbutils.credentials.getCurrentCredentials()

        AWS_SESS = boto3.Session(
            aws_access_key_id=AWS_CRED["aws_access_key_id"],
            aws_secret_access_key=AWS_CRED["aws_secret_access_key"],
            aws_session_token=AWS_CRED["aws_session_token"],
            region_name=AWS_REGION
        )
    else:
        # Superglue path (plain boto STS assume role)
        sts_client = boto3.client("sts", region_name=AWS_REGION)
        assumed_role_object = sts_client.assume_role(
            RoleArn=USER_ROLE,
            RoleSessionName="Assumerole1"
        )
        AWS_CRED = assumed_role_object["Credentials"]

        AWS_SESS = boto3.Session(
            aws_access_key_id=AWS_CRED["AccessKeyId"],
            aws_secret_access_key=AWS_CRED["SecretAccessKey"],
            aws_session_token=AWS_CRED["SessionToken"],
            region_name=AWS_REGION
        )

    S3_CLIENT = AWS_SESS.client("s3")

    (df_log.write
        .mode("append")
        .format("delta")
        .option("mergeSchema", "true")
        .saveAsTable("cgan_ustax_ws.saves_ty25_tax_efile_reject_weekly_send_letter_dm_202601")
    )

# Log start
log_runtime("start")

# Quick view latest logs
df_logs = spark.sql("""
  SELECT
    DATE_FORMAT(from_utc_timestamp(runtime_ts_utc, 'PST'), 'yyyy-MM-dd HH:mm:ss') AS runtime_ts_pst,
    is_superglue_run,
    script_name,
    stage,
    run_timezone
  FROM cgan_ustax_ws.saves_ty25_tax_efile_reject_weekly_send_letter_dm_202601
  ORDER BY 1 DESC
  LIMIT 10
""")
display(df_logs)

# COMMAND ----------

def generate_object_key(location: str, filename: str, make_unique: bool = False) -> str:
    """
    Generate S3 object key. Optionally add a UTC timestamp suffix to avoid overwrite.
    """
    ts = ""
    if make_unique:
        ts = "_" + dt.datetime.utcnow().strftime("%Y%m%d-%H%M%S")

    parts = filename.rsplit(".", 1)
    if len(parts) != 2:
        return f"{location}/{filename}{ts}"

    name, ext = parts
    return f"{location}/{name}{ts}.{ext}"

# COMMAND ----------

# Spark SQL Query
df_s3 = spark.sql("""
    SELECT
        auth_id,
        pseudonym_id,
        cust_first_name,
        cust_last_name,
        turbotax_taxPrep_mailingAddress_street,
        street_addr_2,
        city_name,
        state_code,
        us_zip_code,
        masked_login_name,
        cjo_file_name,
        direct_mail_type,
        date_qualified,
        date_qualified_timestamp
    FROM cgan_ustax_ws.efile_weekly_est_refund_baldue_ty25_cjo_auth_final_updated
    WHERE date_qualified = current_date()
    AND direct_mail_type = 'Baldue'
""")

# Compute row count safely (no toPandas)
row_count = df_s3.count()
print(f"Number of rows (Spark count): {row_count}")

# Build filename AFTER row_count exists — no colons, safe for S3 and downstream systems
S3_TARGET_FILE_NAME = (
    f"TY25_FERCJO_directMail_balDue_"
    f"{row_count}records_"
    f"{dt.datetime.utcnow().strftime('%Y%m%d%H')}.csv"
)
print("Target filename:", S3_TARGET_FILE_NAME)

# COMMAND ----------

# Skip upload on weekends
current_day = dt.datetime.utcnow().weekday()  # Monday=0 ... Sunday=6

if current_day >= 5:
    print("Today is a weekend. Skipping file upload.")
else:
    tmp_dir = f"dbfs:/tmp/efile_reject_weekly_send_letter_export/{dt.datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    local_dir = tmp_dir.replace("dbfs:", "/dbfs")

    # Cast all columns to string + uppercase headers
    df_out = df_s3.select([col(c).cast(StringType()).alias(c) for c in df_s3.columns])
    df_out = df_out.toDF(*[c.upper() for c in df_out.columns])

    # Write as TSV (tab-separated) with header
    (df_out.coalesce(1)
        .write
        .mode("overwrite")
        .option("header", "true")
        .option("escape", "\\")
        .option("sep", "\t")
        .csv(tmp_dir)
    )

    if not os.path.isdir(local_dir):
        raise RuntimeError(f"Local dir does not exist: {local_dir}")

    # Find the Spark part file
    part_file = next(
        (os.path.join(local_dir, f) for f in os.listdir(local_dir) if f.startswith("part-")),
        None
    )

    if part_file is None:
        raise RuntimeError(f"No part file found in {local_dir}")

    local_size_bytes = os.path.getsize(part_file)
    print(f"Found part file: {part_file}")
    print(f"Local part file size: {local_size_bytes} bytes ({local_size_bytes / 1024 / 1024:.2f} MB)")

    # Read directly from part file — skip redundant intermediate .csv copy
    with open(part_file, "rb") as fh:
        body_bytes = fh.read()

    s3_key = generate_object_key(S3_LOCATION, S3_TARGET_FILE_NAME, make_unique=False)

    try:
        s3_resp_add = S3_CLIENT.put_object(
            Bucket=S3_TARGET_BUCKET,
            Key=s3_key,
            Body=body_bytes,
            ContentType="text/plain"
        )
    except Exception as e:
        raise RuntimeError(f"Failed to upload to S3: {e}")

    print(f"Uploaded to s3://{S3_TARGET_BUCKET}/{s3_key}")
    pp(s3_resp_add.get("ResponseMetadata", {}))

    # Confirm uploaded object size via S3 HEAD
    try:
        head = S3_CLIENT.head_object(Bucket=S3_TARGET_BUCKET, Key=s3_key)
        s3_size = head.get("ContentLength")
        print(f"S3 object size: {s3_size} bytes ({s3_size / 1024 / 1024:.2f} MB)")
    except Exception as e:
        print(f"Couldn't retrieve S3 head_object: {e}")

# COMMAND ----------

# Review S3 files under the prefix
s3_resp_list = S3_CLIENT.list_objects_v2(Bucket=S3_TARGET_BUCKET, Prefix=S3_LOCATION)
objects_list = s3_resp_list.get("Contents", [])

print(f"Object list for s3://{S3_TARGET_BUCKET}/{S3_LOCATION}")

if objects_list:
    for obj in objects_list:
        print(f"Key: {obj['Key']}, LastModified: {obj['LastModified']}, Size: {obj['Size']} bytes")
else:
    print(" ===> no files !!!")

# COMMAND ----------

# Log end
log_runtime("end")
print("Done.")
