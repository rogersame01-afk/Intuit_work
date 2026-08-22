#!/usr/bin/env python3
"""Refresh CSO 801 AGI Auto dashboard (Paid Not Filed) — single optimized query."""

import subprocess
import sys
from datetime import datetime

import pandas as pd

CAMPAIGN_START = "2026-03-05"
CANVAS_NAME = "801_CSO_TY25_AGI_Auto_1k_medium_EM_ST_SMS"


def run_query(sql, label="query"):
    result = subprocess.run(
        ["pydatalake", "query", sql, "--backend", "sqlwarehouse", "--limit", "0",
         "--format", "parquet", "-o", "/tmp/cso801_tmp.parquet", "--no-cache"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"{label} failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return pd.read_parquet("/tmp/cso801_tmp.parquet")


COMBINED_SQL = f"""
WITH base AS (
  SELECT
    pseudonym_id,
    CASE WHEN MAX(CASE WHEN canvas_step_name LIKE 'wh_801_%' THEN 1 ELSE 0 END) = 1
         THEN 'holdout' ELSE 'test' END AS test_group
  FROM (
    SELECT DISTINCT external_user_id AS pseudonym_id, canvas_step_name
    FROM tax_src.src_braze_turbotax_email_delivery
    WHERE year = 2026
      AND date(from_utc_timestamp(cast(time AS timestamp), 'America/Los_Angeles')) >= '{CAMPAIGN_START}'
      AND canvas_name = '{CANVAS_NAME}'

    UNION

    SELECT DISTINCT external_user_id AS pseudonym_id, canvas_step_name
    FROM tax_src.src_braze_turbotax_webhook_send
    WHERE year = 2026
      AND date(from_utc_timestamp(cast(time AS timestamp), 'America/Los_Angeles')) >= '{CAMPAIGN_START}'
      AND canvas_name = '{CANVAS_NAME}'
  )
  GROUP BY pseudonym_id
),

user_level AS (
  SELECT
    b.pseudonym_id,
    b.test_group,
    MAX(CASE WHEN r.auth_id IS NOT NULL THEN 1 ELSE 0 END) AS reauthed,
    MAX(CASE WHEN pam.first_fed_efile_attempted_date IS NOT NULL THEN 1 ELSE 0 END) AS efile_attempted,
    MAX(CASE WHEN COALESCE(pam.first_fed_efile_accepted_date, pam.first_print_to_mail_date) IS NOT NULL THEN 1 ELSE 0 END) AS file_success,
    MAX(mam.rt_attach_flag) AS rt_attach_flag,
    MAX(mam.fde_attach_flag) AS fde_attach_flag,
    MAX(mam.total_revenue) AS total_revenue,
    MAX(mam.total_fde_revenue) AS total_fde_revenue
  FROM base b
  LEFT JOIN tax_rpt.product_analytics_master pam
      ON b.pseudonym_id = pam.pseudonym_id AND pam.tax_year = 2025
  LEFT JOIN (
      SELECT DISTINCT msam.auth_id
      FROM tax_rpt.marketing_session_analytics_master msam
      WHERE msam.tax_year = 2025
        AND date(msam.server_timestamp) >= date('{CAMPAIGN_START}')
        AND msam.auth_id IS NOT NULL
  ) r ON pam.auth_id = r.auth_id
  LEFT JOIN tax_rpt.monetization_analytics_master mam
      ON pam.auth_id = mam.auth_id AND mam.tax_year = 2025
  GROUP BY b.pseudonym_id, b.test_group
)

SELECT
  test_group,

  COUNT(*) AS sends,
  SUM(reauthed) AS reauths,
  SUM(efile_attempted) AS fed_efile_attempts,
  SUM(file_success) AS file_successes,

  SUM(CASE WHEN rt_attach_flag = 1 THEN 1 ELSE 0 END) AS rt_sends,
  SUM(CASE WHEN rt_attach_flag = 1 AND reauthed = 1 THEN 1 ELSE 0 END) AS rt_reauths,
  SUM(CASE WHEN rt_attach_flag = 1 AND efile_attempted = 1 THEN 1 ELSE 0 END) AS rt_efile_attempts,
  SUM(CASE WHEN rt_attach_flag = 1 AND file_success = 1 THEN 1 ELSE 0 END) AS rt_file_successes,
  SUM(CASE WHEN rt_attach_flag = 1 AND file_success = 1 THEN 1 ELSE 0 END) AS rt_completers,
  SUM(CASE WHEN rt_attach_flag = 1 AND file_success = 1 THEN total_revenue ELSE 0 END) AS rt_revenue,

  SUM(CASE WHEN fde_attach_flag = 1 THEN 1 ELSE 0 END) AS fde_sends,
  SUM(CASE WHEN fde_attach_flag = 1 AND reauthed = 1 THEN 1 ELSE 0 END) AS fde_reauths,
  SUM(CASE WHEN fde_attach_flag = 1 AND efile_attempted = 1 THEN 1 ELSE 0 END) AS fde_efile_attempts,
  SUM(CASE WHEN fde_attach_flag = 1 AND file_success = 1 THEN 1 ELSE 0 END) AS fde_file_successes,
  SUM(CASE WHEN fde_attach_flag = 1 AND file_success = 1 THEN 1 ELSE 0 END) AS fde_completers,
  SUM(CASE WHEN fde_attach_flag = 1 AND file_success = 1 THEN total_fde_revenue ELSE 0 END) AS fde_revenue

FROM user_level
GROUP BY test_group
"""


def pct(num, den):
    return round(num / den * 100, 1) if den > 0 else 0.0

def ith(test_rate, hold_rate):
    return round(test_rate / hold_rate * 100, 1) if hold_rate > 0 else None

def ith_class(v):
    if v is None: return "flat"
    return "up" if v > 100 else ("down" if v < 100 else "flat")

def fmt_int(v):   return f"{int(v):,}"
def fmt_pct(v):   return f"{v:.1f}%"
def fmt_dol(v):   return f"${v:,.2f}"
def fmt_ith(v):   return f"{v:.1f}" if v is not None else "&mdash;"
def ith_td(v):    return f'<td class="{ith_class(v)}">{fmt_ith(v)}</td>'

def safe_div(a, b):
    return float(a) / float(b) if float(b) > 0 else 0.0


def main():
    print("Querying all metrics in a single pass...")
    df = run_query(COMBINED_SQL, "Combined")

    for c in df.columns:
        if c != "test_group":
            df[c] = pd.to_numeric(df[c], errors="coerce").fillna(0)

    t = df[df.test_group == "test"]
    h = df[df.test_group == "holdout"]
    if len(t) == 0 or len(h) == 0:
        print(f"ERROR: Missing test or holdout rows.\n{df}", file=sys.stderr)
        sys.exit(1)
    t, h = t.iloc[0], h.iloc[0]

    # --- Overall ---
    t_sends, h_sends = int(t.sends), int(h.sends)
    t_reauths, h_reauths = int(t.reauths), int(h.reauths)
    t_rr, h_rr = pct(t_reauths, t_sends), pct(h_reauths, h_sends)
    rr_ith = ith(t_rr, h_rr)
    t_efile, h_efile = int(t.fed_efile_attempts), int(h.fed_efile_attempts)
    t_fs, h_fs = int(t.file_successes), int(h.file_successes)
    t_fsr, h_fsr = pct(t_fs, t_sends), pct(h_fs, h_sends)
    fsr_ith = ith(t_fsr, h_fsr)
    efile_ith = ith(pct(t_efile, t_sends), pct(h_efile, h_sends))

    print(f"  Test sends: {t_sends:,}  Holdout sends: {h_sends:,}")
    print(f"  Reauth ITH: {rr_ith}  File Success ITH: {fsr_ith}")

    # --- RT cohort ---
    rt_t_sends, rt_h_sends = int(t.rt_sends), int(h.rt_sends)
    rt_t_reauths, rt_h_reauths = int(t.rt_reauths), int(h.rt_reauths)
    rt_t_rr, rt_h_rr = pct(rt_t_reauths, rt_t_sends), pct(rt_h_reauths, rt_h_sends)
    rt_rr_ith = ith(rt_t_rr, rt_h_rr)
    rt_t_efile, rt_h_efile = int(t.rt_efile_attempts), int(h.rt_efile_attempts)
    rt_t_fs, rt_h_fs = int(t.rt_file_successes), int(h.rt_file_successes)
    rt_t_fsr, rt_h_fsr = pct(rt_t_fs, rt_t_sends), pct(rt_h_fs, rt_h_sends)
    rt_fsr_ith = ith(rt_t_fsr, rt_h_fsr)
    rt_efile_ith = ith(pct(rt_t_efile, rt_t_sends), pct(rt_h_efile, rt_h_sends))
    rt_t_arpc = safe_div(t.rt_revenue, t.rt_completers)
    rt_h_arpc = safe_div(h.rt_revenue, h.rt_completers)
    rt_incr_rev = (rt_t_fsr / 100 - rt_h_fsr / 100) * rt_t_sends * rt_t_arpc

    # --- 5DE cohort ---
    fde_t_sends, fde_h_sends = int(t.fde_sends), int(h.fde_sends)
    fde_t_reauths, fde_h_reauths = int(t.fde_reauths), int(h.fde_reauths)
    fde_t_rr, fde_h_rr = pct(fde_t_reauths, fde_t_sends), pct(fde_h_reauths, fde_h_sends)
    fde_rr_ith = ith(fde_t_rr, fde_h_rr)
    fde_t_efile, fde_h_efile = int(t.fde_efile_attempts), int(h.fde_efile_attempts)
    fde_t_fs, fde_h_fs = int(t.fde_file_successes), int(h.fde_file_successes)
    fde_t_fsr, fde_h_fsr = pct(fde_t_fs, fde_t_sends), pct(fde_h_fs, fde_h_sends)
    fde_fsr_ith = ith(fde_t_fsr, fde_h_fsr)
    fde_efile_ith = ith(pct(fde_t_efile, fde_t_sends), pct(fde_h_efile, fde_h_sends))
    fde_t_arpc = safe_div(t.fde_revenue, t.fde_completers)
    fde_h_arpc = safe_div(h.fde_revenue, h.fde_completers)
    fde_incr_rev = (fde_t_fsr / 100 - fde_h_fsr / 100) * fde_t_sends * fde_t_arpc

    print(f"  RT incr rev: ${rt_incr_rev:,.0f}  (ARPC test ${rt_t_arpc:,.2f} hold ${rt_h_arpc:,.2f})")
    print(f"  5DE incr rev: ${fde_incr_rev:,.0f}  (ARPC test ${fde_t_arpc:,.2f} hold ${fde_h_arpc:,.2f})")

    refresh_ts = datetime.now().strftime("%b %d, %Y %I:%M %p PT")
    rt_sign = "+" if rt_incr_rev >= 0 else ""
    rt_cls = "green" if rt_incr_rev >= 0 else "red"
    fde_sign = "+" if fde_incr_rev >= 0 else ""
    fde_cls = "green" if fde_incr_rev >= 0 else "red"

    html = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>TY25 Paid Not Filed</title>
<style>
  :root {{ --blue:#0066ff;--orange:#e8590c;--green:#2b8a3e;--red:#c92a2a;--gray:#868e96;--bg:#f8f9fa; }}
  * {{ margin:0;padding:0;box-sizing:border-box; }}
  body {{ font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:#212529;padding:28px;max-width:1200px;margin:0 auto; }}
  h1 {{ font-size:24px;font-weight:700; }}
  .sub {{ font-size:13px;color:var(--gray);margin-bottom:28px; }}
  .kpi-row {{ display:grid;grid-template-columns:repeat(auto-fit, minmax(170px, 1fr));gap:12px;margin-bottom:32px; }}
  .kpi {{ background:#fff;border-radius:10px;padding:16px 12px;box-shadow:0 1px 3px rgba(0,0,0,.06);text-align:center; }}
  .kpi .lbl {{ font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:var(--gray);margin-bottom:5px; }}
  .kpi .val {{ font-size:24px;font-weight:700; }}
  .kpi .note {{ font-size:11px;color:var(--gray);margin-top:3px; }}
  .blue {{ color:var(--blue); }} .org {{ color:var(--orange); }} .green {{ color:var(--green); }} .red {{ color:var(--red); }}
  .section {{ background:#fff;border-radius:10px;padding:20px;box-shadow:0 1px 3px rgba(0,0,0,.06);margin-bottom:24px; }}
  .section h2 {{ font-size:15px;font-weight:600;margin-bottom:14px; }}
  table {{ width:100%;border-collapse:collapse;font-size:12.5px; }}
  th {{ background:#f1f3f5;padding:8px 10px;text-align:right;font-weight:600;border-bottom:2px solid #dee2e6;white-space:nowrap; }}
  th:first-child {{ text-align:left; }}
  td {{ padding:7px 10px;border-bottom:1px solid #f1f3f5;text-align:right;font-variant-numeric:tabular-nums; }}
  td:first-child {{ text-align:left;font-weight:500; }}
  .up {{ color:var(--green);font-weight:700; }} .down {{ color:var(--red);font-weight:700; }} .flat {{ color:var(--gray);font-weight:700; }}
  .col-test {{ color:var(--blue); }} .col-hold {{ color:var(--orange); }}
  .divider {{ border:none;border-top:2px solid #dee2e6;margin:20px 0; }}
  @media (max-width:700px) {{ .kpi-row {{ grid-template-columns:repeat(3,1fr); }} }}
  @media (max-width:450px) {{ .kpi-row {{ grid-template-columns:repeat(2,1fr); }} }}
</style></head><body>
<h1>TY25 Paid Not Filed</h1>
<div class="sub">{CANVAS_NAME} &bull; Since {CAMPAIGN_START} &bull; Refreshed {refresh_ts}</div>

<div class="kpi-row">
  <div class="kpi"><div class="lbl">Holdout Sends</div><div class="val org">{fmt_int(h_sends)}</div></div>
  <div class="kpi"><div class="lbl">Test Sends</div><div class="val blue">{fmt_int(t_sends)}</div></div>
  <div class="kpi"><div class="lbl">Reauth ITH</div><div class="val {ith_class(rr_ith)}">{fmt_ith(rr_ith)}</div><div class="note">Test {fmt_pct(t_rr)} vs Hold {fmt_pct(h_rr)}</div></div>
  <div class="kpi"><div class="lbl">File Success ITH</div><div class="val {ith_class(fsr_ith)}">{fmt_ith(fsr_ith)}</div><div class="note">Test {fmt_pct(t_fsr)} vs Hold {fmt_pct(h_fsr)}</div></div>
  <div class="kpi"><div class="lbl">Incr. RT Revenue</div><div class="val {rt_cls}">{rt_sign}${abs(rt_incr_rev):,.0f}</div><div class="note">S2C ITH {fmt_ith(rt_fsr_ith)} &bull; ARPC {fmt_dol(rt_t_arpc)}</div></div>
  <div class="kpi"><div class="lbl">Incr. 5DE Revenue</div><div class="val {fde_cls}">{fde_sign}${abs(fde_incr_rev):,.0f}</div><div class="note">S2C ITH {fmt_ith(fde_fsr_ith)} &bull; ARPC {fmt_dol(fde_t_arpc)}</div></div>
</div>

<div class="section">
  <h2>Overall Funnel &mdash; All Users</h2>
  <table>
    <thead><tr><th>Metric</th><th class="col-hold">Holdout</th><th class="col-test">Test</th><th>Index to Holdout</th></tr></thead>
    <tbody>
      <tr><td>Sends</td><td>{fmt_int(h_sends)}</td><td>{fmt_int(t_sends)}</td><td>&mdash;</td></tr>
      <tr><td>Reauths</td><td>{fmt_int(h_reauths)}</td><td>{fmt_int(t_reauths)}</td>{ith_td(rr_ith)}</tr>
      <tr><td>Reauth Rate</td><td>{fmt_pct(h_rr)}</td><td>{fmt_pct(t_rr)}</td>{ith_td(rr_ith)}</tr>
      <tr><td>Fed E-file Attempts</td><td>{fmt_int(h_efile)}</td><td>{fmt_int(t_efile)}</td>{ith_td(efile_ith)}</tr>
      <tr><td>File Successes (Accepted/Print)</td><td>{fmt_int(h_fs)}</td><td>{fmt_int(t_fs)}</td>{ith_td(fsr_ith)}</tr>
      <tr><td>File Success Rate</td><td>{fmt_pct(h_fsr)}</td><td>{fmt_pct(t_fsr)}</td>{ith_td(fsr_ith)}</tr>
    </tbody>
  </table>
</div>

<div class="section">
  <h2>RT Attach Cohort</h2>
  <table>
    <thead><tr><th>Metric</th><th class="col-hold">Holdout</th><th class="col-test">Test</th><th>Index to Holdout</th></tr></thead>
    <tbody>
      <tr><td>Sends (RT Attached)</td><td>{fmt_int(rt_h_sends)}</td><td>{fmt_int(rt_t_sends)}</td><td>&mdash;</td></tr>
      <tr><td>Reauths</td><td>{fmt_int(rt_h_reauths)}</td><td>{fmt_int(rt_t_reauths)}</td>{ith_td(rt_rr_ith)}</tr>
      <tr><td>Reauth Rate</td><td>{fmt_pct(rt_h_rr)}</td><td>{fmt_pct(rt_t_rr)}</td>{ith_td(rt_rr_ith)}</tr>
      <tr><td>Fed E-file Attempts</td><td>{fmt_int(rt_h_efile)}</td><td>{fmt_int(rt_t_efile)}</td>{ith_td(rt_efile_ith)}</tr>
      <tr><td>File Successes</td><td>{fmt_int(rt_h_fs)}</td><td>{fmt_int(rt_t_fs)}</td>{ith_td(rt_fsr_ith)}</tr>
      <tr><td>File Success Rate</td><td>{fmt_pct(rt_h_fsr)}</td><td>{fmt_pct(rt_t_fsr)}</td>{ith_td(rt_fsr_ith)}</tr>
      <tr style="border-top:2px solid #dee2e6;"><td>Dedup ARPC (Total Revenue)</td><td>{fmt_dol(rt_h_arpc)}</td><td>{fmt_dol(rt_t_arpc)}</td><td>&mdash;</td></tr>
      <tr><td><strong>Incremental RT Revenue</strong></td><td colspan="2" style="text-align:center;font-size:18px;font-weight:700;" class="{rt_cls}">{rt_sign}${abs(rt_incr_rev):,.0f}</td><td class="note" style="font-size:11px;color:var(--gray);">({fmt_pct(rt_t_fsr)} &minus; {fmt_pct(rt_h_fsr)}) &times; {fmt_int(rt_t_sends)} &times; {fmt_dol(rt_t_arpc)}</td></tr>
    </tbody>
  </table>
</div>

<div class="section">
  <h2>5DE (Five Days Early) Attach Cohort</h2>
  <table>
    <thead><tr><th>Metric</th><th class="col-hold">Holdout</th><th class="col-test">Test</th><th>Index to Holdout</th></tr></thead>
    <tbody>
      <tr><td>Sends (5DE Attached)</td><td>{fmt_int(fde_h_sends)}</td><td>{fmt_int(fde_t_sends)}</td><td>&mdash;</td></tr>
      <tr><td>Reauths</td><td>{fmt_int(fde_h_reauths)}</td><td>{fmt_int(fde_t_reauths)}</td>{ith_td(fde_rr_ith)}</tr>
      <tr><td>Reauth Rate</td><td>{fmt_pct(fde_h_rr)}</td><td>{fmt_pct(fde_t_rr)}</td>{ith_td(fde_rr_ith)}</tr>
      <tr><td>Fed E-file Attempts</td><td>{fmt_int(fde_h_efile)}</td><td>{fmt_int(fde_t_efile)}</td>{ith_td(fde_efile_ith)}</tr>
      <tr><td>File Successes</td><td>{fmt_int(fde_h_fs)}</td><td>{fmt_int(fde_t_fs)}</td>{ith_td(fde_fsr_ith)}</tr>
      <tr><td>File Success Rate</td><td>{fmt_pct(fde_h_fsr)}</td><td>{fmt_pct(fde_t_fsr)}</td>{ith_td(fde_fsr_ith)}</tr>
      <tr style="border-top:2px solid #dee2e6;"><td>Dedup ARPC (5DE Revenue)</td><td>{fmt_dol(fde_h_arpc)}</td><td>{fmt_dol(fde_t_arpc)}</td><td>&mdash;</td></tr>
      <tr><td><strong>Incremental 5DE Revenue</strong></td><td colspan="2" style="text-align:center;font-size:18px;font-weight:700;" class="{fde_cls}">{fde_sign}${abs(fde_incr_rev):,.0f}</td><td class="note" style="font-size:11px;color:var(--gray);">({fmt_pct(fde_t_fsr)} &minus; {fmt_pct(fde_h_fsr)}) &times; {fmt_int(fde_t_sends)} &times; {fmt_dol(fde_t_arpc)}</td></tr>
    </tbody>
  </table>
</div>

<div class="section" style="background:#f0f4ff;border:1px solid #c9d6ff;">
  <h2>Methodology</h2>
  <div style="font-size:12.5px;line-height:1.7;color:#495057;">
    <p><strong>File Success Rate</strong> = (Fed E-file Accepted or Print-to-Mail) / Sends</p>
    <p><strong>Incremental Revenue</strong> = (Test S2C &minus; Holdout S2C) &times; Test Sends &times; Test ARPC<sub>dedup</sub></p>
    <p><strong>RT ARPC</strong> = User-level deduplicated total revenue for RT payers / RT completers = <strong>{fmt_dol(rt_t_arpc)}</strong></p>
    <p><strong>5DE ARPC</strong> = User-level deduplicated Five Days Early revenue / 5DE completers = <strong>{fmt_dol(fde_t_arpc)}</strong></p>
    <p style="margin-top:6px;color:var(--gray);font-size:11px;">RT and 5DE cohorts are filtered to users with the respective attach flag = 1. File success = accepted e-file or print-to-mail.</p>
  </div>
</div>

</body></html>"""

    output_path = "docs/cso801_agi_auto.html"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"\nSaved to {output_path} ({len(html):,} chars)")


if __name__ == "__main__":
    main()
