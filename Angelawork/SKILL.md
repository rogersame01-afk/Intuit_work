---
name: voc-milestone-drivers
description: Analyze VoC contact drivers for any TurboTax product area — accepts a free-text description of the product area and customer type, parses it into SQL filters (milestone, keyword, segment), dynamically classifies themes, and produces a short summary with sample verbatims and PM-actionable takeaways. Use when asked about VoC for a product area, contact drivers for a screen, why customers contact support about a topic, VoC themes by milestone, sizing a UI change with VoC, abandoned customer VoC, or contact reasons by funnel stage.
---

# VoC Product Area Analysis

> **Contributed by:** awatson4

Joins `cgan_ustax_ws.tmp_cgcs_voc_cct` (milestone at contact) to `voc_7216_dwh.structured_extracts` (customer experiences) and `tax_rpt.product_analytics_master` (product segment). Accepts a free-text description of any product area and customer type, then produces classified themes, verbatims, and takeaways.

## When NOT to use

- **Survey scores** (PRS, MPS, TNPS) → use `voc-insights`
- **Raw VoC theme queries** without milestone context → use `voc-structured-extracts`
- **Abandonment analysis** without VoC → use `tto-abandonment`

## Prerequisites

- **pydatalake** with `sqlwarehouse` backend
- **7216 compliance** applies — read `7216-tax-data-guard` rule

## Step 1: Parse the user's request

The user provides a free-text description. Examples:

- "W-2 import issues"
- "VoC for the Wages & Income screen"
- "What are DIY customers contacting about at Final Review?"
- "Pricing friction for new filers in peak season"
- "1099 problems for abandoned customers"

Extract these parameters from the description. If ambiguous, ask a brief open-ended clarifying question — do not present pre-selected options or multiple-choice menus.

| Parameter | How to infer | Default |
|-----------|-------------|---------|
| **Topic keyword(s)** | Named topics like "W-2", "1099", "pricing", "overtime". If present, add `LIKE` filters on `intent_object` and `summary` in the VoC CTE. | None (all topics) |
| **Milestone** | Screen names map to milestones (see list below). | All milestones |
| **Product segment** | "DIY" / "DIWM" / "Core Tax" / no mention. | DIY + DIWM (Core Tax) |
| **Season** | Season name or a launch date (see season resolution below). | All seasons |
| **Abandoned only?** | Only if user says "abandoned", "didn't complete", "dropped off", etc. | All customers |

### Season resolution via `common_dm.dim_cg_date`

Season filtering uses `common_dm.dim_cg_date` — the canonical date dimension — instead of hardcoded date boundaries. This ensures season definitions stay current across tax years.

**When the user provides a season name**, map it to the `season_part` column in `dim_cg_date`:

| User language | `season_part` value |
|---|---|
| "early season" | `Early Season` |
| "first peak", "January peak" | `First Peak` |
| "pre-price increase" | `Pre-Price Increase` |
| "trough", "March" | `Trough` |
| "second peak", "April peak", "peak season" | `Second Peak` |
| "late season", "extension", "post-deadline" | `Late Season` |

**When the user provides a launch date** (e.g., "we're launching March 20" or "new experience goes live 3/20"), resolve it to a season part:

```sql
SELECT DISTINCT season_part
FROM common_dm.dim_cg_date
WHERE tax_pt_date = DATE '2026-03-20'
  AND tax_year = 2025
```

Use the returned `season_part` as the filter. Tell the user which season part the date falls into:

> "March 20 falls in **Trough** (3/1–3/31 for TY25). Filtering VoC themes to that season."

**When the user provides a launch date**, also offer a comparison:

> "Would you also like to see themes from the prior season part (**Pre-Price Increase**, 2/16–2/28) as a baseline comparison?"

If the user accepts, run the query twice (or include both season parts) and present a side-by-side comparison of theme volume and negativity.

### Milestone reference (TY25)

