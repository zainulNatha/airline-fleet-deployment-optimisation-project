# Bronze Layer - Data Profiling & Quality Checks

## Overview

After loading the raw source datasets into the Bronze layer, I carried out a series of data profiling and quality checks before beginning any cleaning or transformation.

The purpose of this stage was to understand the data before making decisions about how the Silver layer should be designed.

The Bronze layer is intended to preserve the source data as close to its original form as possible.

Therefore, unusual values were investigated rather than immediately changed.

The profiling process followed this general approach:

```text
Load Raw Data
      ↓
Understand Source Coverage
      ↓
Check Data Quality
      ↓
Understand Row Grain
      ↓
Test Relationships Between Sources
      ↓
Investigate Failed Matches
      ↓
Document Findings
      ↓
Define Silver Transformations
```

The main profiling SQL is stored in:

```text
04_bronze_quality_checks.sql
```

---

# 1. T-100 Year Coverage

## Check

The first check reviewed which years were contained in the raw T-100 dataset.

```sql
SELECT DISTINCT
    year
FROM bronze.t100_segment_raw
ORDER BY year;
```

## Why this check was performed

The project is focused on United Airlines operations during 2025.

Even though the source file was downloaded for this period, I did not want to assume that the dataset contained only the expected year.

Checking the year coverage first confirms whether an explicit year filter will be required later.

## Reasoning

A data pipeline should validate the contents of a source rather than relying only on the file name or download settings.

For example, if the source unexpectedly contained:

```text
2024
2025
2026
```

then the analysis could accidentally combine multiple years.

## Silver impact

The Silver transformation can explicitly restrict the project to:

```sql
WHERE year = 2025
```

This makes the scope of the project clear and reproducible.

---

# 2. T-100 Carrier Distribution

## Check

The next check identified which airlines were contained in the raw T-100 dataset.

```sql
SELECT
    unique_carrier,
    unique_carrier_name,
    COUNT(*) AS row_count
FROM bronze.t100_segment_raw
GROUP BY
    unique_carrier,
    unique_carrier_name
ORDER BY row_count DESC;
```

## Why this check was performed

The Bronze table contains data for multiple airlines because the raw BTS source was loaded without filtering.

The project itself focuses on United Airlines.

Before filtering the data, I wanted to confirm how United was represented in the source.

United is identified by:

```text
unique_carrier = UA
```

## Reasoning

Filtering should take place in the Silver layer rather than Bronze.

Bronze preserves the original source, while Silver creates the project-specific cleaned dataset.

## Silver impact

The operational Silver dataset will use:

```sql
WHERE unique_carrier = 'UA'
```

---

# 3. United Service Class Distribution

## Check

United records were grouped by the T-100 `class` field.

```sql
SELECT
    class,
    COUNT(*) AS row_count
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
GROUP BY class
ORDER BY row_count DESC;
```

## Result

The following records were identified:

```text
Class   Row Count
-----   ---------
F       53,822
L          881
P          339
```

## Why this check was performed

The project is focused on United's normal scheduled passenger operations.

The `class` field in T-100 represents the type of airline service being reported.

It does not mean passenger cabin classes such as First Class, Business Class or Economy.

The majority of United records were Class `F`, which is the service category relevant to the project.

## Silver impact

The main Silver operational dataset will use:

```sql
WHERE unique_carrier = 'UA'
  AND class = 'F'
```

This keeps the analysis focused on the scheduled operations relevant to passenger demand and aircraft deployment.

---

# 4. Monthly Coverage

## Check

United Class F records were grouped by month.

```sql
SELECT
    month,
    COUNT(*) AS row_count
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
  AND class = 'F'
GROUP BY month
ORDER BY month;
```

## Why this check was performed

Monthly demand is important to this project.

An annual average can hide seasonal changes.

For example:

```text
January     Lower Demand
February    Lower Demand
March       Demand Increases
...
July        Higher Demand
August      Higher Demand
...
```

