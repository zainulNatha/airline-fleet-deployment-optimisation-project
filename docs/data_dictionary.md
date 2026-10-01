# Data Dictionary

This document describes the main database objects used in the **Airline Fleet Deployment Analysis** project.

The project follows a Medallion Architecture:

```text
Bronze
Raw source-aligned tables
        ↓
Silver
Cleaned and standardised tables
        ↓
Gold
Analytical and business-rule views
        ↓
Power BI
Reporting and interactive analysis
```

A key concept throughout the project is **grain**.

> **Grain describes what one row in a table represents.**

Understanding grain is important because it determines how measures such as passengers, seats, departures and costs should be aggregated.

---

# Bronze Layer

The Bronze layer stores the source datasets as close as practical to their original structure.

The purpose of Bronze is:

- Preserve source data
- Avoid unnecessary business transformation
- Allow source profiling
- Provide a reproducible starting point for Silver transformations

---

## `bronze.t100_segment_raw`

### Purpose

Stores raw BTS T-100 Segment operational data.

This is the main source used to analyse:

- Passenger demand
- Seats supplied
- Flights operated
- Aircraft type
- Route distance
- Airborne time

### Source

```text
T_T100_SEGMENT_ALL_CARRIER.csv
```

### Grain

The raw BTS source grain is more detailed than the final analytical grain.

Multiple source rows can exist for the same:

```text
Year
+ Month
+ Origin
+ Destination
+ Aircraft Type
```

These rows are therefore aggregated in Silver rather than treated automatically as duplicates.

### Key Fields

| Column | Description |
|---|---|
| `DEPARTURES_SCHEDULED` | Scheduled departures represented by the source row |
| `DEPARTURES_PERFORMED` | Flights actually performed |
| `PAYLOAD` | Reported payload |
| `SEATS` | Seats supplied |
| `PASSENGERS` | Passengers carried |
| `FREIGHT` | Freight carried |
| `MAIL` | Mail carried |
| `DISTANCE` | Route segment distance |
| `RAMP_TO_RAMP` | Ramp-to-ramp operating time |
| `AIR_TIME` | Airborne time |
| `UNIQUE_CARRIER` | Carrier code |
| `AIRLINE_ID` | BTS airline identifier |
| `UNIQUE_CARRIER_NAME` | Carrier name |
| `ORIGIN_AIRPORT_ID` | BTS origin airport identifier |
| `ORIGIN` | Origin airport code |
| `ORIGIN_CITY_NAME` | Origin city |
| `ORIGIN_STATE_ABR` | Origin state abbreviation |
| `DEST_AIRPORT_ID` | BTS destination airport identifier |
| `DEST` | Destination airport code |
| `DEST_CITY_NAME` | Destination city |
| `DEST_STATE_ABR` | Destination state abbreviation |
| `AIRCRAFT_TYPE` | BTS aircraft type identifier |
| `AIRCRAFT_CONFIG` | Aircraft configuration code |
| `YEAR` | Reporting year |
| `QUARTER` | Reporting quarter |
| `MONTH` | Reporting month |
| `CLASS` | Service class |

### Important Aggregation Rule

The following measures are additive:

```text
Passengers
Seats
Departures
Air Time
```

They are therefore aggregated using `SUM()`.

Route distance is not additive and should not be summed repeatedly across operational rows.

---

## `bronze.aircraft_types_raw`

### Purpose

Stores the BTS aircraft-type reference source.

### Source

```text
T_AIRCRAFT_TYPES.csv
```

### Grain

```text
One row per BTS aircraft type reference record
```

### Key Information

Contains the BTS aircraft type identifier and its corresponding aircraft description.

This table helps interpret aircraft codes appearing in operational and economics data.

---

## `bronze.united_fleet_raw`

### Purpose

Stores the raw United mainline fleet reference used in the project.

### Source

```text
united_fleet_2025_raw.csv
```

### Grain

```text
One row per United fleet aircraft type
```

### Key Information

Includes information such as:

- Aircraft type
- Fleet count
- Minimum seating capacity
- Maximum seating capacity

The source contains 19 United mainline aircraft types in the project scope.

---

## `bronze.airports_raw`

### Purpose

Stores raw airport reference data from OurAirports.

