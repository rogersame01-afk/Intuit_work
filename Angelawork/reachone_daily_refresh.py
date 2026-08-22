# Databricks notebook source

# COMMAND ----------

import os
from datetime import datetime

DBFS_OUTPUT_DIR = "/dbfs/FileStore/awatson4/dashboards"
DBFS_OUTPUT_FILE = f"{DBFS_OUTPUT_DIR}/reachone.html"

os.makedirs(DBFS_OUTPUT_DIR, exist_ok=True)
print(f"Output target: {DBFS_OUTPUT_FILE}")

# COMMAND ----------

# --- Query: Test group (email delivery) ---
test_df = spark.sql("""
SELECT b.canvas_name
    , b.dt AS date_qualified
    , b.canvas_step_name
    , b.test_group
    , COUNT(DISTINCT b.pseudonym_id) AS sends
    , COUNT(DISTINCT CASE WHEN l.auth_id IS NOT NULL THEN b.pseudonym_id END) AS reauths
    , COUNT(DISTINCT CASE WHEN pam.completed_flag = 1 THEN b.pseudonym_id END) AS completes
FROM (
  SELECT DISTINCT
    external_user_id AS pseudonym_id,
    DATE(from_utc_timestamp(CAST(em.time AS timestamp), 'America/Los_Angeles')) AS dt,
    canvas_name,
    canvas_step_name,
    'test' AS test_group
  FROM tax_src.src_braze_turbotax_email_delivery AS em
  WHERE em.year = 2026
    AND DATE(from_utc_timestamp(CAST(em.time AS timestamp), 'America/Los_Angeles')) >= '2026-03-12'
    AND em.canvas_step_name LIKE 'em_803_NULL_00%'
) b
LEFT JOIN (
    SELECT msam.auth_id, pam2.pseudonym_id, msam.server_timestamp AS session_start_datetime
    FROM tax_rpt.marketing_session_analytics_master AS msam
    INNER JOIN tax_rpt.product_analytics_master pam2
        ON msam.auth_id = pam2.auth_id AND pam2.tax_year = msam.tax_year
    WHERE msam.tax_year = 2025
        AND DATE(msam.server_timestamp) >= DATE('2026-03-12')
        AND msam.auth_id IS NOT NULL
) l ON b.pseudonym_id = l.pseudonym_id
    AND DATE(l.session_start_datetime) >= DATE('2026-03-12')
LEFT JOIN tax_rpt.product_analytics_master pam
    ON b.pseudonym_id = pam.pseudonym_id AND pam.tax_year = 2025
WHERE pam.first_completed_date IS NULL OR (pam.first_completed_date > l.session_start_datetime)
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4
""")

print(f"Test rows: {test_df.count()}")

# COMMAND ----------

# --- Query: Holdout group (webhook send) ---
holdout_df = spark.sql("""
SELECT b.canvas_name
    , b.dt AS date_qualified
    , b.canvas_step_name
    , b.test_group
    , COUNT(DISTINCT b.pseudonym_id) AS sends
    , COUNT(DISTINCT CASE WHEN l.auth_id IS NOT NULL THEN b.pseudonym_id END) AS reauths
    , COUNT(DISTINCT CASE WHEN pam.completed_flag = 1 THEN b.pseudonym_id END) AS completes
FROM (
  SELECT DISTINCT
    external_user_id AS pseudonym_id,
    DATE(from_utc_timestamp(CAST(time AS timestamp), 'America/Los_Angeles')) AS dt,
    canvas_name,
    canvas_step_name,
    'holdout' AS test_group
  FROM tax_src.src_braze_turbotax_webhook_send
  WHERE year = 2026
    AND DATE(from_utc_timestamp(CAST(time AS timestamp), 'America/Los_Angeles')) >= '2026-03-12'
    AND canvas_step_name LIKE 'em_803_NULL_00%'
) b
LEFT JOIN (
    SELECT msam.auth_id, pam2.pseudonym_id, msam.server_timestamp AS session_start_datetime
    FROM tax_rpt.marketing_session_analytics_master AS msam
    INNER JOIN tax_rpt.product_analytics_master pam2
        ON msam.auth_id = pam2.auth_id AND pam2.tax_year = msam.tax_year
    WHERE msam.tax_year = 2025
        AND DATE(msam.server_timestamp) >= DATE('2026-03-12')
        AND msam.auth_id IS NOT NULL
) l ON b.pseudonym_id = l.pseudonym_id
    AND DATE(l.session_start_datetime) >= DATE('2026-03-12')
LEFT JOIN tax_rpt.product_analytics_master pam
    ON b.pseudonym_id = pam.pseudonym_id AND pam.tax_year = 2025
WHERE pam.first_completed_date IS NULL OR (pam.first_completed_date > l.session_start_datetime)
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4
""")

