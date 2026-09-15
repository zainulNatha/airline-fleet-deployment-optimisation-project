# Raw Data Sources

Raw source datasets used by this project are not stored directly in this repository.

The project uses the following files locally:

| File | Purpose |
|---|---|
| `T_T100_SEGMENT_ALL_CARRIER.csv` | BTS T-100 route, passenger, capacity and aircraft data |
| `T_AIRCRAFT_TYPES.csv` | BTS aircraft type lookup |
| `united_fleet_2025_raw.csv` | United Airlines mainline fleet reference |
| `airports.csv` | Airport reference data including geographic coordinates |
| `aircraft_range_raw.csv` | Aircraft manufacturer range reference |

The files are loaded into SQL Server through the Bronze-layer ingestion procedure.

## Local Folder Structure

```text
data/
└── raw/
    ├── T_T100_SEGMENT_ALL_CARRIER.csv
    ├── T_AIRCRAFT_TYPES.csv
    ├── united_fleet_2025_raw.csv
    ├── airports.csv
    └── aircraft_range_raw.csv