### Source

```text
airports.csv
```

### Grain

```text
One row per airport record
```

### Key Information

Includes airport information used for:

- Airport names
- Country identification
- Latitude
- Longitude
- Geographic mapping

The Silver layer performs airport-code reconciliation where required.

---

## `bronze.aircraft_range_raw`

### Purpose

Stores aircraft reference range information.

### Source

```text
aircraft_range_raw.csv
```

### Grain

```text
One row per United fleet aircraft type
```

### Key Information

Contains:

- Aircraft type
- Reference range

Range is supplied as manufacturer/public reference information and is later used as a high-level route feasibility check.

---

## `bronze.aircraft_operating_cost_raw`

### Purpose

Stores raw BTS Form 41 Schedule P-5.2 aircraft economics data.

### Source

```text
T_F41SCHEDULE_P52.csv
```

### Grain

The raw source contains aircraft economics by reporting dimensions including:

```text
Carrier
+ Region
+ Year
+ Quarter
+ Aircraft Type
```

### Key Fields

| Column | Description |
|---|---|
| `FUEL_FLY_OPS` | Fuel expense for flying operations |
| `TOT_FLY_OPS` | Total flying operations expense |
| `TOT_DIR_MAINT` | Total direct maintenance expense |
| `TOT_FLT_MAINT_MEMO` | Flight maintenance expense |
| `TOT_AIR_OP_EXPENSES` | Total air operating expense |
| `TOTAL_AIR_HOURS` | Total reported air hours |
| `AIR_DAYS_ASSIGN` | Aircraft days assigned |
| `AIR_FUELS_ISSUED` | Fuel issued |
| `AIRCRAFT_CONFIG` | Aircraft configuration |
| `AIRCRAFT_GROUP` | BTS aircraft group |
| `AIRCRAFT_TYPE` | BTS aircraft type identifier |
| `UNIQUE_CARRIER` | Carrier code |
| `UNIQUE_CARRIER_NAME` | Carrier name |
| `REGION` | Operating region |
| `YEAR` | Reporting year |
| `QUARTER` | Reporting quarter |

### Important Note

Several BTS fields use `(000)` units.

The Bronze layer preserves the source representation.

Silver converts relevant totals into normal units and derives per-air-hour economics.

---

# Silver Layer

The Silver layer cleans, standardises and structures Bronze data for reuse.

The purpose of Silver is to create reliable datasets with clear analytical grains.

---

## `silver.united_fleet`

### Purpose

Provides the cleaned United mainline fleet reference.

### Grain

```text
One row per United aircraft type
```

### Key Information

Includes:

- Aircraft type
- Total aircraft
- Minimum seats
- Maximum seats

### Example Business Use

Used to answer:

> Which aircraft are available within the fleet for candidate comparison?

It is also used in Power BI for fleet-level reporting.

---

## `silver.aircraft_types`

### Purpose

Provides a cleaned BTS aircraft-type reference.

### Grain

```text
One row per BTS aircraft type ID
```

### Key Information

Includes:

- BTS aircraft type ID
- Aircraft description / display information

### Example Business Use

Used to translate operational aircraft codes into understandable aircraft descriptions.

---

## `silver.airports`

### Purpose

Provides the cleaned airport reference used for domestic filtering and geographic analysis.

### Grain

```text
One row per airport
```

### Key Information

Includes information such as:

- Source airport code
- Analysis airport code
- Airport name
- Country
- Latitude
- Longitude

### Why Two Airport Codes May Exist

The project preserves the original source code while also allowing a corrected analysis code where source reconciliation is required.

For example, the project identified a mismatch involving:

```text
PBI
```

The source value is retained rather than overwritten.

---

## `silver.aircraft_range`

### Purpose

Provides cleaned reference range for United fleet aircraft.

### Grain

```text
One row per United aircraft type
```

### Key Information

Includes:

- Aircraft type
- Reference range in nautical miles

### Business Use

Used in Gold to determine whether a candidate aircraft passes the high-level route-distance feasibility check.

---

## `silver.aircraft_mapping`

### Purpose

Acts as a bridge between aircraft identifiers used across different source systems.

### Grain

Conceptually:

```text
One mapping record between a United fleet aircraft name
and a BTS aircraft type identifier
```