print(f"Holdout rows: {holdout_df.count()}")

# COMMAND ----------

# --- Combine and transform ---
import json
from datetime import datetime

pdf_test = test_df.toPandas()
pdf_hold = holdout_df.toPandas()

import pandas as pd
df = pd.concat([pdf_test, pdf_hold], ignore_index=True)
df["date_qualified"] = pd.to_datetime(df["date_qualified"])
df["step_num"] = df["canvas_step_name"].str.split("_").str[3]

STEP_LABELS = {
    "001": "Dependent",
    "002": "State Residence",
    "003": "Std. vs. Itemized",
    "004": "1099",
    "005": "Refund Status",
}
df["step_label"] = df["step_num"].map(STEP_LABELS)

total_rows = len(df)
print(f"Combined: {total_rows} rows")
if total_rows == 0:
    raise ValueError("Query returned 0 rows — aborting")

# COMMAND ----------

# --- Build HTML dashboard ---

daily = df.groupby(["date_qualified", "test_group"]).agg(
    sends=("sends", "sum"), reauths=("reauths", "sum"), completes=("completes", "sum"),
).reset_index().sort_values(["date_qualified", "test_group"])
daily["reauth_rate"] = (daily["reauths"] / daily["sends"] * 100).round(1)
daily["s2c_rate"] = (daily["completes"] / daily["sends"] * 100).round(1)

def pivot_metric(d, metric):
    piv = d.pivot(index="date_qualified", columns="test_group", values=metric).reset_index()
    piv.columns.name = None
    return piv

piv = daily.pivot(index="date_qualified", columns="test_group",
                  values=["sends", "reauths", "reauth_rate", "completes", "s2c_rate"]).reset_index()
piv.columns = ["_".join(c).strip("_") for c in piv.columns]
piv["reauth_idx"] = (piv["reauth_rate_test"] / piv["reauth_rate_holdout"] * 100).round(1)
piv["s2c_idx"] = (piv["s2c_rate_test"] / piv["s2c_rate_holdout"] * 100).round(1)
piv["cum_sends_test"] = piv["sends_test"].cumsum()
piv["cum_sends_holdout"] = piv["sends_holdout"].cumsum()

step_agg = df.groupby(["step_label", "step_num", "test_group"]).agg(
    sends=("sends", "sum"), reauths=("reauths", "sum"), completes=("completes", "sum"),
).reset_index()
step_agg["reauth_rate"] = (step_agg["reauths"] / step_agg["sends"] * 100).round(1)
step_agg["s2c_rate"] = (step_agg["completes"] / step_agg["sends"] * 100).round(1)
step_agg = step_agg.sort_values("step_num")

step_daily = df.groupby(["date_qualified", "step_label", "step_num", "test_group"]).agg(
    sends=("sends", "sum"), reauths=("reauths", "sum"), completes=("completes", "sum"),
).reset_index()
step_daily["reauth_rate"] = (step_daily["reauths"] / step_daily["sends"] * 100).round(1)
step_daily["s2c_rate"] = (step_daily["completes"] / step_daily["sends"] * 100).round(1)

step_data_json = []
for _, row in step_daily.iterrows():
    step_data_json.append({
        "date": row["date_qualified"].strftime("%Y-%m-%d"),
        "step": row["step_num"],
        "label": row["step_label"],
        "group": row["test_group"],
        "sends": int(row["sends"]),
        "reauths": int(row["reauths"]),
        "reauth_rate": float(row["reauth_rate"]),
        "completes": int(row["completes"]),
        "s2c_rate": float(row["s2c_rate"]),
    })
