# Databricks notebook source
# MAGIC %pip install idps_sdk --quiet -i https://artifact.intuit.com/artifactory/api/pypi/pypi-intuit/simple

# COMMAND ----------


pip install --upgrade pandas

# COMMAND ----------

pip install requests_toolbelt

# COMMAND ----------


from pyspark.sql import SparkSession


# Create SparkSession
def get_spark_session():
  spark = SparkSession.builder \
    .master("local[1]") \
    .appName("env_manager") \
    .getOrCreate()

  return spark


# Load dbutils
def get_dbutils(spark=get_spark_session()):
  try:
    from pyspark.dbutils import DBUtils
    dbutils = DBUtils(spark)
  except ImportError:
    import IPython
    dbutils = IPython.get_ipython().user_ns["dbutils"]

  return dbutils


# COMMAND ----------


def is_superglue_run():
  try:
    superglue_run = False
    roles = dbutils.credentials.showRoles()
  except:
    superglue_run = True

  return superglue_run



# COMMAND ----------


is_superglue_run()


# COMMAND ----------

import json
import requests
import os
from datetime import datetime
from idps_sdk import idps_client
#from .globals import *
#from .dbutils import get_dbutils
#from .superglue import is_superglue_run


SUPERGLUE_RUN = is_superglue_run()

allowed_roles = [
  'arn:aws:iam::412714670508:role/analyst_ustax_sec_prd',
  'arn:aws:iam::412714670508:role/analyst_ustax_prd'
]

IDPS_END_POINT = "vkm.ps.idps.a.intuit.com" 
IDPS_POLICY = 'p-o075b7c137dj' #'p-o075b7c137dj' # 'p-h0z7crhh6n76'  # for analyst_ustax_sec_prd
AWS_REGION = "us-west-2"

def select_role(allowed_roles, available_roles):
  for role in allowed_roles:
    if role in available_roles:
      return role
  return None  # In case no allowed roles are in available roles


def set_env_aws_credentials():
  dbutils = get_dbutils()

  if SUPERGLUE_RUN:
    print("Running through Superglue")

  else:
    role_arn = select_role(allowed_roles, dbutils.credentials.showRoles())

    print(role_arn)

    dbutils.credentials.assumeRole(role_arn)

    cred = dbutils.credentials.getCurrentCredentials()

    os.environ['AWS_ACCESS_KEY_ID'] = cred["aws_access_key_id"]
    os.environ['AWS_SECRET_ACCESS_KEY'] = cred["aws_secret_access_key"]
    os.environ['AWS_SESSION_TOKEN'] = cred["aws_session_token"]
    os.environ['AWS_DEFAULT_REGION'] = AWS_REGION
    os.environ['AWS_EC2_METADATA_DISABLED'] = 'true'


set_env_aws_credentials()

idpsClient = idps_client.IdpsClientFactory.get_instance(
  endpoint=IDPS_END_POINT,
  policy_id=IDPS_POLICY,
  # aws_profile=awsProfile,
  force_generic_policies=True
)

DNC_WHITELIST = ['C','E','Y','X','O','H','G','W','R']
DNC_URL = os.getenv('DNC_URL', 'https://www.dncscrub.com/app/main/rpc/scrub')

def _fetch_dnc_api_key():
   return get_secret('DNC_API_KEY')


def _call_dnc_api(phone_entries, api_key):
  """
  Call the DNC API in batches (API limit: 10k numbers per request).
  """
  headers = {"Content-Type": "application/json", "loginId": api_key}
  batch_size = 10000
  aggregated = []

  total = len(phone_entries)
  batches = (total + batch_size - 1) // batch_size

  for batch_idx in range(batches):
    start = batch_idx * batch_size
    end = min(start + batch_size, total)
    batch = phone_entries[start:end]
    payload = {'phoneList': ','.join(batch), 'version': '5', 'output': 'json'}

    resp = requests.post(DNC_URL, headers=headers, json=payload, timeout=10)
    try:
      resp.raise_for_status()
    finally:
      snippet = resp.text[:500] if resp and resp.text else ''
      print(f"DNC batch {batch_idx + 1}/{batches} size={len(batch)} status={resp.status_code if resp else 'N/A'} resp_snippet={snippet}")

    aggregated.extend(resp.json())

  return aggregated


