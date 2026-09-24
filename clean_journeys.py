"""
Build converter journeys from the raw Multi-Touch Attribution dataset.

Conversion in the raw data is tagged per touchpoint, not per journey
(see explore_data.py, User 13186). So a journey is defined as every
touchpoint up to and including a user's FIRST conversion.
Non-converters are excluded here (Models 1-3 only use converters).
"""
import pandas as pd

RAW_FILE = "multi_touch_attribution_data.csv"   # source data: read-only
OUTPUT_FILE = "journeys_clean.csv"             # cleaned converter journeys

# 1. Load raw data
df = pd.read_csv(RAW_FILE)

# 2. Find each user's first conversion time
first_conversions = (
    df[df["Conversion"] == "Yes"]
    .sort_values("Timestamp")
    .groupby("User ID")
    .first()
    .reset_index()
    .rename(columns={"Timestamp": "first_conversion_time"})
    [["User ID", "first_conversion_time"]]
)

# 3. Attach it to every touchpoint (inner merge drops non-converters)
merged = pd.merge(df, first_conversions, on="User ID")
merged["Timestamp"] = pd.to_datetime(merged["Timestamp"])
merged["first_conversion_time"] = pd.to_datetime(merged["first_conversion_time"])

# 4. Keep touchpoints up to and including the first conversion
journeys = merged[
    merged["first_conversion_time"].notna()
    & (merged["Timestamp"] <= merged["first_conversion_time"])
]

# 5. Save + one sanity-check line
journeys.to_csv(OUTPUT_FILE, index=False)
print(f"Saved {len(journeys):,} touchpoints / "
      f"{journeys['User ID'].nunique():,} users to {OUTPUT_FILE}")