If one or more months were missing, a Power BI seasonality visual could be misleading.

## Reasoning

The project is not only interested in total annual passenger demand.

It also wants to understand whether an aircraft appears suitable throughout the year or whether demand changes significantly by month.

## Silver impact

Month will remain part of the analytical grain.

The route data will not immediately be aggregated into one annual record.

---

# 5. Zero Performed Departures

## Check

The data was checked for United Class F records where no departures were performed.

```sql
SELECT COUNT(*) AS zero_departure_rows
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
  AND class = 'F'
  AND departures_performed = 0;
```

## Result

```text
64 records
```

were identified where:

```text
departures_performed = 0
```

## Why this check was performed

One of the planned metrics is:

```text
Passengers per Flight
=
Passengers / Departures Performed
```

A calculation cannot divide by zero.

For example:

```text
150 / 0
```

would cause a SQL error.

## Silver impact

Zero departures will need controlled handling.

A calculation can use:

```sql
NULLIF(departures_performed, 0)
```

For example:

```sql
passengers / NULLIF(departures_performed, 0)
```

If `departures_performed` is zero, `NULLIF()` converts the denominator to `NULL`, preventing a divide-by-zero error.

The underlying Bronze record is still preserved.

---

# 6. Negative Value Checks

## Check

Operational measures were checked for unexpected negative values.

```sql
SELECT *
FROM bronze.t100_segment_raw
WHERE departures_performed < 0
   OR seats < 0
   OR passengers < 0
   OR distance < 0;
```

## Why this check was performed

Values such as:

```text
-20 passengers
-5 departures
-500 distance
```

would not make sense for this analysis.

Negative values could indicate source-data problems or ingestion issues.

## Reasoning

Before calculations are built on top of operational measures, basic validity should be checked.

## Silver impact

Any invalid records identified would need to be investigated before entering the analytical layer.

---

# 7. Key Field NULL Checks

## Check

Important fields were tested for missing values.

```sql
SELECT
    SUM(CASE WHEN origin IS NULL THEN 1 ELSE 0 END) AS null_origin,
    SUM(CASE WHEN dest IS NULL THEN 1 ELSE 0 END) AS null_destination,
    SUM(CASE WHEN aircraft_type IS NULL THEN 1 ELSE 0 END) AS null_aircraft_type,
    SUM(CASE WHEN passengers IS NULL THEN 1 ELSE 0 END) AS null_passengers,
    SUM(CASE WHEN seats IS NULL THEN 1 ELSE 0 END) AS null_seats,
    SUM(CASE WHEN distance IS NULL THEN 1 ELSE 0 END) AS null_distance
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
  AND class = 'F';
```

## Why this check was performed

These fields are essential to the project.

For example:

```text
Missing origin
→ Route cannot be identified

Missing destination
→ Route cannot be identified

Missing aircraft type
→ Aircraft suitability cannot be evaluated

Missing passengers
→ Demand cannot be calculated

Missing seats
→ Capacity cannot be calculated

Missing distance
→ Range suitability cannot be evaluated
```

## SQL technique

The query uses conditional aggregation:

```sql
SUM(
    CASE
        WHEN origin IS NULL THEN 1
        ELSE 0
    END
)
```

Each missing value contributes `1`, while every valid value contributes `0`.

The values are then added together.

## SQL skills practised

```text
CASE
SUM
IS NULL
Conditional aggregation
```

---

# 8. United Aircraft Type Codes

## Check

The aircraft type codes used by United were identified.

```sql
SELECT
    aircraft_type,
    COUNT(*) AS row_count
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
  AND class = 'F'
GROUP BY aircraft_type
ORDER BY aircraft_type;
```

## Why this check was performed

T-100 stores aircraft using numerical codes such as:

```text
612
614
627
698
721
838
839
```

These codes are not meaningful to a Power BI user on their own.

They need to be matched to the BTS aircraft reference.

---

