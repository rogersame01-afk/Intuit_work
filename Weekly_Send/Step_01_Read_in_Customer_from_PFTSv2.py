# Databricks notebook source
from pyspark.sql.functions import input_file_name, regexp_extract, to_date, when
from pyspark.sql import functions as F

# Step 1: Load all .csv.gz files
base_path = "s3://pfts-processing-cgan-prd/outbound_data/teamdms/"
df_raw = spark.read.option("header", True).csv(f"{base_path}*.csv.gz")

# Step 2: Filter to only target files
df_filtered = df_raw.withColumn("full_path", input_file_name()) \
    .filter(
        F.col("full_path").contains("TY25_FERCJO_directMail_balDue") |
        F.col("full_path").contains("TY25_FERCJO_directMail_EstRefund") |
        F.col("full_path").contains("TY25_FERCJO_directMail_Est_refund")
    )

# Step 3: Extract base filename without extension
df_filtered = df_filtered.withColumn(
    "file_name",
    regexp_extract("full_path", r"([^/]+)\.csv\.gz$", 1)
)

# Step 4: Extract date from filename: ..._YYYYMMDD_...
# Handles both: _20260317_7076 and _20260317_HHMMSS
df_filtered = df_filtered.withColumn(
    "dt_str",
    regexp_extract("file_name", r"_(\d{8})_", 1)
).withColumn(
    "dt",
    to_date("dt_str", "yyyyMMdd").cast("string")
)

# Step 5: Set direct_mail_type based on file_name
df_filtered = df_filtered.withColumn(
    "direct_mail_type",
    when(F.col("file_name").contains("TY25_FERCJO_directMail_balDue"), "Baldue")
    .when(F.col("file_name").contains("TY25_FERCJO_directMail_EstRefund"), "Est_Refund")
    .when(F.col("file_name").contains("TY25_FERCJO_directMail_Est_refund"), "Est_Refund")
)

# Step 6: Build final schema
df_final = df_filtered.select(
    F.col("pseudonym_id"),
    F.col("cust_first_name"),
    F.col("cust_last_name"),
    F.col("addr_line_1"),
    F.col("city_name"),
    F.col("state_code"),
    F.col("us_zip_code"),
    F.col("dt"),
    F.col("file_name").alias("cjo_file_name"),
    F.col("direct_mail_type")
)

# Step 7: Write to managed Spark SQL table
df_final.write.mode("overwrite").saveAsTable("cgan_ustax_ws.efile_rejects_directmail_weekly_ty25_cjo_staging_pftsv2_stg")
