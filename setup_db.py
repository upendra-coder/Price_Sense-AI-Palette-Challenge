import duckdb

con = duckdb.connect("pricesense.db")

con.execute("""
CREATE OR REPLACE TABLE transactions AS
SELECT * FROM read_csv_auto('Dataset/transactions.csv');

CREATE OR REPLACE TABLE product_metadata AS
SELECT * FROM read_csv_auto('Dataset/product_metadata.csv');

CREATE OR REPLACE TABLE consumer_insights AS
SELECT * FROM read_csv_auto('Dataset/consumer_insights.csv');

CREATE OR REPLACE TABLE geography_occasion AS
SELECT * FROM read_csv_auto('Dataset/geography_occasion.csv');

CREATE OR REPLACE TABLE competitor_pricing AS
SELECT * FROM read_csv_auto('Dataset/competitor_pricing.csv');
""")

print("Database created successfully!")