### Key Information

Includes information such as:

- United aircraft type
- BTS aircraft type ID
- Mapping status

### Example

```text
United Fleet Name
        ↓
Aircraft Mapping
        ↓
BTS Aircraft Type ID
```

This allows fleet data to connect with:

- T-100 operational data
- BTS aircraft reference data
- Form 41 economics

### Mapping Status

Exact mappings are identified so economics are only assigned where the source relationship is defensible.

---

## Boeing 777-200 Mapping Exception

BTS aircraft code:

```text
627
```

represents the Boeing 777-200 family.

The United fleet reference separately contains:

```text
777-200
777-200ER
```

The source data does not provide enough information to confidently assign code 627 economics to one exact variant.

These variants are therefore not given a false exact economics mapping.

---

## `silver.route_aircraft_monthly`

### Purpose

Provides cleaned monthly United route operations by aircraft type.

This is one of the most important Silver tables in the project.

### Grain

```text
ONE ROW
=
YEAR
+ MONTH
+ ORIGIN
+ DESTINATION
+ AIRCRAFT TYPE
```

For example:

```text
January 2025
EWR → SFO
Aircraft Type 627
```

### Key Information

Includes operational measures such as:

- Year
- Month
- Origin
- Destination
- Aircraft type ID
- Scheduled departures
- Performed departures
- Passengers
- Seats
- Route distance
- Air time

### Why This Table Exists

The raw T-100 source can contain multiple rows below the required reporting grain.

Silver aggregates those rows to a reusable monthly analytical grain.

### Aggregation Logic

Additive measures use `SUM()`:

```text
Passengers
Seats
Departures
Air Time
```

Route distance uses an appropriate non-additive aggregation such as `MAX()`.

### Example

If raw source rows contain:

```text
209 passengers
220 passengers
30,480 passengers
```

for the same monthly route-aircraft combination, Silver combines them:

```text
30,909 passengers
```

rather than calculating a simple average of the source rows.

---

## `silver.aircraft_operating_cost`

### Purpose

Provides cleaned United domestic aircraft economics.

### Grain

```text
ONE ROW
=
YEAR
+ QUARTER
+ BTS AIRCRAFT TYPE
```

### Scope

The Silver load retains:

```text
United Airlines
2025
Domestic region
```

Generic BTS aircraft code `999` is excluded.

### Key Columns

| Column | Description |
|---|---|
| `year` | Reporting year |
| `quarter` | Reporting quarter |
| `aircraft_type_id` | BTS aircraft type identifier |
| `total_air_hours` | Converted total airborne hours |
| `aircraft_days_assigned` | Converted aircraft days assigned |
| `fuel_issued_gallons` | Converted fuel issued |
| `fuel_gallons_per_air_hour` | Fuel issued divided by total air hours |
| `fuel_cost_per_air_hour` | Fuel expense divided by total air hours |
| `operating_cost_per_air_hour` | Total air operating expense divided by total air hours |
| `maintenance_cost_per_air_hour` | Maintenance expense divided by total air hours |
| `dwh_create_date` | Warehouse creation timestamp |

Additional converted total expense fields are retained in the table for use in derived calculations.

### Business Use

Provides the economics context used to compare viable candidate aircraft.

These rates should be interpreted as:

```text
United
+ Aircraft Type
+ Quarter
+ Domestic reporting region
```

rather than exact costs for an individual route or flight.

---

# Gold Layer

Gold contains analytical business logic.

Gold objects are implemented as SQL views in this project.

---

## `gold.route_monthly_summary`

### Purpose

Creates the total monthly demand picture for each directional route.

### Grain

```text
ONE ROW
=
YEAR
+ MONTH
+ ORIGIN
+ DESTINATION
```

Aircraft type is deliberately removed from the grain.

### Why Aircraft Is Removed

Candidate aircraft should be compared against:

> Total demand on the route during the month

rather than demand associated with one historically operated aircraft type.

### Key Metrics

Includes:

- Total passengers
- Total seats
- Scheduled departures
- Performed departures
- Route distance
- Total air time
- Average air time per flight
- Passengers per flight
- Seats per flight
- Load factor
- Quarter

### Key Calculations

