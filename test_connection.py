import os
import psycopg2

conn = psycopg2.connect(
    dbname="Attribution_Analytics",
    user="postgres",
    password=os.environ["PGPASSWORD"],
    host="localhost"
    )
print("Connected using env var!")
conn.close()