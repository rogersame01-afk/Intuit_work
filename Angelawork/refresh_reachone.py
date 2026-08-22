#!/usr/bin/env python3
"""Refresh ReachOne dashboard HTML using pydatalake, now with MAM revenue."""

import json
import subprocess
import sys
from datetime import datetime

import pandas as pd

def run_query(sql):
    result = subprocess.run(
        ["pydatalake", "query", sql, "--backend", "sqlwarehouse", "--limit", "0",
         "--format", "parquet", "-o", "/tmp/reachone_tmp.parquet", "--no-cache"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"Query failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return pd.read_parquet("/tmp/reachone_tmp.parquet")


TEST_SQL = """
SELECT b.canvas_name
    , b.dt AS date_qualified
    , b.canvas_step_name
    , b.test_group
    , COUNT(DISTINCT b.pseudonym_id) AS sends
    , COUNT(DISTINCT CASE WHEN l.auth_id IS NOT NULL THEN b.pseudonym_id END) AS reauths
    , COUNT(DISTINCT CASE WHEN pam.completed_flag = 1 THEN b.pseudonym_id END) AS completes
    , COALESCE(SUM(CASE WHEN pam.completed_flag = 1 THEN mam.total_revenue END), 0) AS revenue
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
LEFT JOIN tax_rpt.monetization_analytics_master mam
    ON pam.auth_id = mam.auth_id AND mam.tax_year = 2025
WHERE pam.first_completed_date IS NULL OR (pam.first_completed_date > l.session_start_datetime)
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4
"""

HOLDOUT_SQL = """
SELECT b.canvas_name
    , b.dt AS date_qualified
    , b.canvas_step_name
    , b.test_group
    , COUNT(DISTINCT b.pseudonym_id) AS sends
    , COUNT(DISTINCT CASE WHEN l.auth_id IS NOT NULL THEN b.pseudonym_id END) AS reauths
    , COUNT(DISTINCT CASE WHEN pam.completed_flag = 1 THEN b.pseudonym_id END) AS completes
    , COALESCE(SUM(CASE WHEN pam.completed_flag = 1 THEN mam.total_revenue END), 0) AS revenue
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
LEFT JOIN tax_rpt.monetization_analytics_master mam
    ON pam.auth_id = mam.auth_id AND mam.tax_year = 2025
WHERE pam.first_completed_date IS NULL OR (pam.first_completed_date > l.session_start_datetime)
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4
"""

ARPC_SQL = """
WITH users AS (
  SELECT DISTINCT external_user_id AS pseudonym_id, 'test' AS test_group
  FROM tax_src.src_braze_turbotax_email_delivery AS em
  WHERE em.year = 2026
    AND DATE(from_utc_timestamp(CAST(em.time AS timestamp), 'America/Los_Angeles')) >= '2026-03-12'
    AND em.canvas_step_name LIKE 'em_803_NULL_00%%'

  UNION ALL

  SELECT DISTINCT external_user_id, 'holdout'
  FROM tax_src.src_braze_turbotax_webhook_send
  WHERE year = 2026
    AND DATE(from_utc_timestamp(CAST(time AS timestamp), 'America/Los_Angeles')) >= '2026-03-12'
    AND canvas_step_name LIKE 'em_803_NULL_00%%'
),
user_outcomes AS (
  SELECT u.pseudonym_id
    , u.test_group
    , MAX(pam.completed_flag) AS completed_flag
    , MAX(mam.total_revenue) AS total_revenue
  FROM users u
  LEFT JOIN tax_rpt.product_analytics_master pam
      ON u.pseudonym_id = pam.pseudonym_id AND pam.tax_year = 2025
  LEFT JOIN tax_rpt.monetization_analytics_master mam
      ON pam.auth_id = mam.auth_id AND mam.tax_year = 2025
  GROUP BY u.pseudonym_id, u.test_group
)
SELECT test_group
  , COUNT(CASE WHEN completed_flag = 1 THEN 1 END) AS completes
  , COALESCE(SUM(CASE WHEN completed_flag = 1 THEN total_revenue END), 0) AS revenue
FROM user_outcomes
GROUP BY test_group
"""

STEP_LABELS = {
    "001": "Dependent",
    "002": "State Residence",
    "003": "Std. vs. Itemized",
    "004": "1099",
    "005": "Refund Status",
}

def nan_to_null(v):
    if pd.isna(v):
        return None
    f = float(v)
    if f == float('inf') or f == float('-inf'):
        return None
    return round(f, 1)

def main():
    print("Querying test group...")
    pdf_test = run_query(TEST_SQL)
    print(f"  Test rows: {len(pdf_test)}")

    print("Querying holdout group...")
    pdf_hold = run_query(HOLDOUT_SQL)
    print(f"  Holdout rows: {len(pdf_hold)}")

    print("Querying deduplicated ARPC...")
    pdf_arpc = run_query(ARPC_SQL)
    for c in ["completes", "revenue"]:
        pdf_arpc[c] = pd.to_numeric(pdf_arpc[c], errors="coerce").fillna(0)
    arpc_test_row = pdf_arpc[pdf_arpc.test_group == "test"].iloc[0]
    arpc_hold_row = pdf_arpc[pdf_arpc.test_group == "holdout"].iloc[0]
    dedup_arpc_test = float(arpc_test_row.revenue) / float(arpc_test_row.completes) if float(arpc_test_row.completes) > 0 else 0
    dedup_arpc_hold = float(arpc_hold_row.revenue) / float(arpc_hold_row.completes) if float(arpc_hold_row.completes) > 0 else 0
    print(f"  Test ARPC (deduped): ${dedup_arpc_test:,.2f}  Holdout ARPC: ${dedup_arpc_hold:,.2f}")

    df = pd.concat([pdf_test, pdf_hold], ignore_index=True)
    df["date_qualified"] = pd.to_datetime(df["date_qualified"])
    for num_col in ["sends", "reauths", "completes", "revenue"]:
        df[num_col] = pd.to_numeric(df[num_col], errors="coerce").fillna(0)
    df["step_num"] = df["canvas_step_name"].str.split("_").str[3]
    df["step_label"] = df["step_num"].map(STEP_LABELS)

    if len(df) == 0:
        print("ERROR: Query returned 0 rows", file=sys.stderr)
        sys.exit(1)
    print(f"Combined: {len(df)} rows")

    # --- Daily data (for each step + "all") ---
    daily_rows = []
    for step_filter in ["all"] + list(STEP_LABELS.keys()):
        sub = df.copy() if step_filter == "all" else df[df.step_num == step_filter].copy()

        daily = sub.groupby(["date_qualified", "test_group"]).agg(
            sends=("sends", "sum"), reauths=("reauths", "sum"),
            completes=("completes", "sum"), revenue=("revenue", "sum"),
        ).reset_index().sort_values(["date_qualified", "test_group"])
        daily["reauth_rate"] = (daily["reauths"] / daily["sends"] * 100).round(1)
        daily["s2c_rate"] = (daily["completes"] / daily["sends"] * 100).round(1)

        piv = daily.pivot(index="date_qualified", columns="test_group",
                          values=["sends", "reauths", "reauth_rate", "completes", "s2c_rate", "revenue"]).reset_index()
        piv.columns = ["_".join(c).strip("_") for c in piv.columns]

        for col in ["sends_test", "sends_holdout", "reauths_test", "reauths_holdout",
                     "reauth_rate_test", "reauth_rate_holdout", "completes_test",
                     "completes_holdout", "s2c_rate_test", "s2c_rate_holdout",
                     "revenue_test", "revenue_holdout"]:
            if col not in piv.columns:
                piv[col] = 0
            piv[col] = pd.to_numeric(piv[col], errors="coerce").fillna(0)

        piv["reauth_idx"] = (piv["reauth_rate_test"] / piv["reauth_rate_holdout"].replace(0, float('nan')) * 100).round(1)
        piv["s2c_idx"] = (piv["s2c_rate_test"] / piv["s2c_rate_holdout"].replace(0, float('nan')) * 100).round(1)
        piv["cum_sends_test"] = piv["sends_test"].fillna(0).cumsum().astype(int)
        piv["cum_sends_holdout"] = piv["sends_holdout"].fillna(0).cumsum().astype(int)

        for _, r in piv.iterrows():
            daily_rows.append({
                "step": step_filter,
                "date": r["date_qualified"].strftime("%Y-%m-%d"),
                "date_fmt": r["date_qualified"].strftime("%m/%d"),
                "sends_h": int(r.get("sends_holdout", 0) if pd.notna(r.get("sends_holdout", 0)) else 0),
                "sends_t": int(r.get("sends_test", 0) if pd.notna(r.get("sends_test", 0)) else 0),
                "cum_h": int(r["cum_sends_holdout"]),
                "cum_t": int(r["cum_sends_test"]),
                "rr_h": nan_to_null(r.get("reauth_rate_holdout", 0)),
                "rr_t": nan_to_null(r.get("reauth_rate_test", 0)),
                "ri": nan_to_null(r["reauth_idx"]),
                "sc_h": nan_to_null(r.get("s2c_rate_holdout", 0)),
                "sc_t": nan_to_null(r.get("s2c_rate_test", 0)),
                "si": nan_to_null(r["s2c_idx"]),
                "rev_h": round(float(r.get("revenue_holdout", 0) or 0), 2),
                "rev_t": round(float(r.get("revenue_test", 0) or 0), 2),
            })

    # --- Step-level data ---
    step_rows = []
    for date_filter in list(df["date_qualified"].dt.strftime("%Y-%m-%d").unique()) + ["all"]:
        sub = df.copy() if date_filter == "all" else df[df.date_qualified == date_filter].copy()

        step_agg = sub.groupby(["step_label", "step_num", "test_group"]).agg(
            sends=("sends", "sum"), reauths=("reauths", "sum"),
            completes=("completes", "sum"), revenue=("revenue", "sum"),
        ).reset_index()
        step_agg["reauth_rate"] = (step_agg["reauths"] / step_agg["sends"] * 100).round(1)
        step_agg["s2c_rate"] = (step_agg["completes"] / step_agg["sends"] * 100).round(1)

        for _, r in step_agg.iterrows():
            step_rows.append({
                "date": date_filter,
                "step": r["step_num"],
                "label": r["step_label"],
                "group": r["test_group"],
                "sends": int(r["sends"]),
                "reauths": int(r["reauths"]),
                "reauth_rate": round(float(r["reauth_rate"]), 1),
                "completes": int(r["completes"]),
                "s2c_rate": round(float(r["s2c_rate"]), 1),
                "revenue": round(float(r["revenue"]), 2),
            })

    # --- Period data (pre/post May 8 content change) ---
    CONTENT_CHANGE_DATE = pd.Timestamp("2026-05-08")
    period_rows = []
    for period_key in ["pre_0508", "post_0508", "all"]:
        if period_key == "pre_0508":
            sub = df[df.date_qualified < CONTENT_CHANGE_DATE].copy()
        elif period_key == "post_0508":
            sub = df[df.date_qualified >= CONTENT_CHANGE_DATE].copy()
        else:
            sub = df.copy()

        period_agg = sub.groupby(["step_label", "step_num", "test_group"]).agg(
            sends=("sends", "sum"), reauths=("reauths", "sum"),
            completes=("completes", "sum"), revenue=("revenue", "sum"),
        ).reset_index()
        period_agg["reauth_rate"] = (period_agg["reauths"] / period_agg["sends"] * 100).round(1)
        period_agg["s2c_rate"] = (period_agg["completes"] / period_agg["sends"] * 100).round(1)

        for _, r in period_agg.iterrows():
            period_rows.append({
                "period": period_key,
                "step": r["step_num"],
                "label": r["step_label"],
                "group": r["test_group"],
                "sends": int(r["sends"]),
                "reauths": int(r["reauths"]),
                "reauth_rate": round(float(r["reauth_rate"]), 1),
                "completes": int(r["completes"]),
                "s2c_rate": round(float(r["s2c_rate"]), 1),
                "revenue": round(float(r["revenue"]), 2),
            })

    # --- KPI totals ---
    totals = df.groupby("test_group").agg(
        sends=("sends", "sum"), reauths=("reauths", "sum"),
        completes=("completes", "sum"), revenue=("revenue", "sum")
    ).reset_index()
    totals["reauth_rate"] = (totals["reauths"] / totals["sends"] * 100).round(1)
    totals["s2c_rate"] = (totals["completes"] / totals["sends"] * 100).round(1)
    totals["rps"] = (totals["revenue"] / totals["sends"]).round(2)

    t_tot = totals[totals.test_group == "test"].iloc[0]
    h_tot = totals[totals.test_group == "holdout"].iloc[0]

    # --- Identify steps that drove positive incremental revenue ---
    step_totals = df.groupby(["step_num", "step_label", "test_group"]).agg(
        sends=("sends", "sum"), reauths=("reauths", "sum"),
        completes=("completes", "sum"), revenue=("revenue", "sum")
    ).reset_index()
    step_totals["s2c_rate"] = (step_totals["completes"] / step_totals["sends"] * 100).round(1)

    winner_steps = []
    for step_num in sorted(STEP_LABELS.keys()):
        t_step = step_totals[(step_totals.step_num == step_num) & (step_totals.test_group == "test")]
        h_step = step_totals[(step_totals.step_num == step_num) & (step_totals.test_group == "holdout")]
        if len(t_step) == 0 or len(h_step) == 0:
            continue
        t_s2c_step = float(t_step.iloc[0].s2c_rate)
        h_s2c_step = float(h_step.iloc[0].s2c_rate)
        incr = (t_s2c_step / 100 - h_s2c_step / 100) * float(t_step.iloc[0].sends) * dedup_arpc_test
        if incr > 0:
            winner_steps.append(step_num)
    print(f"  Winner steps (incr rev > 0): {[STEP_LABELS[s] for s in winner_steps]}")

    winner_df = df[df.step_num.isin(winner_steps)]
    w_totals = winner_df.groupby("test_group").agg(
        sends=("sends", "sum"), reauths=("reauths", "sum"),
        completes=("completes", "sum"), revenue=("revenue", "sum")
    ).reset_index()
    w_totals["reauth_rate"] = (w_totals["reauths"] / w_totals["sends"] * 100).round(1)
    w_totals["s2c_rate"] = (w_totals["completes"] / w_totals["sends"] * 100).round(1)

    wt = w_totals[w_totals.test_group == "test"].iloc[0]
    wh = w_totals[w_totals.test_group == "holdout"].iloc[0]
    w_reauth_idx = round(float(wt.reauth_rate) / float(wh.reauth_rate) * 100, 1) if float(wh.reauth_rate) > 0 else 0
    w_s2c_idx = round(float(wt.s2c_rate) / float(wh.s2c_rate) * 100, 1) if float(wh.s2c_rate) > 0 else 0
    w_incr_rev = (float(wt.s2c_rate) / 100 - float(wh.s2c_rate) / 100) * float(wt.sends) * dedup_arpc_test
    w_incr_per_send = w_incr_rev / float(wt.sends) if float(wt.sends) > 0 else 0

    winner_labels_str = ", ".join(STEP_LABELS[s] for s in winner_steps)

    dates = sorted(df["date_qualified"].unique())
    date_min = pd.Timestamp(dates[0]).strftime("%Y-%m-%d")
    date_max = pd.Timestamp(dates[-1]).strftime("%Y-%m-%d")
    refresh_ts = datetime.now().strftime("%b %d, %Y %I:%M %p PT")

    unique_dates = sorted(df["date_qualified"].dt.strftime("%Y-%m-%d").unique())
    date_options_html = '<option value="all" selected>All Dates (Cumulative)</option>'
    for d in unique_dates:
        dt = pd.Timestamp(d)
        date_options_html += f'\n    <option value="{d}">{dt.strftime("%m/%d/%Y")}</option>'

    step_options_html = '<option value="all" selected>All Steps</option>'
    for k in sorted(STEP_LABELS.keys()):
        step_options_html += f'<option value="{k}">{STEP_LABELS[k]}</option>'

    daily_json = json.dumps(daily_rows, separators=(',', ': '))
    step_json = json.dumps(step_rows, separators=(',', ': '))
    period_json = json.dumps(period_rows, separators=(',', ': '))
    steps_json = json.dumps(sorted(STEP_LABELS.keys()))
    labels_json = json.dumps(STEP_LABELS)

    reauth_idx_total = round(float(t_tot.reauth_rate) / float(h_tot.reauth_rate) * 100, 1)
    s2c_idx_total = round(float(t_tot.s2c_rate) / float(h_tot.s2c_rate) * 100, 1)

    t_s2c = float(t_tot.s2c_rate) / 100
    h_s2c = float(h_tot.s2c_rate) / 100
    t_sends = float(t_tot.sends)
    t_arpc = dedup_arpc_test
    incr_rev = (t_s2c - h_s2c) * t_sends * t_arpc
    incr_per_send = incr_rev / t_sends if t_sends > 0 else 0
    incr_sign = "+" if incr_rev >= 0 else ""
    ps_sign = "+" if incr_per_send >= 0 else ""
    incr_class = "green" if incr_rev >= 0 else "red"

    w_incr_sign = "+" if w_incr_rev >= 0 else ""
    w_ps_sign = "+" if w_incr_per_send >= 0 else ""
    w_incr_class = "green" if w_incr_rev >= 0 else "red"

    html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>TY25 Operation ReachOne</title>
<style>
  :root {{ --blue:#0066ff;--orange:#e8590c;--green:#2b8a3e;--red:#c92a2a;--gray:#868e96;--bg:#f8f9fa;--teal:#0ca678; }}
  * {{ margin:0;padding:0;box-sizing:border-box; }}
  body {{ font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:#212529;padding:28px;max-width:1200px;margin:0 auto; }}
  h1 {{ font-size:24px;font-weight:700; }}
  .sub {{ font-size:13px;color:var(--gray);margin-bottom:28px; }}
  .kpi-row {{ display:grid;grid-template-columns:repeat(auto-fit, minmax(150px, 1fr));gap:12px;margin-bottom:16px; }}
  .kpi {{ background:#fff;border-radius:10px;padding:16px 12px;box-shadow:0 1px 3px rgba(0,0,0,.06);text-align:center; }}
  .kpi .lbl {{ font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:var(--gray);margin-bottom:5px; }}
  .kpi .val {{ font-size:24px;font-weight:700; }}
  .kpi .note {{ font-size:11px;color:var(--gray);margin-top:3px; }}
  .blue {{ color:var(--blue); }} .org {{ color:var(--orange); }} .green {{ color:var(--green); }} .red {{ color:var(--red); }}
  .section-label {{ font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:1px;color:var(--gray);margin-bottom:8px; }}
  .winner-row .kpi {{ border-left:3px solid var(--teal); }}
  .spacer {{ margin-bottom:32px; }}
  .section {{ background:#fff;border-radius:10px;padding:20px;box-shadow:0 1px 3px rgba(0,0,0,.06);margin-bottom:24px; }}
  .section h2 {{ font-size:15px;font-weight:600;margin-bottom:14px; }}
  table {{ width:100%;border-collapse:collapse;font-size:12.5px; }}
  th {{ background:#f1f3f5;padding:8px 10px;text-align:right;font-weight:600;border-bottom:2px solid #dee2e6;white-space:nowrap; }}
  th:first-child {{ text-align:left; }}
  td {{ padding:7px 10px;border-bottom:1px solid #f1f3f5;text-align:right;font-variant-numeric:tabular-nums; }}
  td:first-child {{ text-align:left;font-weight:500; }}
  .up {{ color:var(--green);font-weight:700; }} .down {{ color:var(--red);font-weight:700; }} .flat {{ color:var(--gray);font-weight:700; }}
  .step-row td {{ background:#fff; }} .idx-row td {{ background:#f0f4ff;font-weight:600;font-style:italic; }}
  .col-test {{ color:var(--blue); }} .col-hold {{ color:var(--orange); }}
  .period-header {{ background:#e9ecef;padding:10px;font-weight:700;font-size:13px;border-bottom:2px solid #dee2e6; }}
  @media (max-width:700px) {{ .kpi-row {{ grid-template-columns:repeat(3,1fr); }} }}
  @media (max-width:450px) {{ .kpi-row {{ grid-template-columns:repeat(2,1fr); }} }}
</style></head><body>
<h1>TY25 Operation ReachOne</h1>
<div class="sub">803_CSO_TY25-ReachOne-Email-Outreach &bull; {date_min} &ndash; {date_max} &bull; Refreshed {refresh_ts}</div>

<div class="section-label">All Steps</div>
<div class="kpi-row">
  <div class="kpi"><div class="lbl">Holdout Sends</div><div class="val org">{int(h_tot.sends):,}</div></div>
  <div class="kpi"><div class="lbl">Test Sends</div><div class="val blue">{int(t_tot.sends):,}</div></div>
  <div class="kpi"><div class="lbl">Holdout Reauth</div><div class="val org">{h_tot.reauth_rate:.1f}%</div></div>
  <div class="kpi"><div class="lbl">Test Reauth</div><div class="val blue">{t_tot.reauth_rate:.1f}%</div><div class="note">Index: {reauth_idx_total}</div></div>
  <div class="kpi"><div class="lbl">Holdout S2C</div><div class="val org">{h_tot.s2c_rate:.1f}%</div></div>
  <div class="kpi"><div class="lbl">Test S2C</div><div class="val blue">{t_tot.s2c_rate:.1f}%</div><div class="note">Index: {s2c_idx_total}</div></div>
  <div class="kpi"><div class="lbl">Incremental Revenue</div><div class="val {incr_class}">{incr_sign}${abs(incr_rev):,.0f}</div><div class="note">{ps_sign}${abs(incr_per_send):,.2f} per send &bull; ARPC ${t_arpc:,.2f}</div></div>
</div>

<div class="section-label">Incremental Revenue Drivers: {winner_labels_str}</div>
<div class="kpi-row winner-row">
  <div class="kpi"><div class="lbl">Holdout Sends</div><div class="val org">{int(wh.sends):,}</div></div>
  <div class="kpi"><div class="lbl">Test Sends</div><div class="val blue">{int(wt.sends):,}</div></div>
  <div class="kpi"><div class="lbl">Holdout Reauth</div><div class="val org">{float(wh.reauth_rate):.1f}%</div></div>
  <div class="kpi"><div class="lbl">Test Reauth</div><div class="val blue">{float(wt.reauth_rate):.1f}%</div><div class="note">Index: {w_reauth_idx}</div></div>
  <div class="kpi"><div class="lbl">Holdout S2C</div><div class="val org">{float(wh.s2c_rate):.1f}%</div></div>
  <div class="kpi"><div class="lbl">Test S2C</div><div class="val blue">{float(wt.s2c_rate):.1f}%</div><div class="note">Index: {w_s2c_idx}</div></div>
  <div class="kpi"><div class="lbl">Incremental Revenue</div><div class="val {w_incr_class}">{w_incr_sign}${abs(w_incr_rev):,.0f}</div><div class="note">{w_ps_sign}${abs(w_incr_per_send):,.2f} per send</div></div>
</div>
<div class="spacer"></div>

<div class="section">
  <h2 style="display:inline-block;">Results by Canvas Step &mdash; Pre/Post Content Change (May 8)</h2>
  <select id="periodFilter" onchange="filterPeriodTable()" style="margin-left:12px;padding:5px 10px;border-radius:6px;border:1px solid #dee2e6;font-size:13px;vertical-align:middle;">
    <option value="all" selected>All Dates</option>
    <option value="pre_0508">Pre 5/8 (Original Content)</option>
    <option value="post_0508">Post 5/8 (Updated Content)</option>
  </select>
  <table><thead><tr><th>Canvas Step</th><th>Group</th><th>Sends</th><th>Reauths</th><th>Reauth Rate</th><th>Completes</th><th>S2C</th><th>Incr. Revenue</th></tr></thead><tbody id="periodTableBody"></tbody></table>
</div>

<div class="section">
  <h2 style="display:inline-block;">Results by Canvas Step</h2>
  <select id="stepDateFilter" onchange="filterStepTable()" style="margin-left:12px;padding:5px 10px;border-radius:6px;border:1px solid #dee2e6;font-size:13px;vertical-align:middle;">
    {date_options_html}
  </select>
  <table><thead><tr><th>Canvas Step</th><th>Group</th><th>Sends</th><th>Reauths</th><th>Reauth Rate</th><th>Completes</th><th>S2C</th><th>Incr. Revenue</th></tr></thead><tbody id="stepTableBody"></tbody></table>
</div>
<div class="section">
  <h2 style="display:inline-block;">Daily Volume, Reauth Rate &amp; S2C</h2>
  <select id="dailyStepFilter" onchange="filterDailyTable()" style="margin-left:12px;padding:5px 10px;border-radius:6px;border:1px solid #dee2e6;font-size:13px;vertical-align:middle;">
    {step_options_html}
  </select>
  <div style="overflow-x:auto;"><table><thead><tr>
    <th>Date</th><th class="col-hold">Holdout Sends</th><th class="col-test">Test Sends</th><th class="col-hold">Cum Holdout</th><th class="col-test">Cum Test</th>
    <th class="col-hold">Hold Reauth</th><th class="col-test">Test Reauth</th><th>Idx vs. Holdout</th><th class="col-hold">Hold S2C</th><th class="col-test">Test S2C</th><th>Idx vs. Holdout</th>
  </tr></thead><tbody id="dailyTableBody"></tbody></table></div>
</div>
<script>
var DAILY_DATA={daily_json};
var STEP_DATA={step_json};
var PERIOD_DATA={period_json};
var STEPS={steps_json};
var STEP_LABELS_MAP={labels_json};
var DEDUP_ARPC={round(dedup_arpc_test, 2)};
function idxClass(v){{if(v>100)return"up";if(v<100)return"down";return"flat";}}
function fmtInt(v){{return v!=null?v.toLocaleString():"\\u2014";}}
function fmtPct(v){{return v!=null?v.toFixed(1)+"%":"\\u2014";}}
function fmtIncr(v){{if(v==null)return"\\u2014";var s=v>=0?"+":"-";var cls=v>=0?"up":"down";return'<span class="'+cls+'">'+s+"$"+Math.abs(v).toLocaleString(undefined,{{minimumFractionDigits:0,maximumFractionDigits:0}})+"</span>";}}

function renderStepRows(filtered, tbody) {{
  var rows="";
  STEPS.forEach(function(step){{
    var t=filtered.find(function(r){{return r.step===step&&r.group==="test";}});
    var h=filtered.find(function(r){{return r.step===step&&r.group==="holdout";}});
    if(!t||!h)return;
    var ri=h.reauth_rate>0?Math.round(t.reauth_rate/h.reauth_rate*1000)/10:null;
    var si=h.s2c_rate>0?Math.round(t.s2c_rate/h.s2c_rate*1000)/10:null;
    var rc=ri!==null?idxClass(ri):"flat";var sc=si!==null?idxClass(si):"flat";
    var incr=(t.s2c_rate/100-h.s2c_rate/100)*t.sends*DEDUP_ARPC;
    rows+='<tr class="step-row"><td rowspan="3"><strong>'+STEP_LABELS_MAP[step]+'</strong></td><td class="col-hold">Holdout</td><td>'+fmtInt(h.sends)+'</td><td>'+fmtInt(h.reauths)+'</td><td>'+fmtPct(h.reauth_rate)+'</td><td>'+fmtInt(h.completes)+'</td><td>'+fmtPct(h.s2c_rate)+'</td><td rowspan="3" style="vertical-align:middle;text-align:center;font-size:15px;font-weight:700;">'+fmtIncr(incr)+'</td></tr>';
    rows+='<tr class="step-row"><td class="col-test">Test</td><td>'+fmtInt(t.sends)+'</td><td>'+fmtInt(t.reauths)+'</td><td>'+fmtPct(t.reauth_rate)+'</td><td>'+fmtInt(t.completes)+'</td><td>'+fmtPct(t.s2c_rate)+'</td></tr>';
    rows+='<tr class="idx-row"><td>Idx vs. Holdout</td><td></td><td></td><td class="'+rc+'">'+(ri!==null?ri.toFixed(1):"\\u2014")+'</td><td></td><td class="'+sc+'">'+(si!==null?si.toFixed(1):"\\u2014")+'</td></tr>';
  }});
  tbody.innerHTML=rows;
}}

function filterDailyTable(){{var sel=document.getElementById("dailyStepFilter").value;var filtered=DAILY_DATA.filter(function(r){{return r.step===sel;}});var tbody=document.getElementById("dailyTableBody");var rows="";filtered.forEach(function(r){{var rc=r.ri!==null?idxClass(r.ri):"flat";var sc=r.si!==null?idxClass(r.si):"flat";var ri_str=r.ri!==null?r.ri.toFixed(1):"\\u2014";var si_str=r.si!==null?r.si.toFixed(1):"\\u2014";rows+='<tr><td>'+r.date_fmt+'</td><td>'+fmtInt(r.sends_h)+'</td><td>'+fmtInt(r.sends_t)+'</td><td>'+fmtInt(r.cum_h)+'</td><td>'+fmtInt(r.cum_t)+'</td><td>'+fmtPct(r.rr_h)+'</td><td>'+fmtPct(r.rr_t)+'</td><td class="'+rc+'">'+ri_str+'</td><td>'+fmtPct(r.sc_h)+'</td><td>'+fmtPct(r.sc_t)+'</td><td class="'+sc+'">'+si_str+'</td></tr>';}});tbody.innerHTML=rows;}}

function filterStepTable(){{var sel=document.getElementById("stepDateFilter").value;var filtered=STEP_DATA.filter(function(r){{return r.date===sel;}});renderStepRows(filtered, document.getElementById("stepTableBody"));}}

function filterPeriodTable(){{var sel=document.getElementById("periodFilter").value;var filtered=PERIOD_DATA.filter(function(r){{return r.period===sel;}});renderStepRows(filtered, document.getElementById("periodTableBody"));}}

filterDailyTable();filterStepTable();filterPeriodTable();
</script></body></html>"""

    output_path = "docs/reachone.html"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\nSaved to {output_path} ({len(html):,} chars)")


if __name__ == "__main__":
    main()