Run `SELECT DISTINCT milestone FROM cgan_ustax_ws.tmp_cgcs_voc_cct WHERE cct_tax_year = 2025 AND milestone IS NOT NULL` to get the latest list. Known milestones:

- `0-Not Started`
- `1-Sign in`
- `2-GTKM`
- `3-Personal Info - You & Your Family`
- `4-Federal Taxes - Wages & Income`
- `5-Federal Taxes - Deductions & Credits`
- `6-Federal Taxes - Other Tax Situations`
- `7-Federal Taxes - Federal Review`
- `8-State Taxes`
- `9-Final Review`
- `10-Finish and File`
- `11-Completed/Post File`

Map user language to milestones: "Wages & Income screen" → milestone `4-Federal Taxes - Wages & Income`, "Final Review" → `9-Final Review`, "filing screen" → `10-Finish and File`, etc.

### PAM join logic

**New / Returning segmentation** — always use `tto_segment_rollup` (or `tto_segment` for finer grain). Do NOT use `customer_type` — it does not align with the canonical TTO segment definitions.

| `tto_segment_rollup` | `tto_segment` values |
|---|---|
| `New` | New account, Prospect, Skip Year, Winback |
| `Returning` | First Year Returning, Veteran Returning |

| Filter | SQL |
|---|---|
| New customers | `pam.tto_segment_rollup = 'New'` |
| Returning customers | `pam.tto_segment_rollup = 'Returning'` |
| Specific sub-segment | `pam.tto_segment = 'New account'` (etc.) |

**SKU segment filtering** — always use `start_sku_rollup`. It is populated for both starters and completers. Do NOT use `core_flag`.

| Segment | `start_sku_rollup` values |
|---------|--------------------------|
| DIY only | `'DIY FREE', 'DIY PAID', 'CK DIY FREE'` |
| DIWM only | `'DIWM BASIC', 'DIWM NON-BASIC'` |
| DIY + DIWM (Core Tax) | All 5 values above |
| Non-CK DIY | `'DIY FREE', 'DIY PAID', 'DIWM BASIC', 'DIWM NON-BASIC'` |

**App type filtering** — use `start_app_type` when the user specifies a platform.

| Platform | `start_app_type` values |
|---|---|
| Mobile Web | `'Mobile Web'` |
| Stationary Web (desktop) | `'Stationary Web'` |
| Mobile App | `'Mobile App'` |
| Web (all) | `'Mobile Web', 'Stationary Web'` |

| Completion filter | Additional PAM conditions |
|-------------------|--------------------------|
| All customers | `pam.tto_start_flag = 1` |
| Abandoned only | `pam.tto_start_flag = 1 AND pam.completed_flag = 0` |
| Completers only | `pam.tto_start_flag = 1 AND pam.completed_flag = 1` |

## Step 2: Run the base query

Two query modes depending on whether the user specified a topic keyword:

### Mode A: Topic-specific (keyword provided)

Add keyword filters in the `voc_exploded` CTE on both `intent_object` and `summary`. Example for "W-2":

```sql
AND (
  LOWER(ce.primary_intent.primary_intent_object) LIKE '%w-2%'
  OR LOWER(ce.primary_intent.primary_intent_object) LIKE '%w2%'
  OR LOWER(ce.summary) LIKE '%w-2%'
  OR LOWER(ce.summary) LIKE '%w2%'
)
```

### Mode B: Screen-wide (no keyword, milestone specified)

No keyword filter on VoC — return all contact themes at that milestone.

### Base SQL template

