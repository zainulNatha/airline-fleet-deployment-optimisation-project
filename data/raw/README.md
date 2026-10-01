# Raw Data

This folder documents the source datasets used in the **Airline Fleet Deployment Analysis** project.

The project combines U.S. airline operational data, aircraft reference data, airport information, United Airlines fleet information and aircraft operating-economics data.

The analytical scope is:

- **Airline:** United Airlines
- **Year:** 2025
- **Geography:** U.S. domestic nonstop routes
- **Fleet:** United mainline fleet
- **Demand frequency:** Monthly
- **Economics frequency:** Quarterly

---

## Required Source Files

The project uses six source datasets.

| File | Source | Purpose |
|---|---|---|
| `T_T100_SEGMENT_ALL_CARRIER.csv` | U.S. Bureau of Transportation Statistics (BTS) | Passenger demand, seats, departures, aircraft type, route distance and airborne time |
| `T_AIRCRAFT_TYPES.csv` | U.S. Bureau of Transportation Statistics (BTS) | Reference table for BTS aircraft type codes |
| `T_F41SCHEDULE_P52.csv` | U.S. Bureau of Transportation Statistics (BTS) | Quarterly aircraft fuel, maintenance and operating-cost information |
| `airports.csv` | OurAirports | Airport names, country information and geographic coordinates |
| `united_fleet_2025_raw.csv` | Project reference dataset compiled from public fleet information | United mainline aircraft types, fleet counts and seating configurations |
| `aircraft_range_raw.csv` | Project reference dataset compiled from manufacturer/public aircraft information | Reference aircraft range by fleet type |

---

# Expected Local Folder Structure

To reproduce the project, place the source files in:

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

The SQL `BULK INSERT` paths may need to be changed depending on where the repository is stored on your machine.

---

# 1. BTS T-100 Segment Data

**File**

```text
T_T100_SEGMENT_ALL_CARRIER.csv
```

**Source**

U.S. Bureau of Transportation Statistics — T-100 Segment data.

**Purpose**

This is the main operational dataset used to measure passenger demand and route activity.

The project uses fields including:

- Scheduled departures
- Performed departures
- Seats
- Passengers
- Route distance
- Air time
- Carrier information
- Origin airport
- Destination airport
- Aircraft type
- Year
- Quarter
- Month
- Service class

The data is filtered in the Silver layer to:

```text
United Airlines
2025
```

The Gold analytical layer later restricts the analysis to U.S. domestic routes.

---

## Important T-100 Grain Note

The raw T-100 dataset can contain multiple rows that appear to describe the same:

```text
Month
+ Origin
+ Destination
+ Aircraft Type
```

These rows are not automatically treated as duplicates.

They can represent separate groups of operational activity and therefore need to be aggregated before route-level analysis.

For this reason:

```text
Passengers
Seats
Departures
Air Time
```

are treated as additive measures.

Route distance is not additive.

The Silver layer therefore creates a consistent monthly route-aircraft analytical grain.

---

# 2. BTS Aircraft Types

**File**

```text
T_AIRCRAFT_TYPES.csv
```

**Source**

U.S. Bureau of Transportation Statistics.

**Purpose**

Provides descriptions for BTS aircraft type identifiers used in operational and economics datasets.

The table is used to help interpret aircraft codes appearing in:

```text
T-100 Segment
Form 41 Schedule P-5.2
```

---

# 3. BTS Form 41 Schedule P-5.2

**File**

```text
T_F41SCHEDULE_P52.csv
```

**Source**

U.S. Bureau of Transportation Statistics — Form 41 Schedule P-5.2.

**Purpose**

Provides quarterly aircraft-type operating economics.

The project uses information including:

- Fuel expense
- Flying operations expense
- Direct maintenance expense
- Flight maintenance expense
- Total air operating expense
- Total air hours
- Aircraft days assigned
- Fuel issued
- Aircraft type
- Carrier
- Region
- Year
- Quarter

The Silver layer filters the source to:

```text
Carrier = United Airlines
Year = 2025
Region = Domestic
```

and excludes generic aircraft code:

```text
999
```

---

## BTS `(000)` Units

Several P-5.2 fields are reported in thousands.

For example:

```text
Fuel expense (000)
Operating expense (000)
Air hours (000)
Fuel issued (000)
```

The Silver layer converts these totals into normal units before storing the cleaned analytical data.

Derived metrics include:

```text
Fuel Gallons per Air Hour
Fuel Cost per Air Hour
Operating Cost per Air Hour
Maintenance Cost per Air Hour
```

---

## Economics Interpretation

The economics data represents:

```text
Carrier
+ Aircraft Type
+ Quarter
+ Region
```