for _, row in step_agg.iterrows():
    step_data_json.append({
        "date": "all",
        "step": row["step_num"],
        "label": row["step_label"],
        "group": row["test_group"],
        "sends": int(row["sends"]),
        "reauths": int(row["reauths"]),
        "reauth_rate": float(row["reauth_rate"]),
        "completes": int(row["completes"]),
        "s2c_rate": float(row["s2c_rate"]),
    })
step_dates = sorted(df["date_qualified"].dt.strftime("%Y-%m-%d").unique().tolist())

daily_by_step = df.groupby(["date_qualified", "step_num", "step_label", "test_group"]).agg(
    sends=("sends", "sum"), reauths=("reauths", "sum"), completes=("completes", "sum"),
).reset_index()

daily_data_json = []
for step_val in ["all"] + sorted(STEP_LABELS.keys()):
    if step_val == "all":
        sub = df.groupby(["date_qualified", "test_group"]).agg(
            sends=("sends", "sum"), reauths=("reauths", "sum"), completes=("completes", "sum"),
        ).reset_index()
    else:
        sub = daily_by_step[daily_by_step.step_num == step_val].copy()
    sub["reauth_rate"] = (sub["reauths"] / sub["sends"] * 100).round(1)
    sub["s2c_rate"] = (sub["completes"] / sub["sends"] * 100).round(1)
    sub_piv = sub.pivot(index="date_qualified", columns="test_group",
                        values=["sends", "reauths", "reauth_rate", "completes", "s2c_rate"]).reset_index()
    sub_piv.columns = ["_".join(c).strip("_") for c in sub_piv.columns]
    for col in ["sends_holdout","sends_test","reauths_holdout","reauths_test",
                "reauth_rate_holdout","reauth_rate_test","completes_holdout","completes_test",
                "s2c_rate_holdout","s2c_rate_test"]:
        if col not in sub_piv.columns:
            sub_piv[col] = 0
    sub_piv["reauth_idx"] = (sub_piv["reauth_rate_test"] / sub_piv["reauth_rate_holdout"].replace(0, float('nan')) * 100).round(1)
    sub_piv["s2c_idx"] = (sub_piv["s2c_rate_test"] / sub_piv["s2c_rate_holdout"].replace(0, float('nan')) * 100).round(1)
    sub_piv["cum_sends_test"] = sub_piv["sends_test"].cumsum()
    sub_piv["cum_sends_holdout"] = sub_piv["sends_holdout"].cumsum()
    sub_piv = sub_piv.sort_values("date_qualified")
    for _, row in sub_piv.iterrows():
        daily_data_json.append({
            "step": step_val,
            "date": row["date_qualified"].strftime("%Y-%m-%d"),
            "date_fmt": row["date_qualified"].strftime("%m/%d"),
            "sends_h": int(row["sends_holdout"]) if pd.notna(row["sends_holdout"]) else 0,
            "sends_t": int(row["sends_test"]) if pd.notna(row["sends_test"]) else 0,
            "cum_h": int(row["cum_sends_holdout"]),
            "cum_t": int(row["cum_sends_test"]),
            "rr_h": float(row["reauth_rate_holdout"]) if pd.notna(row["reauth_rate_holdout"]) else 0,
            "rr_t": float(row["reauth_rate_test"]) if pd.notna(row["reauth_rate_test"]) else 0,
            "ri": float(row["reauth_idx"]) if pd.notna(row["reauth_idx"]) else None,
            "sc_h": float(row["s2c_rate_holdout"]) if pd.notna(row["s2c_rate_holdout"]) else 0,
            "sc_t": float(row["s2c_rate_test"]) if pd.notna(row["s2c_rate_test"]) else 0,
            "si": float(row["s2c_idx"]) if pd.notna(row["s2c_idx"]) else None,
        })

totals = df.groupby("test_group").agg(
    sends=("sends", "sum"), reauths=("reauths", "sum"), completes=("completes", "sum")
).reset_index()
totals["reauth_rate"] = (totals["reauths"] / totals["sends"] * 100).round(1)
totals["s2c_rate"] = (totals["completes"] / totals["sends"] * 100).round(1)

t_tot = totals[totals.test_group == "test"].iloc[0]
h_tot = totals[totals.test_group == "holdout"].iloc[0]
dates = piv["date_qualified"]
refresh_ts = datetime.now().strftime("%b %d, %Y %I:%M %p PT")

def idx_class(v):
    if v > 100: return "up"
    if v < 100: return "down"
    return "flat"

