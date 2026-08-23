# Databricks notebook source
# MAGIC %md
# MAGIC # Saves Smartsheet Data Lake Ingestion
# MAGIC
# MAGIC [Smartsheet Outreach Campaigns Roadmap](https://app.smartsheet.com/sheets/jrmQfMW7HGq34XRRqRc2mJv8whCx734wqJjgP5P1?view=grid)
# MAGIC [DB Notebook](https://intuit-e2-570264151593-prd.cloud.databricks.com/?o=8126228270435530#notebook/1596490395397943/command/1596490395397976)

# COMMAND ----------

pip install smartsheet-python-sdk

# COMMAND ----------

pip install pandas 

# COMMAND ----------

# import packages
from smartsheet import Smartsheet
import pandas as pd

# COMMAND ----------


# Smartsheet API token and sheet ID
access_token = 'wJpM5IWAT02xKiDpqVBXHwnpEpgdi2nQiXhUg' # your_api_token

# authenticate
client = Smartsheet(access_token)
# specify sheet id
sheet_id = '4898791518850948' # your_sheet_id

# Fetch sheet using ID
sheet = client.Sheets.get_sheet(sheet_id)
rows = sheet.rows
columns = sheet.columns

# Check sheet is fetched successfully
print(f"Sheet Name: {sheet.name}")
print(f"Number of columns: {len(sheet.columns)}")
print(f"Number of rows: {len(sheet.rows)}")

# COMMAND ----------

# extract column metadata
column_ids = {col.id: col.title for col in sheet.columns}

# Extract data into a list of dictionaries
data = []
for row in rows:
    row_data = {}
    for cell in row.cells:
        column_name = column_ids.get(cell.column_id)
        if column_name:
            row_data[cell.column_id] = cell.value
    data.append(row_data)


# Create a new dictionary to store the modified data
new_data = []
for row in data:
    new_row = {}
    for column_id, value in row.items():
        column_title = column_ids.get(column_id)
        if column_title:
            new_row[column_title] = str(value).replace(" ", "_") if value is not None else value
    new_data.append(new_row) 
data = new_data

print(data)

# COMMAND ----------

# Create a Pandas DataFrame
df = pd.DataFrame(data)

# Clean and transform the data as needed (e.g., handle missing values, convert data types)
df = df.fillna('N/A')
df = df.astype('str')
df.columns = df.columns.str.replace(' ', '_')
df.columns = df.columns.str.replace('?', '')
df.columns = df.columns.str.replace('(', '')
df.columns = df.columns.str.replace(')', '')
df.columns = df.columns.str.replace('-', '_')
df.columns = df.columns.str.replace('/', '_')
df = df.rename(columns={'Stack_Rank_for_Email_Ops': 'Stack_Rank'})
# Add a new column 'timestamp' with the current timestamp
df['timestamp_ingested_utc'] = pd.Timestamp.now(tz='UTC')

df.iteritems = df.items
df.display()

# COMMAND ----------

spark_df = spark.createDataFrame(df)

#use mode function, overwrite will replace a table if its already being used
# spark_df.write.mode('overwrite').format('parquet').saveAsTable('schema_name.table_name')
spark_df.write.mode('overwrite').format('parquet').saveAsTable('cgan_ustax_ws.Saves_Smartsheet_Outreach_Campaigns_Roadmap_ty24')

# COMMAND ----------

# MAGIC %sql
# MAGIC select * from cgan_ustax_ws.temp_20241123_saves_smartsheet_rev
