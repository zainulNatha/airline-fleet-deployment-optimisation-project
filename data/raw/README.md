# Raw Data

This folder contains the source datasets used in the **Airline Fleet Deployment Analysis** project.

The project analyses:

- **Airline:** United Airlines
- **Year:** 2025
- **Geography:** U.S. domestic nonstop routes
- **Demand frequency:** Monthly
- **Economics frequency:** Quarterly
- **Fleet:** United mainline aircraft

The raw datasets feed the Bronze layer of the SQL Server Medallion Architecture.

```text
Raw CSV Files
      ↓
   Bronze
      ↓
   Silver
      ↓
    Gold
      ↓
  Power BI
```

---

# Source Datasets

The project uses six source datasets.

| File | Source | Purpose |
|---|---|---|
| `T_T100_SEGMENT_ALL_CARRIER.csv` | U.S. Bureau of Transportation Statistics | Passenger demand, seats, departures, aircraft type, route distance and airborne time |
| `T_AIRCRAFT_TYPES.csv` | U.S. Bureau of Transportation Statistics | BTS aircraft type reference |
| `T_F41SCHEDULE_P52.csv` | U.S. Bureau of Transportation Statistics | Quarterly aircraft fuel, maintenance and operating economics |
| `airports.csv` | OurAirports | Airport names, countries and geographic coordinates |
| `united_fleet_2025_raw.csv` | Project reference dataset | United mainline fleet counts and seating configurations |
| `aircraft_range_raw.csv` | Project reference dataset | Aircraft reference range |

---

# Dataset Availability

Five of the six datasets are included directly in this repository:

```text
T_AIRCRAFT_TYPES.csv
T_F41SCHEDULE_P52.csv
airports.csv
united_fleet_2025_raw.csv
aircraft_range_raw.csv
```

The only dataset not stored directly in GitHub is:

```text
T_T100_SEGMENT_ALL_CARRIER.csv
```

This file is approximately 100 MB and is therefore downloaded separately from the U.S. Bureau of Transportation Statistics.

---

# Downloading the T-100 Dataset

The main operational source used by the project is:

**BTS T-100 Segment (All Carriers)**

Official BTS download page:

https://www.transtats.bts.gov/DL_SelectFields.asp?QO_fu146_anzr=Nv4+Pn44vr45&gnoyr_VQ=FMG

The dataset provides monthly nonstop segment information including:

- Scheduled departures
- Performed departures
- Seats
- Passengers
- Freight
- Mail
- Distance
- Ramp-to-ramp time
- Air time
- Carrier information
- Origin airport
- Destination airport
- Aircraft type
- Year
- Quarter
- Month
- Service class

## Download Steps

1. Open the BTS T-100 Segment download page.
2. Select **2025**.
3. Select/download the fields required by the project.
4. Extract the CSV if the download is supplied as a ZIP file.
5. Rename the file:

```text
T_T100_SEGMENT_ALL_CARRIER.csv
```

6. Place the file inside:

```text
data/raw/
```

The final local folder should contain:

```text
data/
└── raw/
    ├── T_T100_SEGMENT_ALL_CARRIER.csv
    ├── T_AIRCRAFT_TYPES.csv
    ├── T_F41SCHEDULE_P52.csv
    ├── airports.csv
    ├── united_fleet_2025_raw.csv
    └── aircraft_range_raw.csv
```

The large T-100 file is deliberately excluded from Git tracking using `.gitignore`.

---

# 1. BTS T-100 Segment

## File

```text
T_T100_SEGMENT_ALL_CARRIER.csv
```

## Purpose

This is the main operational dataset.

It is used to analyse:

- Passenger demand
- Seats supplied
- Flights operated
- Aircraft type
- Route distance
- Airborne time
- Monthly seasonality

The Silver layer filters the data to:

```text
United Airlines
2025
```

The Gold layer later restricts the analysis to U.S. domestic routes.

---

## Important Grain Note

The raw T-100 dataset can contain multiple rows for the same:

```text
Year
+ Month
+ Origin
+ Destination
+ Aircraft Type
```

These rows are not automatically duplicates.

They can represent separate groups of operational activity.

The Silver layer therefore aggregates them to a consistent monthly analytical grain.

Measures such as:

```text
Passengers
Seats
Departures
Air Time
```

are additive and use `SUM()`.

Route distance is not additive and is not summed across repeated rows.

---

# 2. BTS Aircraft Types

## File

```text
T_AIRCRAFT_TYPES.csv
```

## Purpose

Provides the reference description for BTS aircraft type codes.

It is used to help interpret aircraft identifiers appearing in:

- T-100 operational data
- Form 41 economics data

---

# 3. BTS Form 41 Schedule P-5.2

## File

```text
T_F41SCHEDULE_P52.csv
```