# 9. Understanding Data Grain

One of the most important profiling tasks was determining the grain of the T-100 data.

## What is grain?

Grain means:

> What does one row in a table represent?

For the Silver route dataset, the intended grain is:

```text
ONE ROW
=
ONE MONTH
+ ONE ORIGIN
+ ONE DESTINATION
+ ONE AIRCRAFT TYPE
```

For example:

```text
January 2025
EWR → SFO
Aircraft Type 627
```

should ideally appear once in the Silver analytical table.

---

# 10. Checking the Intended Monthly Grain

## Check

The raw data was grouped using the intended Silver grain.

```sql
SELECT
    year,
    month,
    origin,
    dest,
    aircraft_type,
    COUNT(*) AS record_count
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
  AND class = 'F'
GROUP BY
    year,
    month,
    origin,
    dest,
    aircraft_type
HAVING COUNT(*) > 1
ORDER BY record_count DESC;
```

## Why `HAVING COUNT(*) > 1` was used

This asks:

> Are there multiple Bronze rows representing the same year, month, route and aircraft type?

If no duplicates existed at this grain, the query would return no rows.

Instead, multiple combinations appeared more than once.

For example:

```text
2025
January
EWR → SFO
Aircraft Type 627
Record Count = 3
```

## Finding

The Bronze source is more detailed than the monthly route-aircraft grain required for the analysis.

This does not automatically mean the records are incorrect duplicates.

They may represent separate source records that should be combined analytically.

---

# 11. Investigating EWR → SFO Aircraft 627

To understand why three records existed, they were inspected directly.

```sql
SELECT
    year,
    month,
    origin,
    dest,
    aircraft_type,
    aircraft_config,
    departures_scheduled,
    departures_performed,
    passengers,
    seats,
    distance,
    air_time
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
  AND class = 'F'
  AND year = 2025
  AND month = 1
  AND origin = 'EWR'
  AND dest = 'SFO'
  AND aircraft_type = 627;
```

## Result

Three separate Bronze records were returned.

The rows had the same:

```text
Year
Month
Origin
Destination
Aircraft Type
Aircraft Configuration
Distance
```

but different operational totals.

## Finding

These records should not simply be deleted as duplicates.

They contain operational activity that needs to be combined at the analytical level.

---

# 12. Validating the Monthly Aggregation

The records were then aggregated.

```sql
SELECT
    year,
    month,
    origin,
    dest,
    aircraft_type,

    SUM(departures_scheduled) AS departures_scheduled,
    SUM(departures_performed) AS departures_performed,
    SUM(passengers) AS passengers,
    SUM(seats) AS seats,

    MAX(distance) AS distance,

    SUM(air_time) AS air_time

FROM bronze.t100_segment_raw

WHERE unique_carrier = 'UA'
  AND class = 'F'
  AND year = 2025
  AND month = 1
  AND origin = 'EWR'
  AND dest = 'SFO'
  AND aircraft_type = 627

GROUP BY
    year,
    month,
    origin,
    dest,
    aircraft_type;
```

## Result

The three Bronze rows became one monthly analytical row:

| Measure | Result |
|---|---:|
| Scheduled Departures | 126 |
| Performed Departures | 128 |
| Passengers | 30,909 |
| Seats | 35,592 |
| Distance | 2,565 |
| Air Time | 41,954 |

## Why some fields use SUM()

These measures represent activity that accumulates:

```text
Passengers
Seats
Departures
Air Time
```

Therefore they are added together.

For example:

```text
Passengers
209
+ 220
+ 30,480
=
30,909
```

## Why distance uses MAX()

Distance represents a route characteristic.

The route does not become longer because multiple source rows exist.

Adding:

```text
2,565
+ 2,565
+ 2,565
```

would incorrectly produce:

```text
7,695
```

Therefore an appropriate value such as:

```sql
MAX(distance)
```

is retained.

## Silver impact

The intended Silver grain is confirmed as:

```text
One Month
+ One Directional Route
+ One Aircraft Type
```

---

# 13. Why the Route is Directional

The project treats:

```text
EWR → SFO
```

and:

```text
SFO → EWR
```

as different directional routes.

Therefore both `origin` and `dest` remain part of the grain.

---

# 14. Why Month Remains in the Grain

It would be possible to aggregate the entire year into:

```text
2025
EWR → SFO
Aircraft 627
```

but this would remove seasonality.

Keeping month allows Power BI to answer questions such as:

```text
Does this route have higher demand in summer?

Is an aircraft suitable all year?

Does capacity become tight during particular months?
```

Therefore the monthly level was deliberately retained.

---

# 15. Matching Aircraft Codes to the BTS Lookup

## Check

T-100 aircraft codes were matched to the BTS aircraft lookup.

```sql
SELECT DISTINCT
    t.aircraft_type,
    a.ac_typeid,
    a.manufacturer,
    a.long_name,
    a.short_name
FROM bronze.t100_segment_raw AS t

LEFT JOIN bronze.aircraft_types_raw AS a
    ON t.aircraft_type = a.ac_typeid

WHERE t.unique_carrier = 'UA'
  AND t.class = 'F'

ORDER BY t.aircraft_type;
```

## Why this check was performed

T-100 contains values such as:

```text
614
698
838
```

while the aircraft lookup gives these codes meaning.

For example:

```text
614 → Boeing 737-800
698 → Airbus A319
838 → Boeing 737 MAX 8 family
```

This makes the operational data understandable.

---

# 16. Checking for Unmatched Aircraft Codes

## Check

A `LEFT JOIN` was used to identify codes that failed to match.

```sql
SELECT DISTINCT
    t.aircraft_type
FROM bronze.t100_segment_raw AS t

LEFT JOIN bronze.aircraft_types_raw AS a
    ON t.aircraft_type = a.ac_typeid

WHERE t.unique_carrier = 'UA'
  AND t.class = 'F'
  AND a.ac_typeid IS NULL;
```

## Result

```text
0 rows
```

## What this means

Every United aircraft code used in T-100 successfully exists in the BTS aircraft reference.

The join therefore provides full aircraft-code coverage for the United operational data being analysed.

---

# 17. Why a LEFT JOIN Was Used

A normal inner join would only return successful matches.

That could hide problems.

A `LEFT JOIN` keeps every record from the operational data, even if a lookup match does not exist.

Conceptually:

```text
T-100 Aircraft Code
        |
        | LEFT JOIN
        v
Aircraft Reference
        |
        v
Successful match OR NULL
```

Then:

```sql
WHERE a.ac_typeid IS NULL
```

shows only the failures.

This pattern is useful for testing reference-data coverage.

---

# 18. Reviewing the United Fleet Reference

## Check

The United fleet table was inspected.

```sql
SELECT
    aircraft_type,
    total,
    owned,
    leased,
    seats_in_standard_configuration,
    average_age_years
FROM bronze.united_fleet_raw
ORDER BY aircraft_type;
```

## Why this check was performed

The United fleet source will eventually provide information such as:

```text
Aircraft Type
Fleet Size
Owned Aircraft
Leased Aircraft
Seat Capacity
Average Age
```

Before using it, its raw formatting needed to be understood.

---

# 19. United Fleet Cleaning Issue - Em Dash

Some fields contained:

```text
—
```

instead of:

```text
0
```

For example:

```text
leased = —
```

## Why this matters

An em dash is text.

It cannot be directly converted into an integer.

For example:

```sql
CAST('—' AS INT)
```

would fail.

## Silver impact

The Silver layer will convert appropriate dash values to numeric zero before converting the column to a numeric data type.

---

# 20. United Fleet Cleaning Issue - Seat Ranges

Some aircraft have one seating value:

```text
737-800 → 166
```

while others contain ranges:

```text
767-300ER → 167-203

777-200ER → 276-362
```