#### Passengers per Flight

```text
Total Passengers
÷
Performed Flights
```

#### Seats per Flight

```text
Total Seats
÷
Performed Flights
```

#### Load Factor

```text
Total Passengers
÷
Total Seats
```

### Geography

Only U.S. domestic routes are retained by validating both origin and destination against the airport reference.

---

## `gold.route_aircraft_candidates`

### Purpose

Compares every monthly route with every aircraft in United's fleet.

### Grain

```text
ONE ROW
=
ROUTE MONTH
+ CANDIDATE AIRCRAFT
```

More explicitly:

```text
YEAR
+ MONTH
+ ORIGIN
+ DESTINATION
+ CANDIDATE AIRCRAFT
```

### How Candidates Are Generated

A `CROSS JOIN` is used:

```text
Monthly Routes
      ×
United Fleet
```

If there are:

```text
1,000 route-months
```

and:

```text
19 fleet aircraft types
```

the candidate stage creates:

```text
19,000 route-aircraft comparisons
```

before further classification.

### Key Information

Includes:

- Route demand
- Candidate aircraft
- Candidate seating capacity
- Capacity gap
- Expected candidate load factor
- Reference aircraft range
- Range feasibility
- Quarterly economics
- Estimated fuel proxy per flight
- Estimated operating-cost proxy per flight

---

## Expected Candidate Load Factor

```text
Passengers per Flight
÷
Candidate Aircraft Seats
```

This answers:

> If average observed route demand were placed on this candidate aircraft, approximately how full would it appear?

It is a comparison metric rather than a passenger-demand forecast.

---

## Capacity Gap

```text
Candidate Seats
-
Passengers per Flight
```

This shows how much candidate seating capacity remains relative to observed average passenger demand.

---

## Estimated Operating Cost Proxy

The project applies the observed average route airborne time to the candidate aircraft's reported quarterly operating-cost rate.

Conceptually:

```text
Average Route Air Time
×
Candidate Operating Cost per Air Hour
```

This is for comparison only.

It is not exact route-level accounting.

---

## `gold.route_aircraft_suitability`

### Purpose

Applies transparent aircraft suitability rules to every route-aircraft candidate.

### Grain

Same as the candidate view:

```text
ROUTE MONTH
+ CANDIDATE AIRCRAFT
```

### Suitability Categories

```text
Not Suitable for Route Distance
Too Small
Capacity Tight
Good Fit
Potentially Oversized
```

### Classification Logic

| Condition | Result |
|---|---|
| Candidate fails reference range check | Not Suitable for Route Distance |
| Expected load factor > 100% | Too Small |
| Expected load factor > 95% | Capacity Tight |
| Expected load factor >= 75% | Good Fit |
| Expected load factor < 75% | Potentially Oversized |

Range is checked before capacity.

### Important Note

These thresholds are project assumptions.

They are not official United Airlines fleet-planning rules.

---

## `gold.route_aircraft_ranked`

### Purpose

Ranks viable candidate aircraft for every monthly route.

### Grain

```text
ROUTE MONTH
+ VIABLE CANDIDATE AIRCRAFT
```

### Excluded Categories

The ranking excludes:

```text
Too Small
Not Suitable for Route Distance
```

### Ranking Priority

Candidates are prioritised as:

```text
1. Good Fit
2. Capacity Tight
3. Potentially Oversized
```

Within those categories, candidates with smaller capacity gaps are preferred.

### Window Function

Ranking uses:

```sql
DENSE_RANK()
```

partitioned by:

```text
Year
Month
Origin
Destination
```

### Why `DENSE_RANK()`?

If two aircraft have the same:

```text
Suitability priority
+
Capacity gap
```

they can both legitimately receive the same rank.

The model avoids inventing an artificial winner.

### Economics

Economics are retained for comparison but do not determine the candidate ranking.

---

## `gold.route_aircraft_best_fit`

### Purpose

Provides the highest-ranked candidate aircraft for each route-month.

### Filter

Conceptually:

```text
candidate_rank = 1
```

### Grain

Usually:

```text
ROUTE MONTH
+ BEST-FIT AIRCRAFT
```

However, more than one aircraft can exist for a route-month where a genuine rank-1 tie occurs.

### Important Note

