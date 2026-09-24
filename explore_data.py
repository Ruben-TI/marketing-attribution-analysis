"""
Exploration of the raw Multi-Touch Attribution dataset (Module 2).

Kept as a record of HOW the key data-quality issue was found.
The reproducible cleaning pipeline lives in clean_journeys.py.

Finding: `Conversion` is tagged per TOUCHPOINT, not per journey.
User 13186's timestamp-sorted history shows "Yes" on a touchpoint
followed by more touchpoints, so a journey was redefined as every
touchpoint up to and including a user's FIRST conversion.
"""
import pandas as pd

df = pd.read_csv("multi_touch_attribution_data.csv")  # read-only source

# 1. Structure: columns, types, missing values
print(df.head())
df.info()

# 2. Which users have the most touchpoints?
print(df["User ID"].value_counts().head(10))

# 3. Inspect one heavy user in time order.
#    Conversion = "Yes" appears mid-history, with touchpoints after it
#    -> conversion is per touchpoint, not per journey.
print(df[df["User ID"] == 13186].sort_values("Timestamp"))

# 4. Preview each user's first conversion (the rule clean_journeys.py uses)
first_conversions = (
    df[df["Conversion"] == "Yes"]
    .sort_values("Timestamp")
    .groupby("User ID")
    .first()
)
print(first_conversions.head())
print(f"Users with at least one conversion: {len(first_conversions):,}")