def filter_out_dnc_numbers(df):
  """
  Uses the existing DNC service to drop numbers that are not allowed.
  The DNC API expects phoneNumber|reserved_id entries; we use the DataFrame index as the reserved id.
  """
  api_key = _fetch_dnc_api_key()
  if not api_key:
    print("Skipping DNC filter because API key could not be retrieved.")
    return df

  phone_entries = []
  index_map = {}
  for idx, row in df.iterrows():
    phone = str(row.get('Address', '')).strip()
    if phone.startswith("+1"):
      phone = phone[2:]
    if phone:
      phone_entries.append(f"{phone}|{idx}")
      index_map[str(idx)] = idx

  if not phone_entries:
    print("No phone numbers found; skipping DNC filter.")
    return df

  try:
    dnc_response = _call_dnc_api(phone_entries, api_key)
  except Exception as e:
    print(f"DNC API call failed; Aborting. Error: {e}")
    exit()
  
  print(f"DNC API call successful; continuing with processing.")

  bad_ids = set()
  for item in dnc_response:
    result_code = item.get('ResultCode')
    reserved = item.get('Reserved')
    if result_code not in DNC_WHITELIST:
      bad_ids.add(reserved)

  if not bad_ids:
    print("DNC filter did not remove any numbers.")
    return df

  # Drop rows whose reserved id (DataFrame index) was rejected
  filtered_df = df.drop(index=[index_map[r] for r in bad_ids if r in index_map])
  print(f"DNC filter removed {len(bad_ids)} numbers; remaining rows: {len(filtered_df)}")
  return filtered_df

def get_secret(secret_name):
  # set_env_aws_credentials()

  secret = idpsClient.get_secret(secret_name).get_string_value()

  return str(secret)

app_secret = get_secret('InHouseDialer')
#add dev portal username saved instead of hardcoding
username = get_secret('InHouseDialer_UserName')
#add dev portal password 
password = get_secret('InHouseDialer_Password')


# COMMAND ----------

app_secret

# COMMAND ----------

username

# COMMAND ----------

password

# COMMAND ----------



#appid
appid = "Intuit.cg.analytics.savesoutbounddialer" #https://devportal.intuit.com/app/dp/resource/5050804575420355370/report

#access url
access_url = "https://identityinternal.api.intuit.com/signin/graphql"

# Set the body 
data = {
    "query": "mutation identityTestSignInWithPassword($input: Identity_TestSignInWithPasswordInput!) { identityTestSignInWithPassword(input: $input) { accessToken legacyAuthId } }",
    "variables": {
        "input": {
            "username": username,
            "password": password,
            "tenantId": "",
            "intent": {
                "appGroup": appid,
                "assetAlias": appid
            }
        }
    }
}

# Set the header 
headers={
  "Content-Type": "application/json",
  "Authorization": "Intuit_IAM_Authentication "
  + f'intuit_appid={appid},'
  + f'intuit_app_secret={app_secret},'
  +"intuit_token_type=IAM-Ticket"
}
# Get the offline token 
response = requests.post(access_url, data=json.dumps(data), headers=headers)
# Parse the JSON response.text
parsed_data = json.loads(response.text)
# Parse the JSON response.text for intuit_token_ticket
intuit_token_ticket = parsed_data['data']['identityTestSignInWithPassword']['accessToken']

print(intuit_token_ticket)  # Output: tokenvalue

# Parse the JSON response.text for userid
userid = parsed_data['data']['identityTestSignInWithPassword']['legacyAuthId']

print(userid)  # Output: tokenvalue


# COMMAND ----------


response.text


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


df = spark.sql("""
    SELECT DISTINCT 
        'VOICE' AS ChannelType, 
        phone AS Address, 
        'ACTIVE' AS EndpointStatus, 
        auth_id AS UserId, -- changed this from pseudoonym_id to auth id on 2.4.25 for iep per matt mpip install requests_toolbelt
        first_name AS FirstName, 
        last_name AS LastName, 
        'SENTIMENT' AS intuCallType ,         
        auth_id, 
        email_address
    FROM  
     cgan_ustax_ws.nlac_sentiment_ob_initial_surveys_mp_norm_ty25_final
    where Test_Group='Test'
    and date_qualified = current_date()
    limit 25000
""")

