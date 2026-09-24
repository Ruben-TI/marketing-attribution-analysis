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
print("Connected successfully!")
with open("journeys_clean.csv", "r") as file:
    reader = csv.reader(file)
    header = next(reader)
    for row in reader:
        cursor.execute(
            "INSERT INTO journeys (user_id, touchpoint_time, channel, campaign, conversion, first_conversion_time) VALUES (%s, %s, %s, %s, %s, %s)",
        row
    )  # Skip the header row
conn.commit()
print("Data loaded successfully!")