import duckdb
import os

con = duckdb.connect("pricesense.db")
sql_folder = "Code files"

files = sorted(f for f in os.listdir(sql_folder) if f.endswith(".sql"))
print(f"Found {len(files)} SQL files.\n")

for file in files:
    path = os.path.join(sql_folder, file)
    print(f"Running {file}...")
    try:
        with open(path, "r", encoding="utf-8") as f:
            con.execute(f.read())
        print("SUCCESS\n")
    except Exception as e:
        print("FAILED\n")
        print(e)
        print("-" * 80)

print("All files processed.")