This view should therefore not automatically be interpreted as:

```text
exactly one aircraft per route-month
```

`DENSE_RANK()` deliberately preserves legitimate ties.

---

# Power BI Analytical Tables

Power BI imports Gold analytical outputs alongside selected Silver reference tables.

The principal imported datasets include:

```text
gold.route_monthly_summary
gold.route_aircraft_ranked
silver.route_aircraft_monthly
silver.aircraft_types
silver.airports
silver.united_fleet
silver.aircraft_range
silver.aircraft_mapping
silver.aircraft_operating_cost
```

Some tables are renamed within Power BI for readability.

For example:

```text
gold.route_monthly_summary
→
Route Monthly Summary
```

and:

```text
gold.route_aircraft_ranked
→
Aircraft Candidates
```

---

# Power BI Helper Tables

Additional helper and dimension tables are created inside Power BI.

---

## `Routes`

### Purpose

Provides one reusable route dimension.

### Key

```text
Route Key
=
Origin | Destination
```

### Key Information

Includes:

- Origin
- Destination
- Display route
- Origin airport name
- Destination airport name
- Origin coordinates
- Destination coordinates

---

## `Date`

### Purpose

Provides the monthly reporting dimension.

### Grain

```text
One row per month
```

### Key Information

Includes:

- Month start date
- Year
- Quarter
- Month number
- Month name
- Year-month display value

---

## `Route Map Paths`

### Purpose

Supports route-line rendering in Power BI's map visual.

The table contains origin and destination coordinates in the structure required to draw directional route paths.

---

## Measures

A disconnected measure table is used to organise DAX measures such as:

```text
Total Passengers
Performed Flights
Total Seats
Weighted Load Factor
Passengers per Flight
Average Air Time
Fleet KPIs
Aircraft economics measures
```

---

# Key Grain Summary

| Object | Grain |
|---|---|
| `bronze.t100_segment_raw` | Raw BTS T-100 source grain |
| `bronze.aircraft_types_raw` | One BTS aircraft reference record |
| `bronze.united_fleet_raw` | One United fleet aircraft type |
| `bronze.airports_raw` | One airport |
| `bronze.aircraft_range_raw` | One United aircraft type |
| `bronze.aircraft_operating_cost_raw` | Raw Form 41 aircraft economics record |
| `silver.united_fleet` | One United fleet aircraft type |
| `silver.aircraft_types` | One BTS aircraft type |
| `silver.airports` | One airport |
| `silver.aircraft_range` | One United fleet aircraft type |
| `silver.aircraft_mapping` | Aircraft identifier mapping record |
| `silver.route_aircraft_monthly` | Year + Month + Origin + Destination + Aircraft Type |
| `silver.aircraft_operating_cost` | Year + Quarter + BTS Aircraft Type |
| `gold.route_monthly_summary` | Year + Month + Origin + Destination |
| `gold.route_aircraft_candidates` | Route-Month + Candidate Aircraft |
| `gold.route_aircraft_suitability` | Route-Month + Candidate Aircraft |
| `gold.route_aircraft_ranked` | Route-Month + Viable Candidate Aircraft |
| `gold.route_aircraft_best_fit` | Route-Month + Rank-1 Candidate Aircraft |
| Power BI `Routes` | One directional route |
| Power BI `Date` | One month |

---

# Why Grain Matters

Consider the following raw operational rows:

```text
EWR → SFO
January 2025
Aircraft 627

Row 1:      209 passengers
Row 2:      220 passengers
Row 3:   30,480 passengers
```

The correct monthly passenger total is:

```text
209
+ 220
+ 30,480
=
30,909 passengers
```

A simple average of the three rows would not describe monthly demand.

The same principle applies throughout the project:

> Before aggregating a measure, first understand what one row represents.

This is one of the main modelling lessons demonstrated by the project.

---

# Data Dictionary Usage

This document is intended to help:

- Understand the structure of the warehouse
- Identify the grain of each object
- Understand why each table/view exists
- Follow the transformation from raw data to analytical output
- Reproduce the project
- Practise SQL using a realistic data model

For transformation details and SQL implementation, see:

```text
scripts/bronze/README.md
scripts/silver/README.md
scripts/gold/README.md
```