def safe_int(v):
    return f"{int(v):,}" if pd.notna(v) else "\u2014"

def safe_pct(v):
    return f"{v:.1f}%" if pd.notna(v) else "\u2014"

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>TY25 Operation ReachOne</title>
<style>
  :root {{ --blue: #0066ff; --orange: #e8590c; --green: #2b8a3e; --red: #c92a2a; --gray: #868e96; --bg: #f8f9fa; }}
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: var(--bg); color: #212529; padding: 28px; max-width: 1200px; margin: 0 auto; }}
  h1 {{ font-size: 24px; font-weight: 700; }}
  .sub {{ font-size: 13px; color: var(--gray); margin-bottom: 28px; }}
  .kpi-row {{ display: grid; grid-template-columns: repeat(6, 1fr); gap: 12px; margin-bottom: 32px; }}
  .kpi {{ background: #fff; border-radius: 10px; padding: 16px 12px; box-shadow: 0 1px 3px rgba(0,0,0,.06); text-align: center; }}
  .kpi .lbl {{ font-size: 10px; text-transform: uppercase; letter-spacing: .5px; color: var(--gray); margin-bottom: 5px; }}
  .kpi .val {{ font-size: 24px; font-weight: 700; }}
  .kpi .note {{ font-size: 11px; color: var(--gray); margin-top: 3px; }}
  .blue {{ color: var(--blue); }}
  .org {{ color: var(--orange); }}
  .section {{ background: #fff; border-radius: 10px; padding: 20px; box-shadow: 0 1px 3px rgba(0,0,0,.06); margin-bottom: 24px; }}
  .section h2 {{ font-size: 15px; font-weight: 600; margin-bottom: 14px; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 12.5px; }}
  th {{ background: #f1f3f5; padding: 8px 10px; text-align: right; font-weight: 600; border-bottom: 2px solid #dee2e6; white-space: nowrap; }}
  th:first-child {{ text-align: left; }}
  td {{ padding: 7px 10px; border-bottom: 1px solid #f1f3f5; text-align: right; font-variant-numeric: tabular-nums; }}
  td:first-child {{ text-align: left; font-weight: 500; }}
  .up {{ color: var(--green); font-weight: 700; }}
  .down {{ color: var(--red); font-weight: 700; }}
  .flat {{ color: var(--gray); font-weight: 700; }}
  .step-row td {{ background: #fff; }}
  .idx-row td {{ background: #f0f4ff; font-weight: 600; font-style: italic; }}
  .col-test {{ color: var(--blue); }}
  .col-hold {{ color: var(--orange); }}
  @media (max-width: 700px) {{ .kpi-row {{ grid-template-columns: repeat(3, 1fr); }} }}
  @media (max-width: 450px) {{ .kpi-row {{ grid-template-columns: repeat(2, 1fr); }} }}
</style>
</head>
<body>
<h1>TY25 Operation ReachOne</h1>
<div class="sub">803_CSO_TY25-ReachOne-Email-Outreach &bull; {dates.iloc[0].strftime('%Y-%m-%d')} &ndash; {dates.iloc[-1].strftime('%Y-%m-%d')} &bull; Refreshed {refresh_ts}</div>

<div class="kpi-row">
  <div class="kpi"><div class="lbl">Holdout Sends</div><div class="val org">{int(h_tot.sends):,}</div></div>
  <div class="kpi"><div class="lbl">Test Sends</div><div class="val blue">{int(t_tot.sends):,}</div></div>
  <div class="kpi"><div class="lbl">Holdout Reauth</div><div class="val org">{h_tot.reauth_rate:.1f}%</div></div>
  <div class="kpi"><div class="lbl">Test Reauth</div><div class="val blue">{t_tot.reauth_rate:.1f}%</div>
    <div class="note">Index vs. Holdout: {t_tot.reauth_rate / h_tot.reauth_rate * 100:.1f}</div></div>
  <div class="kpi"><div class="lbl">Holdout S2C</div><div class="val org">{h_tot.s2c_rate:.1f}%</div></div>
  <div class="kpi"><div class="lbl">Test S2C</div><div class="val blue">{t_tot.s2c_rate:.1f}%</div>
    <div class="note">Index vs. Holdout: {t_tot.s2c_rate / h_tot.s2c_rate * 100:.1f}</div></div>
</div>

<div class="section">
  <h2 style="display:inline-block;">Daily Volume, Reauth Rate &amp; S2C</h2>
  <select id="dailyStepFilter" onchange="filterDailyTable()" style="margin-left:12px;padding:5px 10px;border-radius:6px;border:1px solid #dee2e6;font-size:13px;vertical-align:middle;">
    <option value="all" selected>All Steps</option>
"""

for step_key in sorted(STEP_LABELS.keys()):
    html += f'    <option value="{step_key}">{STEP_LABELS[step_key]}</option>\n'

html += f"""  </select>
  <div style="overflow-x:auto;">
  <table>
    <thead>
      <tr>
        <th>Date</th>
        <th class="col-hold">Holdout Sends</th><th class="col-test">Test Sends</th>
        <th class="col-hold">Cum Holdout</th><th class="col-test">Cum Test</th>
        <th class="col-hold">Hold Reauth</th><th class="col-test">Test Reauth</th><th>Idx vs. Holdout</th>
        <th class="col-hold">Hold S2C</th><th class="col-test">Test S2C</th><th>Idx vs. Holdout</th>
      </tr>
    </thead>
    <tbody id="dailyTableBody">
    </tbody>
  </table>
  </div>
</div>

<div class="section">
  <h2 style="display:inline-block;">Results by Canvas Step</h2>
  <select id="stepDateFilter" onchange="filterStepTable()" style="margin-left:12px;padding:5px 10px;border-radius:6px;border:1px solid #dee2e6;font-size:13px;vertical-align:middle;">
    <option value="all" selected>All Dates (Cumulative)</option>
"""

for d in step_dates:
    dt_obj = datetime.strptime(d, "%Y-%m-%d")
    html += f'    <option value="{d}">{dt_obj.strftime("%m/%d/%Y")}</option>\n'

html += f"""  </select>
  <table>
    <thead>
      <tr><th>Canvas Step</th><th>Group</th><th>Sends</th><th>Reauths</th><th>Reauth Rate</th><th>Completes</th><th>S2C</th></tr>
    </thead>
    <tbody id="stepTableBody">
    </tbody>
  </table>
</div>

<script>
var DAILY_DATA = {json.dumps(daily_data_json)};
var STEP_DATA = {json.dumps(step_data_json)};
var STEPS = {json.dumps(sorted(STEP_LABELS.keys()))};
var STEP_LABELS_MAP = {json.dumps(STEP_LABELS)};

function idxClass(v) {{ if (v > 100) return "up"; if (v < 100) return "down"; return "flat"; }}
function fmtInt(v) {{ return v.toLocaleString(); }}
function fmtPct(v) {{ return v.toFixed(1) + "%"; }}

function filterDailyTable() {{
  var sel = document.getElementById("dailyStepFilter").value;
  var filtered = DAILY_DATA.filter(function(r) {{ return r.step === sel; }});
  var tbody = document.getElementById("dailyTableBody");
  var rows = "";

  filtered.forEach(function(r) {{
    var rc = r.ri !== null ? idxClass(r.ri) : "flat";
    var sc = r.si !== null ? idxClass(r.si) : "flat";
    var ri_str = r.ri !== null ? r.ri.toFixed(1) : "\\u2014";
    var si_str = r.si !== null ? r.si.toFixed(1) : "\\u2014";
    rows += '<tr>';
    rows += '<td>' + r.date_fmt + '</td>';
    rows += '<td>' + fmtInt(r.sends_h) + '</td><td>' + fmtInt(r.sends_t) + '</td>';
    rows += '<td>' + fmtInt(r.cum_h) + '</td><td>' + fmtInt(r.cum_t) + '</td>';
    rows += '<td>' + fmtPct(r.rr_h) + '</td><td>' + fmtPct(r.rr_t) + '</td><td class="' + rc + '">' + ri_str + '</td>';
    rows += '<td>' + fmtPct(r.sc_h) + '</td><td>' + fmtPct(r.sc_t) + '</td><td class="' + sc + '">' + si_str + '</td>';
    rows += '</tr>';
  }});

  tbody.innerHTML = rows;
}}

function filterStepTable() {{
  var sel = document.getElementById("stepDateFilter").value;
  var filtered = STEP_DATA.filter(function(r) {{ return r.date === sel; }});
  var tbody = document.getElementById("stepTableBody");
  var rows = "";

  STEPS.forEach(function(step) {{
    var t = filtered.find(function(r) {{ return r.step === step && r.group === "test"; }});
    var h = filtered.find(function(r) {{ return r.step === step && r.group === "holdout"; }});
    if (!t || !h) return;

    var ri = h.reauth_rate > 0 ? Math.round(t.reauth_rate / h.reauth_rate * 1000) / 10 : null;
    var si = h.s2c_rate > 0 ? Math.round(t.s2c_rate / h.s2c_rate * 1000) / 10 : null;
    var rc = ri !== null ? idxClass(ri) : "flat";
    var sc = si !== null ? idxClass(si) : "flat";

    rows += '<tr class="step-row"><td rowspan="3"><strong>' + STEP_LABELS_MAP[step] + '</strong></td>';
    rows += '<td class="col-hold">Holdout</td><td>' + fmtInt(h.sends) + '</td><td>' + fmtInt(h.reauths) + '</td><td>' + fmtPct(h.reauth_rate) + '</td><td>' + fmtInt(h.completes) + '</td><td>' + fmtPct(h.s2c_rate) + '</td></tr>';
    rows += '<tr class="step-row"><td class="col-test">Test</td><td>' + fmtInt(t.sends) + '</td><td>' + fmtInt(t.reauths) + '</td><td>' + fmtPct(t.reauth_rate) + '</td><td>' + fmtInt(t.completes) + '</td><td>' + fmtPct(t.s2c_rate) + '</td></tr>';
    rows += '<tr class="idx-row"><td>Idx vs. Holdout</td><td></td><td></td><td class="' + rc + '">' + (ri !== null ? ri.toFixed(1) : "\\u2014") + '</td><td></td><td class="' + sc + '">' + (si !== null ? si.toFixed(1) : "\\u2014") + '</td></tr>';
  }});

  tbody.innerHTML = rows;
}}

filterDailyTable();
filterStepTable();
</script>

</body>
</html>
"""

print(f"HTML generated: {len(html):,} chars")

# COMMAND ----------

# --- Write HTML to DBFS ---
with open(DBFS_OUTPUT_FILE, "w", encoding="utf-8") as f:
    f.write(html)

print(f"Saved to {DBFS_OUTPUT_FILE} ({len(html):,} chars)")

# COMMAND ----------

# --- Push HTML to GitHub Pages via REST API ---
import requests, base64

IS_DATABRICKS = "DATABRICKS_RUNTIME_VERSION" in os.environ

GITHUB_TOKEN = os.environ.get("github_token", "") or os.environ.get("GITHUB_TOKEN", "")
if not GITHUB_TOKEN and IS_DATABRICKS:
    dbutils.widgets.text("github_token", "")
    GITHUB_TOKEN = dbutils.widgets.get("github_token")
if not GITHUB_TOKEN:
    raise RuntimeError(
        "github_token not set — add it as a SuperGlue pipeline parameter or paste into the widget"
    )

GH_API = "https://github.intuit.com/api/v3"
REPO = "awatson4/nlac"
FILE_PATH = "docs/reachone.html"
BRANCH = "master"
headers = {"Authorization": f"token {GITHUB_TOKEN}", "Accept": "application/vnd.github.v3+json"}

get_resp = requests.get(f"{GH_API}/repos/{REPO}/contents/{FILE_PATH}?ref={BRANCH}", headers=headers)
sha = get_resp.json().get("sha") if get_resp.status_code == 200 else None

payload = {
    "message": f"Daily refresh: {refresh_ts}",
    "content": base64.b64encode(html.encode("utf-8")).decode("ascii"),
    "branch": BRANCH,
}
if sha:
    payload["sha"] = sha

put_resp = requests.put(f"{GH_API}/repos/{REPO}/contents/{FILE_PATH}", headers=headers, json=payload)

if put_resp.status_code in (200, 201):
    print(f"Pushed to GitHub Pages: https://github.intuit.com/pages/{REPO}/reachone.html")
else:
    print(f"GitHub push failed ({put_resp.status_code}): {put_resp.text}")
    raise RuntimeError(f"GitHub API returned {put_resp.status_code}")