## Purpose

Provides quarterly aircraft-type operating economics.

The project uses fields covering:

- Fuel expense
- Flying operations expense
- Maintenance expense
- Total air operating expense
- Total air hours
- Aircraft days assigned
- Fuel issued
- Aircraft type
- Carrier
- Region
- Year
- Quarter

The Silver layer filters the data to:

```text
United Airlines
2025
Domestic region
```

Generic BTS aircraft type:

```text
999
```

is excluded.

---

## BTS `(000)` Units

Several P-5.2 fields are supplied in thousands.

The Silver layer converts the required totals into normal units before calculating:

```text
Fuel Gallons per Air Hour
Fuel Cost per Air Hour
Operating Cost per Air Hour
Maintenance Cost per Air Hour
```

These economics values are aircraft-type/quarter comparison measures.

They are not exact route-level accounting costs.

---

# 4. OurAirports

## File

```text
airports.csv
```

## Purpose

Used to enrich airport codes with:

- Airport name
- Country
- Latitude
- Longitude

This supports:

- U.S. domestic route filtering
- Airport display names
- Geographic route mapping in Power BI

The Silver layer also performs airport-code reconciliation where required while preserving the original source value.

---

# 5. United Fleet Reference

## File

```text
united_fleet_2025_raw.csv
```

## Purpose

Provides the United mainline fleet used for candidate aircraft comparison.

Information includes:

- Aircraft type
- Fleet count
- Minimum seating capacity
- Maximum seating capacity

The project reference contains:

```text
19 aircraft types
```

and approximately:

```text
1,066 aircraft
```

This is a project reference dataset compiled from publicly available fleet information.

It should not be interpreted as an official internal United Airlines fleet-planning dataset.

---

# 6. Aircraft Range Reference

## File

```text
aircraft_range_raw.csv
```

## Purpose

Provides reference range information for United fleet aircraft.

The project contains range information for:

```text
19 aircraft types
```

Range is supplied in nautical miles.

Where required, Gold converts range using:

```text
1 nautical mile ≈ 1.15078 statute miles
```

for comparison with T-100 route distance.

---

## Range Limitation

Aircraft range is used only as a high-level feasibility check.

It does not account for:

- Payload
- Weather
- Winds
- Reserve fuel
- Airport elevation
- Runway performance
- Airline operating restrictions
- Aircraft-specific configuration

It should not be interpreted as an exact operational range calculation.

---

# Aircraft Mapping

Aircraft names and identifiers differ between datasets.

For example:

```text
United Fleet Name
        ↓
Aircraft Mapping
        ↓
BTS Aircraft Type ID
```

The Silver layer creates:

```text
silver.aircraft_mapping
```

to explicitly connect these different source systems.

This is safer than relying on aircraft-name text alone.

---

# Boeing 777-200 Family Limitation

BTS aircraft code:

```text
627
```

represents the wider Boeing 777-200 family.

The United fleet reference separately identifies:

```text
777-200
777-200ER
```

The public BTS data does not provide enough information to confidently assign the family-level economics to either exact subtype.

The project therefore does not force an exact economics mapping for these aircraft.

This avoids introducing false precision into the analysis.

---

# Reproducing the Project

Once all six files are available locally:

## 1. Initialise the Database

Run:

```text
scripts/01_init_database.sql
```

---

## 2. Build Bronze

Run:

```text
scripts/bronze/02_ddl_bronze.sql
scripts/bronze/03_proc_load_bronze.sql
scripts/bronze/04_bronze_quality_checks.sql
```

---

## 3. Build Silver

Run:

```text
scripts/silver/05_ddl_silver.sql
scripts/silver/06_proc_load_silver.sql
scripts/silver/07_silver_quality_checks.sql
```

---

## 4. Build Gold

Run:

```text
scripts/gold/08_gold_model.sql
scripts/gold/09_gold_quality_checks.sql
scripts/gold/10_route_suitability_analysis.sql
```

The `BULK INSERT` file paths may need to be changed to match the location of the repository on your own machine.

---

# Further Documentation

For additional information see:

- [Main Project README](../../README.md)
- [Data Dictionary](../../docs/data_dictionary.md)
- [Bronze Documentation](../../scripts/bronze/README.md)
- [Silver Documentation](../../scripts/silver/README.md)
- [Gold Documentation](../../scripts/gold/README.md)

---

# Data Usage Note

This is an independent educational and portfolio project.

The datasets are used to demonstrate:

- SQL
- Data engineering
- Data modelling
- Data quality
- Analytical reasoning
- Power BI

The project is not affiliated with or endorsed by United Airlines, the U.S. Bureau of Transportation Statistics or OurAirports.

Users reproducing the project should review the usage guidance provided by the original source providers.
