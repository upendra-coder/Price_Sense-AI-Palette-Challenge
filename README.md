# PriceSense (simplified)

A pricing-recommendation pipeline: raw transactions + product/customer/competitor
data → per-product price elasticity → a price recommendation with projected
revenue impact.

## What changed from the original


| File | What it does |
|---|---|
| `01_clean_and_model.sql` | Cleans the 5 raw tables and builds `master_view`, the single joined view everything else reads from. |
| `02_elasticity.sql` | The real modeling step: per-product price elasticity of demand, using outlier-trimmed, quantile-banded, log-log arc elasticity — saved as a **table** so it's computed once. |
| `03_insights.sql` | One useful query per theme (category performance, persona spend, geography, occasions, competitor benchmark), condensed. |
| `04_recommendation_engine.sql` | Reads the elasticity table (doesn't recompute it), applies a demand-cliff cap and a few additive context bonuses, and outputs a recommended price with projected revenue/volume impact. |



## Running it

```
pip install duckdb pandas
python setup_db.py       # loads CSVs into pricesense.db
python run_file.py        # runs the 4 SQL files in order
python export_results.py  # writes final_recommendations.csv
python check_elasticity.py  # sanity-checks the distribution of outputs
```

## Output columns (`final_recommendations.csv`)

`product_id`, `category`, `current_price`, `recommended_price`,
`price_change_pct`, `revenue_impact`, `expected_units`, `elasticity`,
`elasticity_class`, `demand_cliff_price`, `action`, `risk_level`.
