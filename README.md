# NYC Taxi Rides — dbt Analytics Engineering Project

## Overview

This project implements an analytics engineering pipeline for New York City taxi trip data using dbt (data build tool) and Google BigQuery. It transforms raw yellow and green taxi trip records into a clean, tested, and documented analytical layer ready for business intelligence consumption.

The project was built as part of the [DataTalksClub Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp) — Module 4: Analytics Engineering.

---

## Architecture

```
Raw Sources (BigQuery: nytaxi dataset)
        │
        ▼
Staging Layer (views)
  ├── stg_green_tripdata
  └── stg_yellow_tripdata
        │
        ▼
Core Layer (tables)
  ├── dim_zones          ← built from seed: taxi_zone_lookup.csv
  ├── fact_trips         ← union of green + yellow, joined with dim_zones
  └── dm_monthly_zone_revenue  ← pre-aggregated data mart
```

**Staging** cleans and standardizes raw source data — renaming columns, casting data types, generating surrogate keys, and applying payment type descriptions. No business logic lives here.

**Core** applies business logic — combining green and yellow trips into a unified fact table, enriching location IDs with human-readable zone names, and aggregating revenue metrics into a data mart for BI consumption.

---

## Data Sources

Raw data is loaded into BigQuery via Kestra orchestration pipelines from the [DataTalksClub NYC TLC Data repository](https://github.com/DataTalksClub/nyc-tlc-data/releases).

| Table | Description | Rows |
|---|---|---|
| `nytaxi.green_tripdata` | Green taxi trips, 2019–2020 | ~7.8M |
| `nytaxi.yellow_tripdata` | Yellow taxi trips, 2019–2020 | ~109M |

**Key difference between datasets:** Yellow taxis operate exclusively in Manhattan and can be hailed from the street. Green taxis operate in outer boroughs and cannot pick up street hails in Manhattan. This is why yellow trips lack `trip_type` and `ehail_fee` columns that exist in the green dataset.

---

## Project Structure

```
dbt-taxi-rides-ny/
├── dbt_project.yml          # Project configuration, materializations, variables
├── packages.yml             # dbt package dependencies (dbt_utils)
├── models/
│   ├── staging/
│   │   ├── schema.yml       # Source definitions, model tests, column descriptions
│   │   ├── stg_green_tripdata.sql
│   │   └── stg_yellow_tripdata.sql
│   └── core/
│       ├── schema.yml       # Model tests and column descriptions
│       ├── dim_zones.sql
│       ├── fact_trips.sql
│       └── dm_monthly_zone_revenue.sql
├── macros/
│   └── get_payment_type_description.sql
└── seeds/
    └── taxi_zone_lookup.csv
```

---

## Models

### Staging

#### `stg_green_tripdata`
Cleans and standardizes green taxi trip data from the raw source.

- Generates a surrogate key (`tripid`) using `dbt_utils.generate_surrogate_key`
- Renames columns to consistent naming convention (`lpep_pickup_datetime` → `pickup_datetime`)
- Casts all columns to appropriate data types
- Applies `get_payment_type_description` macro to convert payment type integers to human-readable labels
- Materialized as a **view** (lightweight, always fresh, not queried directly by analysts)

#### `stg_yellow_tripdata`
Same as above for yellow taxi data, with adjustments for schema differences: 

- Uses `tpep_pickup_datetime` / `tpep_dropoff_datetime` instead of `lpep_` prefix
- `trip_type` and `ehail_fee` cast as `NULL` (yellow taxis never have these values)

---

### Core

#### `dim_zones`
Dimension table mapping taxi zone location IDs to human-readable names.

- Built from `taxi_zone_lookup.csv` seed (265 rows, rarely changes)
- Cleans `service_zone` values: replaces 'Boro' with 'Green' for clarity
- Materialized as a **table**

#### `fact_trips`
Central fact table combining all green and yellow taxi trips.

- Unions `stg_green_tripdata` and `stg_yellow_tripdata`
- Adds `service_type` column ('Green' or 'Yellow') to distinguish trip source
- Inner joins with `dim_zones` twice — once for pickup zone, once for dropoff zone
- Filters out trips with unrecognized location IDs (`borough != 'Unknown'`)
- **115M+ rows**
- Materialized as a **table** (queried frequently, must be fast)

#### `dm_monthly_zone_revenue`
Pre-aggregated data mart for revenue analysis by service type, pickup zone, and month.

- Groups `fact_trips` by `service_type`, `pickup_zone`, and month
- Calculates revenue metrics: fare, tips, tolls, surcharges, total amount
- Calculates trip volume: count, average passenger count, average trip distance
- **12,498 rows** — optimized for dashboard consumption
- Materialized as a **table**

---

## Macros

### `get_payment_type_description(payment_type)`
Converts raw payment type integer codes to human-readable descriptions.

| Code | Description |
|---|---|
| 1 | Credit card |
| 2 | Cash |
| 3 | No charge |
| 4 | Dispute |
| 5 | Unknown |
| 6 | Voided trip |

Used in both staging models — written once, applied everywhere (DRY principle).

---

## Seeds

### `taxi_zone_lookup.csv`
Static reference table with 265 rows mapping NYC taxi zone location IDs to zone names, boroughs, and service zones. Loaded directly into BigQuery via `dbt seed`.

Used as the basis for `dim_zones`.

---

## Tests

Data quality tests are defined in `schema.yml` files for staging and core models:

| Test | Column | Models |
|---|---|---|
| `unique` | `tripid` | stg_green_tripdata, stg_yellow_tripdata |
| `not_null` | `tripid` | stg_green_tripdata, stg_yellow_tripdata |
| `relationships` | `pickup_locationid` | stg_green_tripdata, stg_yellow_tripdata |
| `relationships` | `dropoff_locationid` | stg_green_tripdata, stg_yellow_tripdata |
| `accepted_values` | `payment_type_description` | stg_green_tripdata, stg_yellow_tripdata |
| `unique` | `locationid` | dim_zones |
| `not_null` | `locationid` | dim_zones |
| `unique` | `tripid` | fact_trips |
| `not_null` | `tripid` | fact_trips |

All tests use `severity: warn` — failures produce warnings but do not stop the pipeline. Known data quality issues in the NYC TLC dataset include ~12% null `vendorid` values and payment types outside the expected 1–6 range.

---

## Variables

| Variable | Default | Description |
|---|---|---|
| `is_test_run` | `true` | Adds `LIMIT 100` to staging models during development to reduce cost |
| `payment_type_values` | `[1, 2, 3, 4, 5, 6]` | Valid payment type codes, used in accepted_values tests |

To run with full data (production mode):
```bash
dbt run --vars '{"is_test_run": false}'
```

---

## Packages

| Package | Version | Usage |
|---|---|---|
| `dbt-labs/dbt_utils` | 1.3.0 | `generate_surrogate_key` for tripid generation |

Install packages:
```bash
dbt deps
```

---

## Setup

### Prerequisites

- dbt Cloud account (free Developer plan)
- GCP project with BigQuery enabled
- Service account with BigQuery Data Editor, Job User, and User permissions
- Raw taxi data loaded into BigQuery `nytaxi` dataset (see data loading section below)

### Data Loading

Raw data is loaded via Kestra orchestration. The backfill flow `12_mod4_gcp_taxi_backfill` loads all 2019–2020 green and yellow taxi data into the `nytaxi` dataset in BigQuery.

### dbt Cloud Setup

1. Create a new dbt Cloud project named `taxi_rides_ny`
2. Connect to BigQuery using your service account JSON key
3. Set dataset location to `US`
4. Connect to this GitHub repository
5. Set development dataset to `dbt_<your_name>`

### Running the Project

Install dependencies:
```bash
dbt deps
```

Load seed data:
```bash
dbt seed
```

Run all models (development — limited to 100 rows):
```bash
dbt run
```

Run all models (full data):
```bash
dbt run --vars '{"is_test_run": false}'
```

Run tests:
```bash
dbt test
```

Build everything (seed + run + test):
```bash
dbt build --vars '{"is_test_run": false}'
```

---

## Key Design Decisions

**Why views for staging, tables for core?**
Staging models are never queried directly by analysts or BI tools — they're intermediate steps. Views cost nothing to store and always reflect the latest source data. Core models are queried repeatedly and contain 100M+ rows — materializing them as tables makes queries fast and predictable.

**Why an inner join in fact_trips?**
Trips with unrecognized location IDs are excluded. This keeps the fact table clean and ensures every trip can be enriched with zone information. Approximately 1.5M trips (~1.3%) were excluded for this reason.

**Why a data mart instead of querying fact_trips directly?**
`dm_monthly_zone_revenue` pre-aggregates 115M rows into 12,498 rows. A dashboard querying monthly revenue by zone would otherwise scan the entire fact table on every load. The data mart makes that query instant.

---

## Author

Kaleab Gebretsadike   
GitHub: [calebfg](https://github.com/calebfg)