## Why this matters

A value such as:

```text
167-203
```

cannot be stored directly as a single integer.

It contains two useful values.

## Silver impact

The seating field can be separated into:

```text
seats_min
seats_max
```

For example:

```text
167-203
```

becomes:

```text
seats_min = 167
seats_max = 203
```

A single value:

```text
166
```

can become:

```text
seats_min = 166
seats_max = 166
```

---

# 21. Aircraft Naming Differences Between Sources

The United fleet data and BTS aircraft reference do not always use identical names.

Examples include:

| United Fleet | BTS Aircraft Reference |
|---|---|
| 737 MAX 8 | BOEING B737 MAX 800 |
| 737 MAX 9 | BOEING B737 MAX 900 |
| A319-100 | AIRBUS INDUSTRIE A319 |
| A320-200 | AIRBUS INDUSTRIE A320-100/200 |
| A321neo | AIRBUS INDUSTRIE A321-200N |

## Why this matters

A direct join such as:

```sql
ON fleet.aircraft_type = aircraft.long_name
```

would fail even though both rows refer to the same aircraft family.

## Silver impact

Aircraft names will need to be standardised using a controlled mapping.

This avoids relying on inconsistent text descriptions.

---

# 22. Aircraft Family Ambiguity

Some BTS aircraft codes represent broader aircraft families.

For example, a BTS code may represent a 777-200 family, while United's own fleet table separately reports:

```text
777-200
777-200ER
```

## Why this matters

The analysis should not pretend that the operational data provides greater aircraft-variant detail than it actually does.

## Project decision

Aircraft mappings will be documented transparently.

Where the source only supports a broader family-level match, the analysis will not claim an exact subtype unless it can be supported by the data.

---

# 23. Airport Reference Matching

## Check

United origin airports were matched to the airport reference.

```sql
SELECT DISTINCT
    t.origin,
    a.iata_code,
    a.name AS airport_name,
    a.latitude_deg,
    a.longitude_deg
FROM bronze.t100_segment_raw AS t

LEFT JOIN bronze.airports_raw AS a
    ON t.origin = a.iata_code

WHERE t.unique_carrier = 'UA'
  AND t.class = 'F'

ORDER BY t.origin;
```

## Why this check was performed

The airport reference provides information required later for Power BI, including:

```text
Airport Name
Latitude
Longitude
Municipality
Region
Country
```

Latitude and longitude will support the route map.

---

# 24. Checking for Unmatched Airport Codes

## Check

A `LEFT JOIN` was used to find United airports that could not be matched.

```sql
SELECT DISTINCT
    t.origin
FROM bronze.t100_segment_raw AS t

LEFT JOIN bronze.airports_raw AS a
    ON t.origin = a.iata_code

WHERE t.unique_carrier = 'UA'
  AND t.class = 'F'
  AND a.iata_code IS NULL

ORDER BY t.origin;
```

## Result

One unmatched airport code appeared:

```text
PBI
```

## Important reasoning

This does not immediately prove that the airport is missing.

It only proves:

```text
T-100 origin code
PBI

did not equal any

airports_raw.iata_code
```

The next step was therefore investigation rather than editing the data.

---

# 25. Investigating the Unmatched PBI Airport

## Check

The airport reference was searched using several possible identifiers.

```sql
SELECT *
FROM bronze.airports_raw
WHERE iata_code = 'PBI'
   OR ident = 'KPBI'
   OR name LIKE '%Palm Beach%';
```

## Why several conditions were used

The airport might have failed the IATA-code match but still exist under:

```text
ICAO / Ident code
Airport name
Location
```

This is a useful troubleshooting approach when integrating independent reference datasets.

## Finding

The airport existed in the airport reference under:

```text
ident = KPBI
```

Therefore it was not a missing-airport problem.

---

# 26. Inspecting the KPBI IATA Value

## Check

The exact stored IATA value was inspected.