```sql
WITH date_dim AS (
  SELECT DISTINCT tax_pt_date, season_part
  FROM common_dm.dim_cg_date
  WHERE tax_year = 2025
),
contacts AS (
  SELECT
    cct.agent_source_key AS contact_id,
    cct.milestone,
    dd.season_part
  FROM cgan_ustax_ws.tmp_cgcs_voc_cct cct
  INNER JOIN tax_rpt.product_analytics_master pam
    ON cct.cct_auth_id = pam.auth_id AND cct.cct_tax_year = pam.tax_year
  INNER JOIN date_dim dd
    ON dd.tax_pt_date = to_date(from_utc_timestamp(cct.agent_leg_start_ts_utc, 'America/Los_Angeles'))
  WHERE cct.customer_handle_flg = 1
    AND cct.cct_tax_year = 2025
    AND cct.cct_auth_id IS NOT NULL AND cct.cct_auth_id <> '' AND cct.cct_auth_id <> '000-00-0000'
    AND pam.tto_start_flag = 1
    AND pam.start_sku_rollup IN ('DIY FREE', 'DIY PAID', 'CK DIY FREE', 'DIWM BASIC', 'DIWM NON-BASIC')
    /* Optional: AND pam.tto_segment_rollup = 'New'  -- new/returning filter */
    /* Optional: AND pam.start_app_type IN ('Mobile Web', 'Stationary Web')  -- platform filter */
    /* Optional: AND pam.completed_flag = 0  -- for abandoned only */
    /* Optional: AND cct.milestone = '4-Federal Taxes - Wages & Income' */
    /* Optional: AND dd.season_part = 'Trough'  -- for season / launch date filter */
),
voc_exploded AS (
  SELECT
    v.source_id AS contact_id,
    ce.primary_intent.primary_intent_verb AS intent_verb,
    ce.primary_intent.primary_intent_object AS intent_object,
    ce.sentiment AS experience_sentiment,
    ce.summary AS experience_summary
  FROM voc_7216_dwh.structured_extracts v
  LATERAL VIEW EXPLODE(v.customer_experiences) AS ce
  WHERE v.tax_year = 2025
    AND v.product = 'TurboTax'
    AND v.source_type = 'callchat'
    AND v.dominant_intent IS NOT NULL AND v.dominant_intent <> ''
    AND ce.summary IS NOT NULL AND ce.summary <> ''
    /* Optional: keyword filters for Mode A */
)
SELECT
  c.season_part, c.milestone, ve.intent_verb, ve.intent_object,
  CAST(COUNT(*) AS INT) AS volume,
  CAST(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY c.season_part, c.milestone), 1) AS DOUBLE) AS pct_within_milestone,
  CAST(COUNT(CASE WHEN ve.experience_sentiment = 'negative' THEN 1 END) AS INT) AS negative_cnt,
  CAST(ROUND(COUNT(CASE WHEN ve.experience_sentiment = 'negative' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 1) AS DOUBLE) AS pct_negative
FROM contacts c
INNER JOIN voc_exploded ve ON c.contact_id = ve.contact_id
WHERE c.season_part IS NOT NULL
  AND ve.intent_verb IS NOT NULL AND ve.intent_verb <> ''
  AND ve.intent_object IS NOT NULL AND ve.intent_object <> ''
GROUP BY c.season_part, c.milestone, ve.intent_verb, ve.intent_object
HAVING COUNT(*) >= 5
ORDER BY c.milestone, c.season_part, volume DESC
```

Save to parquet: `--format parquet -o /tmp/voc_product_area.parquet`

**Critical:** Cast numeric columns to `INT`/`DOUBLE` to avoid Decimal serialization errors.

## Step 3: Dynamic theme classification

Do NOT use a hardcoded classifier. Instead, dynamically group the raw verb/object pairs:

1. Load the parquet into pandas
2. Create `subcategory = intent_verb + ' -> ' + intent_object`
3. Examine the top ~50 subcategories by volume
4. Group into **8–15 human-readable themes** using these principles:
   - **Merge spelling/hyphenation variants** (e.g., "W2" and "W-2", "enter" and "add")
   - **Separate high-negativity error themes** from routine entry/verification themes
   - **Keep actionable specificity** — "Import W-2 failed" is better than "W-2 issues"
   - **Remove generic themes** — exclude verb/object combos like `file → tax return`, `complete → tax return filing`, `prepare → taxes` that are too vague to act on
