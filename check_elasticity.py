import pandas as pd

df = pd.read_csv("final_recommendations.csv")

print("\nELASTICITY CLASSES")
print(df["elasticity_class"].value_counts())

print("\nACTIONS")
print(df["action"].value_counts())

print("\nRISK LEVELS")
print(df["risk_level"].value_counts())

print("\nELASTICITY SUMMARY")
print(df["elasticity"].describe())