```sql
SELECT
    ident,
    name,
    iata_code,
    '[' + iata_code + ']' AS iata_with_brackets,
    LEN(iata_code) AS character_length,
    DATALENGTH(iata_code) AS stored_length
FROM bronze.airports_raw
WHERE ident = 'KPBI';
```

## Result

The source contained:

```text
ident = KPBI
iata_code = DJT
```

while the 2025 T-100 data contained:

```text
PBI
```

Therefore the two sources describe the same physical airport using different IATA references.

---

# 27. Why Brackets Were Added Around the Code

This expression was used:

```sql
'[' + iata_code + ']'
```

It does not alter the source value.

It simply makes the beginning and end of the text easier to see.

For example:

```text
[PBI]
```

shows a clean three-character value.

A value containing a trailing space could appear as:

```text
[PBI ]
```

A leading space could appear as:

```text
[ PBI]
```

This is a useful debugging technique when a text-based join unexpectedly fails.

---

# 28. Understanding LEN()

`LEN()` returns the number of characters in a string.

For:

```text
DJT
```

the result is:

```text
3
```

However, SQL Server's `LEN()` does not count trailing spaces.

Therefore:

```text
'PBI '
```

can still appear to have a length of:

```text
3
```

This means `LEN()` alone should not always be relied on when investigating trailing whitespace.

---

# 29. Understanding DATALENGTH()

`DATALENGTH()` returns the number of bytes used to store the value.

The Bronze airport code column uses:

```text
NVARCHAR
```

which normally uses two bytes per character.

Therefore:

```text
DJT
```

uses:

```text
3 characters × 2 bytes
=
6 bytes
```

The observed result was therefore:

```text
LEN = 3
DATALENGTH = 6
```

which was expected.

This helped confirm there was no hidden extra character causing the PBI mismatch.

---

# 30. Reusable Leading and Trailing Space Check

In future datasets, whitespace can be checked using:

```sql
SELECT
    iata_code,
    '[' + iata_code + ']' AS visible_value,
    LEN(iata_code) AS character_length,
    DATALENGTH(iata_code) AS stored_bytes,
    LEN(TRIM(iata_code)) AS trimmed_length
FROM bronze.airports_raw
WHERE iata_code <> TRIM(iata_code);
```

## How it works

`TRIM()` removes spaces from the beginning and end of the text.

The condition:

```sql
WHERE iata_code <> TRIM(iata_code)
```

means:

> Show me values that change when their surrounding spaces are removed.

If the query returns rows, those values contain leading or trailing whitespace.

## Possible Silver cleaning

If appropriate, they can later be standardised using:

```sql
TRIM(iata_code)
```

---

# 31. PBI Reference Mismatch Finding

The investigation showed:

```text
2025 T-100
PBI

Newer Airport Reference
KPBI
IATA = DJT
```

## Finding

The failed join was not caused by:

```text
A missing airport
A trailing space
A leading space
A NULL value
```

Instead it was a reference-data difference between the operational dataset and the newer airport reference.

## Decision

Neither Bronze dataset was changed.

Bronze preserves:

```text
T-100 → PBI
Airport Reference → DJT / KPBI
```

The difference will be reconciled in Silver through a controlled mapping.

Conceptually:

```text
2025 T-100                  Airport Reference
    PBI                         KPBI / DJT
      \                           /
       \                         /
        \                       /
             SILVER MAPPING
                   ↓
        Standard Airport Record
```

This preserves source lineage while allowing the datasets to be integrated.

---

# 32. Checking Both Origins and Destinations

The initial airport check only used `origin`.

A complete route contains both:

```text
Origin
Destination
```

Therefore both sides need to be checked.

## Check

A CTE was created containing every United origin and destination airport.