5. Apply the classification to every row and re-aggregate by theme
6. Sort by volume descending

### Refund disambiguation

When "refund" appears in themes, it mixes product refunds, tax refund status, and refund advance/loan. Disambiguate:

| Pattern | Label |
|---------|-------|
| Object contains `advance` or `loan` | `apply → refund advance/loan` |
| Object contains `refund request` or `refund form`, or verb = `escalate` + refund | `request → product refund (TT charges)` |
| Object contains `refund status`, `missing refund`, `delayed refund` | `check → tax refund status` |
| Verb in (check, track, confirm, verify) + refund | `check → tax refund status` |
| Object contains `refund discrepancy`, `refund calculation`, `refund amount` | `resolve → refund amount discrepancy` |
| Generic "get/obtain refund" | Exclude from top-N display (too ambiguous) |

## Step 4: Pull sample verbatims for top themes

After theme classification, run a second query to pull 1–2 negative-sentiment verbatims for each of the **top 5 themes by volume**. These are included in the initial summary — do not defer verbatims to a follow-up.

Use a `ROW_NUMBER()` window partitioned by theme to pick the most descriptive summaries (ordered by `LENGTH(experience_summary) DESC` to favor detailed accounts over terse ones). Filter to `sentiment = 'negative'` so verbatims illustrate the pain, not routine contacts.

### Verbatim SQL template

```sql
WITH date_dim AS ( /* same as base query */ ),
contacts AS ( /* same as base query */ ),
voc_exploded AS (
  SELECT
    v.source_id AS contact_id,
    ce.primary_intent.primary_intent_verb AS intent_verb,
    ce.primary_intent.primary_intent_object AS intent_object,
    ce.sentiment AS experience_sentiment,
    SUBSTRING(ce.summary, 1, 500) AS experience_summary
  FROM voc_7216_dwh.structured_extracts v
  LATERAL VIEW EXPLODE(v.customer_experiences) AS ce
  WHERE v.tax_year = 2025
    AND v.product = 'TurboTax'
    AND v.source_type = 'callchat'
    AND v.dominant_intent IS NOT NULL AND v.dominant_intent <> ''
    AND ce.summary IS NOT NULL AND ce.summary <> ''
    AND ce.sentiment = 'negative'
    /* Optional: same keyword filters as base query for Mode A */
),
ranked AS (
  SELECT
    c.tto_segment_rollup,
    ve.intent_verb,
    ve.intent_object,
    ve.experience_summary,
    <theme_case_expression> AS theme,
    ROW_NUMBER() OVER (
      PARTITION BY <theme_case_expression>
      ORDER BY LENGTH(ve.experience_summary) DESC
    ) AS rn
  FROM contacts c
  INNER JOIN voc_exploded ve ON c.contact_id = ve.contact_id
)
SELECT theme, tto_segment_rollup, intent_verb, intent_object, experience_summary
FROM ranked
WHERE theme NOT IN ('Other', '_GENERIC')
  AND rn <= 2
ORDER BY theme, tto_segment_rollup, rn
```

Build the `<theme_case_expression>` dynamically from the themes identified in Step 3 — use `CASE WHEN LOWER(intent_object) LIKE '%keyword%' THEN 'Theme Name' ... ELSE 'Other' END`. Only include the top 5 themes by volume to keep the query focused.

Save to parquet: `--format parquet -o /tmp/voc_verbatims.parquet`

**Critical:** Truncate summaries with `SUBSTRING(ce.summary, 1, 500)` to avoid oversized results.

## Step 5: Produce output

Produce a **short summary** (3–5 sentences):

- Total contacts matching the filters
- Top 3–4 themes with volume and negativity %
- One sentence on seasonal pattern (which season has most volume or highest pain)
- One sentence on the single highest-negativity theme

