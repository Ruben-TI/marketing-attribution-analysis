"""
Model 4: data-driven attribution with a Markov chain (removal effect).

Each user's journey becomes a path: Start -> channel -> ... -> outcome,
where outcome is "Conversion" or "Null" (did not convert). From all paths
we estimate the probability of moving from one step to the next, then ask
for each channel: how much does the overall conversion probability drop
if this channel is removed? That drop is the channel's removal effect.

Unlike Models 1-3, this needs non-converters too (a removal effect is
measured against a baseline that includes users who never convert).

Known limitation (documented in the README): conversion_probability()
treats a revisited channel as a dead end, so the baseline is a
conservative lower bound. The revisit diagnostic below shows this affects
~15% of users, spread evenly across channels, so channel-to-channel
comparisons remain valid.
"""
from collections import Counter

import pandas as pd

RAW_FILE = "multi_touch_attribution_data.csv"  # source data: read-only
JOURNEYS_FILE = "journeys_clean.csv"           # converters (clean_journeys.py)
EXPORT_FILE = "all_journeys.csv"               # loaded into fact_touchpoints
CHANNELS = ["Display Ads", "Direct Traffic", "Referral",
            "Social Media", "Email", "Search Ads"]


# 1. Combine converters and non-converters --------------------------------
df = pd.read_csv(RAW_FILE)
journeys_clean = pd.read_csv(JOURNEYS_FILE)

# Non-converters: users who never appear in the converter journeys
non_converters = df[~df["User ID"].isin(journeys_clean["User ID"])].copy()

journeys_clean["outcome"] = "Conversion"
non_converters["outcome"] = "Null"

all_journeys = pd.concat([journeys_clean, non_converters])
all_journeys = all_journeys.sort_values(["User ID", "Timestamp"])
all_journeys.to_csv(EXPORT_FILE, index=False)  # loaded into fact_touchpoints


# 2. One path per user: Start -> channels -> outcome ----------------------
sequences = all_journeys.groupby("User ID")["Channel"].apply(list)
outcomes = all_journeys.groupby("User ID")["outcome"].first()
paths = (sequences + outcomes.apply(lambda x: [x])).apply(lambda seq: ["Start"] + seq)


# 3. Transition probabilities ---------------------------------------------
def get_pairs(seq):
    """Consecutive (from, to) steps in one path."""
    return [(seq[i], seq[i + 1]) for i in range(len(seq) - 1)]


all_pairs = [pair for path in paths for pair in get_pairs(path)]
pair_counts = Counter(all_pairs)
from_counts = Counter(from_step for from_step, _ in all_pairs)

# transition_probs[from][to] = P(next step is `to` | current step is `from`)
transition_probs = {}
for (from_step, to_step), count in pair_counts.items():
    transition_probs.setdefault(from_step, {})[to_step] = count / from_counts[from_step]


# 4. Probability of reaching Conversion from a given step -----------------
def conversion_probability(current, probs, visited=None):
    """Walk every path forward from `current`, weighting by probability.

    `visited` stops infinite loops (A -> B -> A ...). Side effect: a path
    that revisits a channel is cut off there (see known limitation above).
    """
    if visited is None:
        visited = set()
    if current == "Conversion":
        return 1.0
    if current == "Null" or current in visited or current not in probs:
        return 0.0
    visited = visited | {current}
    return sum(p * conversion_probability(nxt, probs, visited)
               for nxt, p in probs[current].items())


baseline = conversion_probability("Start", transition_probs)


# 5. Diagnostic: how many users revisit a channel? ------------------------
def get_revisits(seq):
    """Channels that appear more than once in a path (Start/outcome excluded)."""
    counts = Counter(seq[1:-1])
    return {channel: c for channel, c in counts.items() if c > 1}


revisits = paths.apply(get_revisits)
users_with_revisits = (revisits.apply(len) > 0).sum()


# 6. Removal effects ------------------------------------------------------
def remove_channel(channel_to_remove, probs):
    """Copy of `probs` where every step into the removed channel goes to Null."""
    new_probs = {}
    for from_step, destinations in probs.items():
        if from_step == channel_to_remove:
            continue
        new_destinations = {}
        for to_step, p in destinations.items():
            if to_step == channel_to_remove:
                new_destinations["Null"] = new_destinations.get("Null", 0) + p
            else:
                new_destinations[to_step] = p
        new_probs[from_step] = new_destinations
    return new_probs


removal_effects = {
    channel: baseline - conversion_probability("Start", remove_channel(channel, transition_probs))
    for channel in CHANNELS
}


# 7. Summary --------------------------------------------------------------
n_users = len(paths)
n_converters = (outcomes == "Conversion").sum()
print(f"Users: {n_users:,} ({n_converters:,} converters, {n_users - n_converters:,} non-converters)")
print(f"Transitions: {len(all_pairs):,}")
print(f"Baseline conversion probability: {baseline:.4f}")
print(f"Users with a revisited channel: {users_with_revisits:,} "
      f"({users_with_revisits / n_users:.1%}) - see known limitation")
print("\nRemoval effect by channel:")
for channel, effect in sorted(removal_effects.items(), key=lambda kv: kv[1], reverse=True):
    print(f"  {channel:<15}{effect:.4f}")
print(f"Sum of removal effects: {sum(removal_effects.values()):.3f}")
