# Databricks notebook source
# MAGIC %md
# MAGIC [DB Notebook](https://intuit-e2-739275435815-exploration-prd.cloud.databricks.com/editor/notebooks/541338410506859?o=2986300204636899#command/541338410506860)
# MAGIC [Git](https://github.intuit.com/CGCSData/cgcs-core-cx/blob/master/outreach/planned/sentiment_ty24/dailyprocess/step_05_day3_em_and_ob_recipe_creation.sql)


# COMMAND ----------

# MAGIC %sql
# MAGIC INSERT INTO cgan_ustax_ws.ob_sentiment_day3_ob_and_em_daily_test_historical
# MAGIC SELECT DISTINCT
# MAGIC     base.ChannelType
# MAGIC   , base.EndpointStatus
# MAGIC   , base.pseudonym_id
# MAGIC   , base.intuCallType
# MAGIC   , base.date_qualified
# MAGIC   , base.response_id
# MAGIC   , base.test_group
# MAGIC   , base.qualified_auth_id
# MAGIC   , cast(current_timestamp as date) as date_qualified_email
# MAGIC FROM cgan_ustax_ws.ob_sentiment_day3_ob_and_em_daily_test_ty25 AS base
# MAGIC LEFT JOIN tax_src.src_braze_turbotax_email_delivery AS em
# MAGIC   ON base.pseudonym_id = em.external_user_id
# MAGIC   AND em.canvas_id = 'de4f8dfe-80b9-4bff-b739-3a781709e4d5'
# MAGIC WHERE em.external_user_id IS NULL --did not previously receive email
# MAGIC ;

# COMMAND ----------

# MAGIC %sql
# MAGIC select * from cgan_ustax_ws.ob_sentiment_day3_ob_and_em_daily_test_historical order by date_qualified_email desc

# COMMAND ----------

# MAGIC %md
# MAGIC ### Send qualified email audience to Braze API

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
df = spark.sql("select distinct pseudonym_id as external_id, 1 as mpm_798 from cgan_ustax_ws.ob_sentiment_day3_ob_and_em_daily_test_historical where date_qualified_email = cast(current_timestamp as date)")
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