Then, for each of the **top 5 themes**, include 1–2 sample verbatims (negative sentiment) inline. Format each verbatim as a blockquote with the customer segment label:

> **[Returning]** "Customer called TurboTax frustrated because..."

Verbatims ground the quantitative summary in real customer language and make the output immediately useful to PMs without requiring a follow-up drill-down.

## Step 6: PM-Actionable Recommendations

**Always produce this section** — do not offer it as a follow-up. It appears as a standalone `## PM-Actionable Recommendations` heading after the summary and verbatims.

Generate **3 recommendations**, one per bullet, each tied to a specific theme from the analysis. Each recommendation must follow this structure:

1. **Action-oriented headline** — starts with a verb, names the specific product surface or flow (e.g., "Make 1099-R entry smarter about edge cases")
2. **Evidence** — cite the theme's volume and negativity %, plus the New vs Returning gap if meaningful (e.g., "720 contacts, 36% negative, 12pp worse for Returning")
3. **Mechanism** — one sentence explaining *why* customers are struggling, grounded in the verbatims (e.g., "TurboTax requires RMD fields even when the account was liquidated")
4. **Suggested intervention** — a concrete product change, not a vague recommendation (e.g., "Suppress inapplicable fields based on distribution code" not "Improve the 1099-R experience")

Prioritize recommendations by **volume × negativity** (pain-weighted impact), not volume alone. A 200-contact theme at 80% negativity ranks above a 600-contact theme at 15% negativity.

Format example:

> **1. Fix the 1099-R entry flow — suppress inapplicable fields based on distribution code.** 720 contacts at 36% negative (12pp worse for Returning). Customers are forced to enter RMD and Form 8606 fields that don't apply to their distribution type. Build conditional logic that skips inapplicable fields based on the distribution code already entered, and allow explicit "I didn't receive this form" bypasses.

After the recommendations, offer optional follow-ups:
- Re-run for abandoned-only or completers-only
- Break down by milestone x season (detailed table)
- Filter to a different product segment
- Pull additional verbatims for a specific theme
## Gotchas

- **New/Returning segmentation** — always use `tto_segment_rollup` (or `tto_segment` for sub-segments). Do NOT use `customer_type` — it does not align with the canonical TTO segment definitions
- **Always use `start_sku_rollup`** for SKU segment filtering — it is populated for all starters regardless of completion status. Do NOT use `core_flag`
- **Platform filtering** — use `start_app_type` (values: `Mobile Web`, `Stationary Web`, `Mobile App`). Do NOT use `app_type` (does not exist)
- `completed_sku_rollup` is only populated for completers — do not use it for segment filtering
- `complete_flag` does not exist — the column is `completed_flag`
- `tto_flag` does not exist in PAM — do not reference it
- **Milestone reliability for New customers** — a high proportion of New customer contacts show milestone `0-Not Started` even when the customer is clearly engaged in tax prep (e.g., W-2 upload). The milestone stamp is often stale for this population. Flag this caveat when presenting milestone breakdowns for New customers
- Cast numeric columns to `INT`/`DOUBLE` in SQL to avoid Python Decimal serialization errors
- Truncate `sanitized_source_text` with `SUBSTRING(..., 1, 3000)` if pulling raw transcripts
- Season part comes from `common_dm.dim_cg_date` joined on `tax_pt_date` — do NOT hardcode season date boundaries
- The `dim_cg_date` join key uses PST: `to_date(from_utc_timestamp(cct.agent_leg_start_ts_utc, 'America/Los_Angeles'))`
- `dim_cg_date` has hourly grain (~24 rows per date) — always deduplicate with `SELECT DISTINCT tax_pt_date, season_part` in a CTE before joining to avoid fan-out
- The HAVING threshold of `>= 5` works for topic-specific queries; raise to `>= 10` for broad screen-wide queries to reduce noise
