import duckdb

con = duckdb.connect("pricesense.db")

with open("Code files/04_recommendation_engine.sql", "r", encoding="utf-8") as f:
    sql = f.read()

df = con.execute(sql).fetchdf()
print(df.head())

df.to_csv("final_recommendations.csv", index=False)
print("CSV CREATED")