```sql
WITH united_airports AS
(
    SELECT origin AS airport_code
    FROM bronze.t100_segment_raw
    WHERE unique_carrier = 'UA'
      AND class = 'F'

    UNION

    SELECT dest AS airport_code
    FROM bronze.t100_segment_raw
    WHERE unique_carrier = 'UA'
      AND class = 'F'
)

SELECT
    u.airport_code
FROM united_airports AS u

LEFT JOIN bronze.airports_raw AS a
    ON u.airport_code = a.iata_code

WHERE a.iata_code IS NULL

ORDER BY u.airport_code;
```

---

# 33. Understanding the CTE

This section:

```sql
WITH united_airports AS
(
    ...
)
```

creates a temporary named result set for the query.

It does not permanently create another database table.

The first query takes:

```text
Every United Origin
```

and the second takes:

```text
Every United Destination
```

---

# 34. Why UNION Was Used

`UNION` combines both result sets while removing duplicate values.

Imagine the origin data contains:

```text
EWR
SFO
ORD
EWR
```

and destinations contain:

```text
SFO
DEN
EWR
```

After `UNION`, the result becomes:

```text
DEN
EWR
ORD
SFO
```

This creates one unique list of airports used anywhere in the route data.

That list can then be compared to the airport reference.

---

# 35. What the Final Airport Check is Asking

The logic can be read in plain English as:

```text
Create a list of every airport United flew to or from
                     ↓
Compare each airport to airports_raw
                     ↓
Keep all United airport codes using LEFT JOIN
                     ↓
Show only airports where no reference match exists
```

This gives a complete test of airport-reference coverage.

---

# Bronze Profiling Findings

The profiling stage identified several important requirements for Silver.

```text
T-100 Operational Data
│
├── Filter to United Airlines
├── Filter to relevant scheduled service
├── Retain monthly detail
├── Handle zero performed departures
├── Aggregate multiple source rows
│   to monthly route-aircraft grain
└── Preserve directional routes

Aircraft Lookup
│
├── Decode BTS aircraft codes
└── All United codes successfully matched

United Fleet
│
├── Convert text numeric values
├── Handle em-dash values
├── Split seating ranges
└── Standardise aircraft names

Airport Reference
│
├── Convert coordinates to numeric types
├── Validate airport-code matching
├── Check both origins and destinations
└── Reconcile historical PBI reference difference
```

---

# Planned Silver Route Grain

The profiling work confirmed that the main route-performance Silver table should use:

```text
One Row
=
One Year
+ One Month
+ One Origin
+ One Destination
+ One Aircraft Type
```

Operational measures will then be aggregated appropriately.

Examples:

```text
SUM passengers
SUM seats
SUM departures performed
SUM departures scheduled
SUM air time
```

while route characteristics such as distance will not be summed.

---

# Why Bronze Was Not Changed

An important design principle throughout the profiling stage was:

> Unusual raw values are investigated in Bronze and corrected or standardised in Silver.

For example:

```text
Bronze T-100
PBI

Bronze Airport Reference
DJT / KPBI
```

Both remain untouched.

Silver handles the relationship.

This maintains clear source lineage and makes transformations traceable.

---

# SQL Skills Practised During Bronze Profiling

The profiling work used:

```text
SELECT DISTINCT
COUNT
GROUP BY
ORDER BY
HAVING
WHERE
CASE
SUM
MAX
LEFT JOIN
IS NULL
CTEs
UNION
LEN
DATALENGTH
TRIM
Aliases
Conditional Aggregation
Data Grain Analysis
Reference Data Validation
```

---

# Bronze Profiling Outcome

At the end of this stage:

```text
Raw Data Loaded
       ↓
Source Coverage Checked
       ↓
Data Quality Checked
       ↓
Monthly Grain Identified
       ↓
Aircraft References Validated
       ↓
Fleet Cleaning Requirements Identified
       ↓
Airport References Validated
       ↓
PBI Mismatch Investigated
       ↓
Silver Requirements Defined
```

The project can now move into the Silver layer, where the identified issues will be cleaned and standardised before the business-ready Gold layer is built.