pd_df = df.toPandas()
pd_df = pd_df.rename(columns={
    'UserId': 'User.UserId', 
    'FirstName': 'User.UserAttributes.FirstName', 
    'LastName': 'User.UserAttributes.LastName', 
    'intuCallType': 'User.UserAttributes.intuCallType',  
    'auth_id': 'User.UserAttributes.IntuAuthId' ,        
    'email_address': 'User.UserAttributes.Email'
    
})

pd_df.head()

# COMMAND ----------


row_count = pd_df.shape[0]
print(f"Number of rows: {row_count}")

# COMMAND ----------


try:
    # Convert DataFrame to CSV string
    content = pd_df.to_csv(index=False)

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


csv_string = pd_df.to_csv(index=False)  # Convert DataFrame to CSV
csv_size = len(csv_string.encode())  # Get file size in bytes

# Print file size in human-readable format
print(f"CSV Size: {csv_size} bytes ({csv_size / 1024:.2f} KB, {csv_size / (1024*1024):.2f} MB)")

# COMMAND ----------

# In-House Dialer Endpoint  -- this worked on 2/2/25
# url = "https://localhost:8443/api/outbound-dialer/fullCampaignCreate"
# url = "https://contactdistributionmgmt-e2e.api.intuit.com/api/outbound-dialer/fullCampaignCreate"
url = "https://contactdistributionmgmt.api.intuit.com/api/outbound-dialer/fullCampaignCreateV2"


from datetime import datetime, timedelta, time
import pytz
import json
import requests
from requests_toolbelt.multipart.encoder import MultipartEncoder

# Define UTC and Pacific timezones with automatic DST adjustment
UTC = pytz.utc
PACIFIC = pytz.timezone("America/Los_Angeles")  # Automatically adjusts for DST

# Get current UTC date
current_utc_date = datetime.utcnow().date()

#######################################################################################################
# Get current time in PST
now_pst = datetime.now(PACIFIC)

# Define default campaign start time: 8:00 AM PST today
default_start_pst = PACIFIC.localize(datetime.combine(now_pst.date(), time(8,0)))

# If current PST time is on or after 8 AM, use current time + 30 minutes (15 min was too short on Mondays)
if now_pst >= default_start_pst:
    campaign_start_pst = now_pst + timedelta(minutes=30)
else:
    campaign_start_pst = default_start_pst

# Convert to UTC and remove tzinfo for JSON compatibility
campaign_start_utc = campaign_start_pst.astimezone(UTC)
campaign_start_naive = campaign_start_pst.replace(tzinfo=None)  # Optional: for consistency with other naive times
#######################################################################################################

# Format UTC & PST Start Date (REMOVING "UTC" suffix for API)
formatted_start_date_utc = campaign_start_utc.strftime("%Y-%m-%dT%H:%M:%S")
formatted_start_date_pst = campaign_start_pst.strftime("%Y-%m-%d %I:%M %p %Z")
start_day_of_week_pst = campaign_start_pst.strftime("%A")  # ✅ Get weekday in PST

# Determine campaign end time based on the day of the week
weekday = current_utc_date.weekday()  # 0 = Monday, 6 = Sunday

#######################################################################################################
if weekday == 6:
    # Do not run on Sunday
    campaign_end_naive = None
else:  # Monday to Saturday - 8:00 PM PST End
    campaign_end_naive = datetime.combine(current_utc_date, time(20, 0, 0))  # 8 PM PST (Same day) changed to 5pm apr 21

campaign_end_pst = PACIFIC.localize(campaign_end_naive)  # Localize to PST/PDT
campaign_end_utc = campaign_end_pst.astimezone(UTC)  # Convert to UTC
#######################################################################################################

