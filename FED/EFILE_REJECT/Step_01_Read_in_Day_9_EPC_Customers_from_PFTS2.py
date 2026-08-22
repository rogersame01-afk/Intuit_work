# Databricks notebook source

from pyspark.sql.functions import input_file_name, regexp_extract, to_date, when
from pyspark.sql import functions as F

# Step 1: Load all .csv.gz files
base_path = "s3://pfts-processing-cgan-prd/inbound_data/in_house_dialer/"
df_raw = spark.read.option("header", True).csv(f"{base_path}*.csv.gz")

# Step 2: Filter to only target files
df_filtered = df_raw.withColumn("full_path", input_file_name()) \
    .filter(
        F.col("full_path").contains("TY25_FERCJO_epcDay9") 
    )

# Step 3: Extract base filename without extension
df_filtered = df_filtered.withColumn(
    "file_name",
    regexp_extract("full_path", r"([^/]+)\.csv\.gz$", 1)
)

# Step 4: Extract date from filename: ..._YYYYMMDD_HHMMSS
df_filtered = df_filtered.withColumn(
    "dt_str",
    regexp_extract("file_name", r"_(\d{8})_", 1)
).withColumn(
    "dt",
    to_date("dt_str", "yyyyMMdd").cast("string")
)


# Step 5: Set prerecorded_call based on file_name
df_filtered = df_filtered.withColumn(
    "prerecorded_call",
    when(F.col("file_name").contains("TY25_FERCJO_prcDay2_new"), "new")
    .when(F.col("file_name").contains("TY25_FERCJO_prcDay2_returning"), "returning")
)

# Step 6: Build final schema
df_final = df_filtered.select(
    F.col("pseudonym_id"),
    F.col("phone"),
    F.col("state_code"),
    F.col("first_name"),
    F.col("last_name"),
    F.col("email"),
    F.col("dt"),
    F.col("file_name").alias("cjo_file_name"),
    F.col("prerecorded_call")
)

# Step 7: Register as managed Spark SQL table
spark.sql("DROP TABLE IF EXISTS cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2_stg")
df_final.write.mode("overwrite").saveAsTable("cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2_stg")


# COMMAND ----------

# COMMAND ----------
# MAGIC %sql
# MAGIC --DROP TABLE IF EXISTS cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2;
# MAGIC --CREATE TABLE cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2 AS
# MAGIC INSERT INTO cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2
# MAGIC SELECT *
# MAGIC FROM cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2_stg s
# MAGIC WHERE DATE(dt) > '2026-03-07'
# MAGIC AND NOT EXISTS (
# MAGIC     SELECT 1
# MAGIC     FROM cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2 t
# MAGIC     WHERE t.pseudonym_id = s.pseudonym_id
# MAGIC )
# MAGIC ;



# COMMAND ----------

# MAGIC %sql
# MAGIC select dt, cjo_file_name, count(*) as total, count(distinct pseudonym_id) as distinct_customers from cgan_ustax_ws.efile_rejects_day9_epc_ty25_cjo_staging_pftsv2 group by 1,2 order by 1 desc;

