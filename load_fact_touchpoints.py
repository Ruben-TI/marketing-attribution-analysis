import csv
import os
import psycopg2

conn = psycopg2.connect(
    dbname="Attribution_Analytics",
    user="postgres",
    password=os.environ["PGPASSWORD"],
    host="localhost"
)
cursor = conn.cursor()

with open("all_journeys.csv", "r", newline="") as file:
    reader = csv.reader(file)
    next(reader)  # skip the header row
    for row in reader:
        row = [None if value == "" else value for value in row]  # blank -> NULL
        cursor.execute(
            "INSERT INTO fact_touchpoints (user_id, touchpoint_time, channel, campaign, "
            "conversion, first_conversion_time, outcome) "
            "VALUES (%s, %s, %s, %s, %s, %s, %s)",
            row
        )

conn.commit()
print("Loaded!")