# Format UTC & PST End Date (REMOVING "UTC" suffix for API)
formatted_end_date_utc = campaign_end_utc.strftime("%Y-%m-%dT%H:%M:%S")
formatted_end_date_pst = campaign_end_pst.strftime("%Y-%m-%d %I:%M %p %Z")
end_day_of_week_pst = campaign_end_pst.strftime("%A")  # ✅ Get weekday in PST

# Get the number of records in the dataframe
num_records = len(pd_df)

#######################################################################################################
# Set Outbound queue name
outbound_queue = "cg-us_ps_sentiment_campaign" #"cg_jshen2_test_322"
#######################################################################################################

# ✅ Print campaign start and end times in both UTC and PST
print(f"📞 Outbound Queue: {outbound_queue}")
print(f"📊 Number of records in the campaign: {num_records}")
print(f"📅 Campaign Start (UTC): {formatted_start_date_utc}")
print(f"📅 Campaign Start (PST): {formatted_start_date_pst} ({start_day_of_week_pst})")
print(f"📅 Campaign End (UTC): {formatted_end_date_utc}")
print(f"📅 Campaign End (PST): {formatted_end_date_pst} ({end_day_of_week_pst})")

# Specify the payload values (NO " UTC" SUFFIX)
payload = {
    'data': {
        "segment": "us",  # other options: "ap", "eu"
        "campaignStartDate": formatted_start_date_utc,  # ✅ Correct format
        "campaignEndDate": formatted_end_date_utc,  # ✅ Correct format 
        "dialerType": "Predictive",  # other options: "Agentless", "Predictive", "Progressive"
        "outboundQueue":  outbound_queue,  # "us_ps_fs_efile_reject_campaign queue", # "cg_jshen2_test_322" 
        "agentBandwidthAllocation": 92, #matt said set to 96 on feb 12 and 98 on feb 20 and 100 on 2/22 and 92 on 326
        "filters": [],
        "communicationTime": {  # the time when customer receives the call
            "timeZone": "recipient",
            "areaCodeEnabled": False,
            "postalCodeEnabled": True,
            "activeDays": [
                "Mon",
                "Tue",
                "Wed",
                "Thu",
                "Fri",
                "Sat"
            ],
            "startTime": "08:00 AM",
            "endTime": "08:00 PM"
        },
        "ivaDetails": {
            "enabled": True,
            "campaignName": "CSO-798 TY25 Mid Product Sentiment Outreach",
            "campaignGreeting": "We recently reached out to you about your survey response.",  # IVA Campaign greeting
            "ivrIntent": "Outreach Low Score",  # CUP intent
            "explanation": "We wanted to check in to see if we could answer any questions for you. ",
            "offerSelfHelp": False,
            "helpLink": "",
            "retentionDuration": 30  # fixed value
        }
    }
}


headers = {
    'Content-Type': 'multipart/form-data',
    'Accept': 'application/json',
    'Authorization': f'Intuit_IAM_Authentication intuit_token_type="IAM-Ticket",intuit_apkey_version="1.0",intuit_token="{intuit_token_ticket}",intuit_userid="{userid}",intuit_realmid="",intuit_appid={appid},intuit_app_secret={app_secret}'
}

# Convert the DataFrame to a CSV string
csv_string = pd_df.to_csv(index=False)

# Specify the file for upload using the CSV string directly as bytes
files = [
    ('file', (csv_string.encode(), 'text/csv'))
]

# Create a MultipartEncoder (including the JSON payload)
multipart_data = MultipartEncoder(
    fields={
        'data': json.dumps(payload['data']),
        'file': ('sample_upload.csv', csv_string.encode(), 'text/csv')
    }
)

# Update the headers with the correct Content-Type
headers['Content-Type'] = multipart_data.content_type  

# Call the API using the MultipartEncoder
response = requests.request("POST", url, headers=headers, data=multipart_data) 

# Print the response with a success message
if response.status_code == 200:
    print(f"✅ Success: Campaign successfully created with end time {formatted_end_date_utc} UTC ({end_day_of_week_pst} PST).")
    print(f"📊 Number of records processed: {num_records}")
else:
    print(f"❌ Error: {response.status_code}, {response.text}")