It does **not** represent the exact operating cost of an individual flight or route.

The project therefore uses these values as aircraft comparison metrics rather than exact route-accounting costs.

---

# 4. OurAirports Data

**File**

```text
airports.csv
```

**Source**

OurAirports.

**Purpose**

Used to enrich operational airport codes with:

- Airport name
- Country
- Latitude
- Longitude

This supports:

- U.S. domestic route filtering
- Airport display names
- Geographic route mapping in Power BI

---

## Airport Code Reconciliation

Source datasets do not always use airport identifiers consistently.

For example, the project identified a mismatch involving:

```text
PBI
```

The Bronze layer preserves the source value.

The Silver layer creates a separate analysis airport code where required so that operational data can be matched correctly without overwriting the original source value.

---

# 5. United Fleet Reference

**File**

```text
united_fleet_2025_raw.csv
```

**Purpose**

Provides the United mainline fleet used for candidate aircraft comparison.

Information includes:

- Aircraft type
- Fleet count
- Minimum seating capacity
- Maximum seating capacity

The project contains:

```text
19 United mainline aircraft types
```

representing approximately:

```text
1,066 aircraft
```

in the fleet reference used for the project.

This dataset was compiled as a project reference dataset using publicly available fleet information.

It should not be interpreted as an official United Airlines internal fleet-planning dataset.

---

# 6. Aircraft Range Reference

**File**

```text
aircraft_range_raw.csv
```

**Purpose**

Provides manufacturer/public reference range information for each United fleet type.

The project contains range information for:

```text
19 aircraft types
```

Range values are stored in nautical miles and converted where required for comparison with T-100 route distance.

The Gold layer uses:

```text
1 nautical mile ≈ 1.15078 statute miles
```

---

## Range Interpretation

Aircraft reference range is used only as a high-level route feasibility check.

It does not account for:

- Payload
- Weather
- Winds
- Reserve fuel
- Airport altitude
- Runway performance
- Airline-specific operating restrictions
- Route-specific aircraft configuration

It should therefore not be interpreted as an exact operational range calculation.

---

# Aircraft Mapping

Aircraft identifiers differ between the source datasets.

For example:

```text
United Fleet Name
BTS Aircraft Type ID
BTS Aircraft Description
```

may all identify the same aircraft differently.

The Silver layer therefore creates:

```text
silver.aircraft_mapping
```

to explicitly connect aircraft across sources.

This is safer than attempting to join datasets using aircraft-name text alone.

---

# Boeing 777-200 Family Limitation

One important source limitation involves BTS aircraft type:

```text
627
```

which represents a broader Boeing 777-200 family classification.

The United fleet reference separately identifies:

```text
777-200
777-200ER
```

The BTS source does not provide sufficient detail to confidently determine which United subtype the economics belong to.

The project therefore does **not** force an exact economics mapping for these two variants.

This prevents false precision being introduced into the analysis.

---

# Why Raw CSV Files May Not Be Stored in the Main Repository

Some source datasets are relatively large.

For example, the T-100 Segment file used in the project is approximately:

```text
100 MB
```

Large raw files are therefore excluded from the normal Git repository using `.gitignore`.

This keeps the repository lightweight and avoids unnecessary duplication of publicly available source data.

The repository instead documents:

- Required filenames
- Source purpose
- Expected folder structure
- Transformation logic
- SQL scripts used to process the data

A separate reproducibility data snapshot may also be provided through a GitHub Release in the future.

---

# Reproducing the Analysis

Once the six files are available locally:

### 1. Initialise the database

Run:

```text
scripts/01_init_database.sql
```

### 2. Build and load Bronze

Run:

```text
scripts/bronze/02_ddl_bronze.sql
scripts/bronze/03_proc_load_bronze.sql
scripts/bronze/04_bronze_quality_checks.sql
```

### 3. Build Silver

Run:

```text
scripts/silver/05_ddl_silver.sql
scripts/silver/06_proc_load_silver.sql
scripts/silver/07_silver_quality_checks.sql
```

### 4. Build Gold

Run:

```text
scripts/gold/08_gold_model.sql
scripts/gold/09_gold_quality_checks.sql
scripts/gold/10_route_suitability_analysis.sql
```

More detailed explanations of the transformations are available in the README contained within each Medallion layer.

---

# Data Usage Note

This project is an independent educational and portfolio project.

Public/reference source data is used to demonstrate:

- SQL
- Data engineering
- Data modelling
- Data quality
- Analytical reasoning
- Power BI

The project is not affiliated with or endorsed by United Airlines, the U.S. Bureau of Transportation Statistics or OurAirports.

Users reproducing the project should also review the terms and usage guidance provided by the original source providers.
