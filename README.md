# Multi-Touch Attribution Analysis

## Overview

Marketing teams frequently default to last-touch attribution because it's simple to implement — every conversion gets credited to whichever channel the customer interacted with right before converting. This is convenient, but it systematically undervalues awareness and consideration channels (display, social, email) that influence a customer earlier in their journey without being the final click.

This project builds and compares multiple attribution models — first-touch, last-touch, linear, and a data-driven approach — against a real multi-touchpoint dataset, to quantify how much credit (and, by extension, budget) shifts depending on which model a business chooses to trust.

**Dataset:** [Multi-Touch Attribution](https://www.kaggle.com/datasets/vivekparasharr/multi-touch-attribution) (Kaggle) — 10,000 rows of marketing touchpoint events across `User ID`, `Timestamp`, `Channel`, `Campaign`, and `Conversion`.

**Stack:** Python (pandas) for cleaning and transformation → PostgreSQL for structured querying and window-function-based modeling → Power BI for the final business-facing dashboard.

![Executive Summary page of the Power BI dashboard](images/executive_summary.png)

**Headline finding:** Display Ads earns the most credit under first-touch, last-touch and linear attribution, but **Referral** takes the top spot once a data-driven Markov model accounts for how channels work together. See [the dashboard](#dashboard-v2-complete) for the full breakdown.

---

## Data Quality Finding: Redefining "Conversion"

Before any attribution model can be built, the data has to actually represent what the model assumes it represents. It didn't, out of the box.

**The assumption a naive analysis would make:** each `User ID` represents one journey ending in a single conversion event, and every touchpoint before that conversion should be eligible for attribution credit.

**What the data actually showed:** `Conversion` is flagged per touchpoint, not per journey. Users with a "Yes" on one row frequently had additional touchpoints — including ones occurring chronologically *after* the "Yes" — still logged with the same `User ID`. Manually inspecting one user's full, timestamp-sorted history (`User ID 13186`, 12 touchpoints) confirmed the "Yes" landed mid-sequence (8th of 12), not at the end.

**Why this matters:** left as-is, a model built on this data would attribute conversion credit to touchpoints that happened *after* the conversion they supposedly influenced — which is not logically possible and would produce misleading channel-credit numbers.

**The fix:** journeys were redefined at the point of first conversion.
1. Isolated all rows where `Conversion == "Yes"`.
2. Grouped by `User ID` and identified each converting user's earliest conversion timestamp (`first_conversion_time`).
3. Merged that timestamp back onto the full dataset.
4. Filtered to only the touchpoints occurring at or before each user's `first_conversion_time`.
5. Users with no conversion at all were excluded from this stage — with no conversion event, there's no credit to assign for the first three models (though, as it turns out, they become essential again for the fourth — see below).

This produced a clean journeys table: **3,860 touchpoint rows across 2,381 converting users** (~1.6 touchpoints per journey on average — a signal worth carrying into the modeling stage, since short journeys mean first-touch and last-touch will frequently agree, and the data-driven model's value will show up more clearly on the longer journeys).

---

## Database Design

Cleaned data was exported to `journeys_clean.csv` and loaded into a dedicated PostgreSQL database (`Attribution_Analytics`), keeping this project fully separate from other portfolio databases.

**Table: `journeys`**

| Column | Type | Notes |
|---|---|---|
| `touchpoint_id` | `SERIAL PRIMARY KEY` | Auto-incrementing row identifier |
| `user_id` | `INT` | |
| `touchpoint_time` | `TIMESTAMP` | Named to avoid colliding with the reserved word `timestamp` |
| `channel` | `VARCHAR(25)` | |
| `campaign` | `VARCHAR(25)` | |
| `conversion` | `TEXT` | "Yes"/"No", per-touchpoint (see finding above) |
| `first_conversion_time` | `TIMESTAMP` | |

Data was loaded with a small Python script (`load_to_postgres.py`) using `psycopg2` to read the CSV and insert each row via parameterized `INSERT` statements, rather than pgAdmin's GUI import or `COPY` — both of which have proven unreliable on Windows in past projects. Load was verified with a row count check (3,860, matching the cleaned CSV) and a manual spot-check of the first few rows.

A second table, **`model_results`**, holds the final output of all four attribution models for the Power BI dashboard:

| Column | Type | Notes |
|---|---|---|
| `result_id` | `SERIAL PRIMARY KEY` | |
| `channel` | `VARCHAR(25)` | |
| `model` | `VARCHAR(25)` | First-touch / Last-touch / Linear / Markov |
| `value` | `NUMERIC` | Holds both whole-number SQL counts and Markov decimal probabilities without losing precision |

Stored in **long format** (one row per channel/model combination, 24 rows total) rather than wide format, since long format is what Power BI needs to build a legend- and axis-based comparison chart without any reshaping inside the tool itself.

### Star Schema (Dashboard v2)

To expand the dashboard beyond a single chart, the database was reorganized into a **star schema**: fact tables in the middle, dimension tables around them.

```
             dim_model
                 │
dim_channel ── model_results
     │
     └──────── fact_touchpoints ── dim_campaign
```

| Object | Kind | Grain / Purpose |
|---|---|---|
| `fact_touchpoints` | Table | One row per touchpoint, **converters and non-converters** (4,854 rows / 2,847 users) |
| `model_results` | Table | One row per channel x model (24 rows) |
| `dim_channel` | View | `SELECT DISTINCT channel` from `fact_touchpoints` (6 rows) |
| `dim_campaign` | View | `campaign` (join key) + `campaign_label` (display name; `-` -> "No Campaign") |
| `dim_model` | Table | `model`, `model_label`, `model_type` (Position-based / Data-driven), `sort_order` |
| `journey_lengths` | View | One row per converter: `user_id`, `journey_length` (touchpoints before first conversion). Standalone summary for the journey-length chart; intentionally not related to other tables |

**Why a new fact table:** the original `journeys` table only contains converters (by design, for Models 1-3). Any conversion-rate calculation on it would always return 100%. `fact_touchpoints` reuses the same `all_journeys` dataset built for the Markov model (exported from `markov_model.py` to `all_journeys.csv` and loaded with `load_fact_touchpoints.py`), so dashboard numbers match the model exactly. Blank `first_conversion_time` values for non-converters are converted to `NULL` during the load.

**Load verification:**

| outcome | touchpoints | users |
|---|---|---|
| Conversion | 3,860 | 2,381 |
| Null | 994 | 466 |
| **Total** | **4,854** | **2,847** |

Overall conversion rate: **83.6%** (2,381 / 2,847).

**Orphan checks:** every relationship key was validated with a `LEFT JOIN` from fact to dimension (e.g. `model_results` -> `dim_model`, `model_results` -> `dim_channel`), confirming no unmatched (NULL) keys before building relationships in Power BI.

**Data note — missing campaigns:** 1,507 of 4,854 touchpoints (31%) have no campaign (`-`), including **every** Direct Traffic touchpoint. This is expected: direct visits (typed URL, bookmark) carry no ad click or UTM tags, so there is no campaign to attribute. It is relabeled "No Campaign" in `dim_campaign` for display, while the original value is kept as the join key.

---

## Model 1-3: Position-Based Attribution (SQL)

A `numbered_touchpoints` VIEW was built on top of `journeys` using a window function:

```sql
ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY touchpoint_time) AS touchpoint_position
```

alongside `MAX(touchpoint_position) OVER (PARTITION BY user_id)` to mark each journey's final position. This one reusable view powers all three position-based models:

- **First-touch** — credit to `touchpoint_position = 1`
- **Last-touch** — credit to `touchpoint_position = max_position`
- **Linear** — credit split evenly across every touchpoint (`SUM(1.0 / max_position)`)

**Results:**

| Channel | First-touch | Last-touch | Linear |
|---|---|---|---|
| Display Ads | 428 | 415 | 424.5 |
| Direct Traffic | 411 | 402 | 405.2 |
| Referral | 408 | 412 | 410.0 |
| Social Media | 389 | 412 | 396.8 |
| Email | 374 | 391 | 381.2 |
| Search Ads | 371 | 349 | 363.3 |

**Finding:** Display Ads leads under all three models, and the overall channel ranking barely shifts between them. This runs counter to the original hypothesis (that model choice would meaningfully redistribute credit) — but it's a more honest result, and a direct consequence of how short the average journey is (~1.6 touchpoints). With that few touchpoints per user, "first" and "last" are frequently the *same* touchpoint. The real test of whether model choice matters shifts to the fourth model, which is structurally capable of detecting something the first three cannot: interaction effects between channels, not just position within a sequence.

---

## Model 4: Data-Driven (Markov Chain Removal Effect)

**The methodological catch:** a removal-effect model asks *"how many conversions would be lost if this channel were removed from the picture entirely?"* Answering that requires seeing both journeys that converted and journeys that didn't — a baseline to measure loss against. Models 1-3 deliberately excluded non-converters as noise; for this model, they're the opposite of noise — they're required.

**The fix:** non-converters were reintroduced for this model only, with each user's full path labeled by outcome:
- Converting users: their touchpoints through first conversion, labeled `"Conversion"`
- Non-converting users: their entire touchpoint history (no truncation point exists), labeled `"Null"`

Verified the split against the full raw dataset before combining: 2,381 converters + 466 non-converters = 2,847 unique users, matching `df['User ID'].nunique()` exactly. Combined into a single `all_journeys` DataFrame (4,854 rows) via `pd.concat()`.

**Building the transition chain:**
1. Sorted `all_journeys` by user and timestamp, then collapsed each user's touchpoints into a single ordered channel list via `groupby().apply(list)`.
2. Appended each user's outcome to the end of their list, and prepended a `"Start"` marker to the front — producing full paths like `[Start, Social Media, Direct Traffic, Email, Conversion]`.
3. Wrote and unit-tested a `get_pairs()` function to break each path into consecutive `(from, to)` transitions.
4. Flattened all 2,847 users' pairs into a single list — **7,701 total transitions**.
5. Counted occurrences of each specific pair, and separately counted total outgoing transitions per starting channel, then combined both into `transition_probs` — a full probability lookup for every channel's complete set of next-step probabilities.

**Investigating the revisit limitation before deciding anything:** `conversion_probability()` (a recursive function walking the chain from `"Start"` to an outcome) needs a `visited` set to prevent infinite recursion on channels that loop back to each other. That safeguard has a side effect — any real path that revisits a channel gets cut off as a dead end, even if the user genuinely converted afterward. Rather than guessing how much this mattered, a diagnostic was run before deciding anything: **425 of 2,847 users (14.9%) have at least one revisit**, and the revisits are fairly evenly spread across channels (Display Ads 90, Email 84, Direct Traffic 81, Referral 75, Social Media 65, Search Ads 62 — roughly 1.5x top-to-bottom, not a dramatic skew). **Decision:** proceed with the existing function rather than rewrite it — the limitation is real but affects a minority of users fairly evenly, so channel-to-channel comparisons should stay valid even though the absolute baseline is a conservative lower bound.

**Two bugs found and fixed during this stage — both worth documenting, since catching them mattered as much as writing the original code:**

1. **In `remove_channel()`** (the function that simulates removing a channel from the chain): `return new_probs` was indented one level too deep, so the function exited after processing only the first channel instead of all of them. Caught by testing the function directly rather than trusting it — `remove_channel("Display Ads", transition_probs)` should have returned 6 channels and only returned 1.
2. **In the original `transition_probs`-building loop** (written two sessions earlier): the line assigning each destination's probability was nested one level too deep inside the "is this a new channel" check, so every channel only ever recorded its *first* destination, silently dropping the rest. This bug had been present since it was first written — the earlier hand-verification (`Search Ads → Conversion` = 0.4556) happened to pass only because that was Search Ads' first-recorded destination, which masked the problem. It surfaced when the Display Ads removal effect came back as exactly `0.0` — a suspiciously clean number that prompted checking `transition_probs["Start"]` directly, which turned out to have only one destination instead of six.

**Corrected baseline conversion probability, after both fixes: 0.7147 (~71.5%)** — much closer to the raw converter ratio (2,381 / 2,847 ≈ 83.6%), with the remaining gap consistent with the documented revisit limitation above rather than an unexplained discrepancy.

**Full removal-effect results:**

| Channel | Removal Effect |
|---|---|
| Referral | 0.1776 |
| Social Media | 0.1719 |
| Display Ads | 0.1702 |
| Direct Traffic | 0.1682 |
| Email | 0.1635 |
| Search Ads | 0.1564 |

Sanity-checked: the six removal effects sum to ≈1.008, a reasonable figure against the 0.7147 baseline — each removal is an independent "what if this channel vanished" scenario rather than a strict partition of the baseline, so some overlap in the total is expected, not a red flag.

---

## Cross-Model Comparison: The Real Finding

| Rank | First-touch | Last-touch | Linear | Markov Removal Effect |
|---|---|---|---|---|
| 1 | Display Ads (428) | Display Ads (415) | Display Ads (424.5) | **Referral (0.1776)** |
| 2 | Direct Traffic (411) | Referral / Social Media (412, tied) | Referral (410.0) | Social Media (0.1719) |
| 3 | Referral (408) | — | Direct Traffic (405.2) | Display Ads (0.1702) |
| 4 | Social Media (389) | Direct Traffic (402) | Social Media (396.8) | Direct Traffic (0.1682) |
| 5 | Email (374) | Email (391) | Email (381.2) | Email (0.1635) |
| 6 | Search Ads (371) | Search Ads (349) | Search Ads (363.3) | Search Ads (0.1564) |

**This is the project's headline finding.** Display Ads leads all three position-based models — the kind of model most businesses actually run in production. But under the data-driven model, which is the only one of the four that accounts for how channels enable *each other*, not just where they sit in a sequence, **Referral overtakes it**, and Display Ads drops to third.

The practical implication: a business optimizing budget off first-touch, last-touch, or linear attribution alone would be structurally underinvesting in Referral relative to what a model sensitive to channel interaction effects says it's actually contributing. Position-based models can't see this because they only ever ask "where did this touchpoint sit in the sequence" — never "what did this channel make possible for the touchpoints around it." This is the concrete answer to the question the project opened with: attribution model choice *does* meaningfully change which channel looks best — just not in the position-based models alone, and not until the data-driven model is built correctly (see the bug-fixing note above for what "correctly" took to get right).

---

## Module 6: Power BI Dashboard

Since the four models sit on wildly different scales — raw touchpoint counts (350-430) for the SQL models versus small probabilities (0.15-0.18) for the Markov model — a direct value comparison on one chart made the Markov bars visually disappear. Rather than split the results into separate charts, the underlying finding is about **rank**, not raw value, so all four models were normalized onto the same 1-6 scale instead.

A second PostgreSQL view, `model_results_ranked`, was built on top of `model_results` using the same window-function pattern from Module 4:

```sql
CREATE VIEW model_results_ranked AS
SELECT
    channel,
    model,
    value,
    RANK() OVER (PARTITION BY model ORDER BY value DESC) AS rank
FROM model_results;
```

The final dashboard is a clustered bar chart (channel on the Y-axis, rank on the X-axis, model as the legend/color), connected live to this view. It visually confirms the project's headline finding: Search Ads and Email sit flat and consistent (rank 5-6) across all four models — genuinely weak performers with no disagreement between methods — while Display Ads and Referral show the real divergence. Display Ads' bar is visibly shorter under the Markov model (rank 3) than under the other three (rank 1), and Referral's bar is visibly longer under the other three (rank 2-3) than under Markov, where it wins outright (rank 1). A short text summary above the chart states the finding directly, so the dashboard is legible without requiring prior context.

### Dashboard v2 (complete)

The single-chart v1 undersold the underlying work, so the report was rebuilt as a two-page dashboard in a new file, `Attribution_Dashboard.pbix` (v1 is kept in `Analysticss.pbix`). Canvas: 16:9, 1920 x 1080.

**Page 1 — Executive Summary (complete)**

![Executive Summary: KPI cards, Markov shift chart and credit-share matrix](images/executive_summary.png)

- **Title:** "Marketing Attribution: Does the model change the winner?"
- **KPI row (reads left to right, ending on the answer):** Total Users 2,847 -> Converted Users 2,381 -> Conversion Rate 83.6% -> Avg Touchpoints per User 1.70 -> Top Channel (Markov) **Referral**
- **Headline chart — "Modeling channel interactions shifts credit away from Display Ads":** a diverging bar chart of Markov credit share minus the average of the three position-based models, in percentage points. Gains in blue, losses in gray.
- **Detail matrix — "Display Ads leads every position-based model; Referral leads Markov":** credit share by channel x model, with each model's #1 channel highlighted via a conditional-formatting rule driven by a RANKX measure.

**Page 2 — Model Detail: "What's behind the shift?" (complete)**

![Model Detail: conversion rate by channel, Markov removal effects and journey-length distribution](images/model_detail.png)

- **"Conversion rates are similar across channels (78% to 84%)":** conversion rate by channel, from the same `[Conversion Rate]` measure as the KPI card (filter context splits it per channel). Display Ads converts best (84%), Search Ads lowest (78%). Every channel sits *below* the 83.6% overall rate: a user counts in every channel they touched, and non-converters touch more channels, so channel rates overlap and don't average back to the total.
- **"Referral drives the most conversions when channel interactions are modeled":** the raw Markov removal effects at true scale (Referral 0.178 down to Search Ads 0.156). Read next to the first chart, it shows Display Ads converting well on its own but ranking only #3 once interactions are modeled: useful, but more replaceable than Referral.
- **"59% of converters had a single touchpoint, leaving position-based models nothing to disagree on":** a journey-length histogram of converters (1 touchpoint: 1,403 | 2: 630 | 3: 238 | 4: 79 | 5: 21 | 6: 9 | 8: 1). For a one-touchpoint journey, first-touch, last-touch and linear all credit the same channel, which explains why the three position-based models agree so closely and why only the Markov model tells a different story.
- **Page navigator** buttons on both pages.
- **Hover tooltip (report page):** hovering a channel in the Page 1 headline chart shows that channel's credit share under each of the four models, with a dynamic title (`SELECTEDVALUE(dim_channel[channel])`), e.g. "Display Ads: credit share by model".
- **Source footnote** on both pages: dataset, population (2,847 users / 4,854 touchpoints), date range, and the journey and removal-effect definitions.

**Page 2 design decisions:**

- **Journey lengths built in SQL** as a `journey_lengths` view (`GROUP BY user_id` over `journeys`) and verified in pgAdmin (2,381 converters / 3,860 touchpoints) before loading, keeping data shaping in the database alongside the rest of the star schema.
- **Converters only** in the histogram: that's the exact population the position-based models were run on. Including non-converters would invite a misleading comparison, since converter journeys were cut off at first conversion by design.
- **Removed an auto-detected relationship.** Power BI linked `journey_lengths` to `fact_touchpoints` on `user_id`; because the view contains converters only, the link could silently filter non-converters out of other visuals, so it was deleted and the table kept standalone.
- **Removal effects shown with a visual-level filter** (`model_label = Markov`) on the existing `[Credit]` measure rather than a new measure.

**Refined finding — where the credit moves:**

| Channel | Markov shift vs position-based avg (pp) |
|---|---|
| Referral | +0.40 |
| Search Ads | +0.35 |
| Social Media | +0.29 |
| Email | +0.18 |
| Direct Traffic | -0.36 |
| Display Ads | -0.86 |

The losses are concentrated in Display Ads, while the gains are spread across four channels. The shifts sum to zero: attribution models don't create credit, they only move it between channels. The effects are also **small** (every channel's share sits between roughly 15% and 18%), and the dashboard shows that honestly rather than exaggerating it.

**Design decisions:**

- **Diverging "shift" chart instead of a rank or zoomed-axis bar chart.** The finding rests on gaps under one percentage point. A bar chart starting at zero hides them, and a zoomed axis exaggerates them (bars must start at zero to be honest). Plotting the *difference* shows exactly what changes when interactions are modeled, at its true size.
- **Credit share %, not raw values or rank.** Each model's credit is expressed as a % of that model's total (`DIVIDE([Credit], CALCULATE([Credit], ALL(dim_channel)))`), so count-based models and Markov probabilities share one scale.
- **Removed a misleading matrix total.** A row total summing credit across models let the count-based models (hundreds) swamp Markov (decimals, ~1/7,000 of the total), so it was turned off.
- **Rank shown as a highlight, not columns.** Eight value columns overflowed the matrix and cut off the Markov column; the rank now drives the cell highlight instead ("less is more").
- **One population for every KPI.** Avg Touchpoints per User (1.70) includes non-converters, like every other card. Converters alone average 1.62; non-converters average 2.13, but converter journeys were truncated at first conversion, so that gap is partly a data-prep artifact and isn't presented as a behavioral insight.
- **Explicit DAX measures only,** stored in a dedicated `_Measures` table, replacing Power BI's implicit Sum/Average aggregations.
- **No date table or time-intelligence visuals:** the dataset only spans Feb 10-11, 2025, so trend charts would add noise rather than insight.

**DAX measures:** Total Users, Converted Users, Conversion Rate, Avg Touchpoints per User, Credit, Credit Share %, Channel Rank (RANKX, ties skipped like SQL `RANK()`), Markov Share, Position Avg Share (AVERAGEX over the three position-based models), Markov Shift (pp), Top Channel (Markov) (TOPN + MAXX). Every measure was checked against pgAdmin or Python results before being used in a visual.

**Model setup:** 5 tables loaded; 4 one-to-many relationships (single-direction, dimension -> fact) verified; `public` schema prefix removed from table names; fact-table key columns hidden so only the dimension versions can be used in visuals; ID columns set to "Don't summarize"; `model_label` sorted by `sort_order`.

---

## Repository Structure

| Path | What it is |
|---|---|
| `explore_data.py` | Exploration of the raw data: how the per-touchpoint conversion issue was found (User 13186) |
| `clean_journeys.py` | Cleaning pipeline: builds converter journeys (touchpoints up to each user's first conversion) -> `journeys_clean.csv` |
| `markov_model.py` | Data-driven model: Markov chain removal effects; also exports `all_journeys.csv` (converters + non-converters) |
| `load_to_postgres.py` | Loads `journeys_clean.csv` into the `journeys` table |
| `load_fact_touchpoints.py` | Loads `all_journeys.csv` into the `fact_touchpoints` table |
| `test_connection.py` | Read-only check that the PostgreSQL connection works |
| `sql/schema.sql` | Every table and view in the database (schema only, exported with pg_dump) |
| `sql/position_models.sql` | First-touch, last-touch and linear attribution queries |
| `sql/verification_checks.sql` | Row counts, journey-length checks and orphan (LEFT JOIN) checks, with expected results |
| `Attribution_Dashboard.pbix` / `.pdf` | Power BI dashboard (v2) and a PDF export; `Analysticss.pbix` is the original one-chart v1 |
| `images/` | Dashboard screenshots used in this README |

## How to Reproduce

1. **Download the data** from [Kaggle](https://www.kaggle.com/datasets/vivekparasharr/multi-touch-attribution) and save it in the project folder as `multi_touch_attribution_data.csv` (data files aren't stored in this repo).
2. **Install the Python packages:** `pip install pandas psycopg2`
3. **Build the journeys:** `python clean_journeys.py`, then `python markov_model.py` (prints the removal effects and writes `all_journeys.csv`).
4. **Create the database** `Attribution_Analytics` in PostgreSQL and run `sql/schema.sql` to create all tables and views.
5. **Set the database password as an environment variable** (credentials are never stored in the code). On Windows, run `setx PGPASSWORD "your_password"` and open a new terminal.
6. **Load the data:** `python load_to_postgres.py` and `python load_fact_touchpoints.py` (run each **once**; they insert rows).
7. **Run the models and checks:** `sql/position_models.sql` for Models 1-3; `sql/verification_checks.sql` to confirm counts. The final results in `model_results` (24 rows) and the `dim_model` lookup (4 rows) were entered from these outputs.
8. **Open** `Attribution_Dashboard.pbix` in Power BI Desktop and point the PostgreSQL connection at your server (`localhost`).

---

## Progress

**Module 1 — Environment Setup:** Complete
**Module 2 — Data Cleaning & Journey Construction:** Complete
**Module 3 — Load to PostgreSQL:** Complete
**Module 4 — SQL Analysis & Position-Based Model Comparison:** Complete
**Module 5 — Data-Driven Model (Markov Chain):** Complete
**Module 6 — Power BI Dashboard:** v1 complete (single chart); v2 two-page dashboard (Executive Summary + Model Detail) complete

**Project status: Analysis and dashboard complete. Remaining: repo cleanup before publishing (tidy exploration script, dashboard screenshots). Database credentials are read from the `PGPASSWORD` environment variable; none are stored in the code.**

---

## Why This Approach

This project is intentionally scoped around a judgment call, not just a technique demonstration. Anyone can run four attribution formulas against clean data. The more useful skill — the one this README is meant to surface — is recognizing when the data doesn't mean what its column names imply, catching when an earlier cleaning decision needs to be selectively reversed for a later model, running a real diagnostic instead of guessing when a function's own safeguards introduce a bias, and tracing a suspicious result (an exact `0.0`) back through the pipeline until the actual root cause — a silent bug two sessions old — was found and fixed, rather than accepting a plausible-looking number at face value.
