# Bronze Layer - Data Profiling & Quality Checks

## Overview

The Bronze layer is the raw-data foundation of the Aircraft Route Suitability Analysis project.

Its purpose is to ingest and preserve the source datasets before cleaning, standardisation, aggregation or business logic is applied.

The project currently uses six source datasets:

1. BTS T-100 Segment operational data
2. BTS Aircraft Type reference
3. United Airlines 2025 fleet reference
4. OurAirports airport reference
5. Aircraft range reference
6. BTS Form 41 Schedule P-5.2 aircraft operating-cost and fuel data

The overall Bronze process is:

```text
Raw Source Files
       ↓
Bronze Tables
       ↓
Source Profiling
       ↓
Data Quality Investigation
       ↓
Understand Grain
       ↓
Validate Relationships
       ↓
Document Source Issues
       ↓
Define Silver Transformations
```

The Bronze layer deliberately avoids applying business logic too early.

An important principle used throughout the project is:

> Preserve the source in Bronze, investigate unusual values, and perform controlled cleaning and standardisation in Silver.

The main Bronze scripts are:

```text
02_ddl_bronze.sql
03_proc_load_bronze.sql
04_bronze_quality_checks.sql
```

---

# Bronze Architecture

The current Bronze layer contains:

```text
bronze.t100_segment_raw

bronze.aircraft_types_raw

bronze.united_fleet_raw

bronze.airports_raw

bronze.aircraft_range_raw

bronze.aircraft_operating_cost_raw
```

The relationship between the sources and later analytical use is:

```text
BTS T-100
    │
    └── Route demand
        Seats
        Passengers
        Departures
        Distance
        Aircraft type
        Air time
        Month

BTS Aircraft Types
    │
    └── Decode BTS aircraft codes

United Fleet
    │
    └── Fleet size
        Seat capacity
        Aircraft names
        Average age

OurAirports
    │
    └── Airport names
        Coordinates
        Country
        Region

Aircraft Range
    │
    └── Reference aircraft range

BTS Form 41 Schedule P-5.2
    │
    └── Fuel
        Operating cost
        Maintenance
        Aircraft utilisation
```

Together these sources support the project's main analytical question:

> For each United Airlines U.S. domestic route, which aircraft in the existing fleet appears best suited based on passenger demand, aircraft capacity, route distance and, in the extended model, aircraft operating economics?

---

# Source 1 - BTS T-100 Segment Data

The T-100 Segment dataset is the main operational source.

It contains measures including:

```text
Departures Scheduled
Departures Performed
Passengers
Seats
Payload
Freight
Mail
Distance
Air Time
Ramp-to-Ramp Time
Carrier
Origin
Destination
Aircraft Type
Aircraft Configuration
Year
Quarter
Month
Service Class
```

The raw source includes multiple airlines and multiple service categories.

Filtering to United Airlines is intentionally deferred to Silver.

---

# 1. T-100 Year Coverage

## Check

The first profiling step confirms which years exist in the operational source.

```sql
SELECT DISTINCT
    year
FROM bronze.t100_segment_raw
ORDER BY year;
```

## Why this matters

The project scope is:

```text
Year = 2025
```

A file name or download selection should not be treated as proof that every record belongs to the expected period.

The data itself should be validated.

## Silver impact

The operational Silver transformation explicitly applies:

```sql
WHERE year = 2025
```

This makes the project period reproducible and transparent.

---

# 2. T-100 Carrier Distribution

## Check

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

## Finding

The source contains many airlines.

United Airlines is represented using:

```text
unique_carrier = UA
```

## Why this matters

The project is United-specific, but Bronze should still preserve the full downloaded source.

## Silver impact

Silver applies:

```sql
WHERE unique_carrier = 'UA'
```

---

# 3. United Service Class Distribution

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

```text
Class    Rows
-----    ------
F        53,822
L           881
P           339
```

## Important interpretation

The T-100 `class` field represents a service category.

It does **not** represent cabin classes such as:

```text
First Class
Business Class
Economy
```

Class `F` is the scheduled service category relevant to the passenger-demand analysis in this project.

## Silver impact

The main operational dataset uses:

```sql
WHERE unique_carrier = 'UA'
  AND class = 'F'
  AND year = 2025
```

---

# 4. Monthly Coverage

Monthly coverage was checked because seasonality is central to the project.

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

## Why this matters

An annual average could hide meaningful differences between:

```text
Winter
Spring
Summer
Autumn
```

For example, an aircraft that appears well matched to average annual demand may become:

```text
Too Small
```

during a peak month or:

```text
Potentially Oversized
```

during a lower-demand month.

## Project decision

Month remains part of the analytical grain.

The project does not immediately collapse route activity into a single annual average.

---

# 5. Zero Performed Departures

## Check

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

## Why this matters

One of the later metrics is:

```text
Passengers per Flight
=
Passengers
/
Departures Performed
```

Division by zero must be handled safely.

## Silver / Gold approach

Calculations use:

```sql
NULLIF(departures_performed, 0)
```

For example:

```sql
passengers
/
NULLIF(departures_performed, 0)
```

If performed departures equals zero, the denominator becomes `NULL` instead of causing an error.

---

# 6. Negative Operational Values

Operational measures were checked for impossible negative values.

```sql
SELECT *
FROM bronze.t100_segment_raw
WHERE departures_performed < 0
   OR seats < 0
   OR passengers < 0
   OR distance < 0;
```

Values such as:

```text
-20 passengers
-5 flights
-500 miles
```

would indicate either a source problem or an ingestion problem.

Basic validity should be checked before creating analytical metrics.

---

# 7. Key Field NULL Checks

Important analytical fields were reviewed for missing values.

```sql
SELECT
    SUM(CASE WHEN origin IS NULL THEN 1 ELSE 0 END)
        AS null_origin,

    SUM(CASE WHEN dest IS NULL THEN 1 ELSE 0 END)
        AS null_destination,

    SUM(CASE WHEN aircraft_type IS NULL THEN 1 ELSE 0 END)
        AS null_aircraft_type,

    SUM(CASE WHEN passengers IS NULL THEN 1 ELSE 0 END)
        AS null_passengers,

    SUM(CASE WHEN seats IS NULL THEN 1 ELSE 0 END)
        AS null_seats,

    SUM(CASE WHEN distance IS NULL THEN 1 ELSE 0 END)
        AS null_distance

FROM bronze.t100_segment_raw

WHERE unique_carrier = 'UA'
  AND class = 'F';
```

## Why these fields matter

```text
Missing Origin
→ Route cannot be identified

Missing Destination
→ Route cannot be identified

Missing Aircraft Type
→ Aircraft cannot be evaluated

Missing Passengers
→ Demand cannot be measured

Missing Seats
→ Capacity cannot be measured

Missing Distance
→ Range feasibility cannot be evaluated
```

This check also practised conditional aggregation using:

```sql
SUM(CASE WHEN ... THEN 1 ELSE 0 END)
```

---

# 8. United Aircraft Type Codes

T-100 identifies aircraft using BTS numerical codes.

Examples include:

```text
612
614
622
623
624
626
627
634
637
694
698
721
837
838
839
887
888
889
```

These values are useful for joins but are not suitable as final Power BI labels.

The BTS Aircraft Type lookup is therefore required to decode the operational records.

---

# 9. Understanding T-100 Grain

One of the most important Bronze profiling tasks was understanding:

> What does one source row represent?

The analytical grain required later is:

```text
One Row
=
One Year
+ One Month
+ One Origin
+ One Destination
+ One Aircraft Type
```

For example:

```text
2025
January
EWR
SFO
Aircraft Type 627
```

should become one Silver analytical row.

---

# 10. Testing the Intended Monthly Grain

The raw source was grouped using the intended Silver key.

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

## Finding

Multiple source rows can represent the same:

```text
Year
Month
Origin
Destination
Aircraft Type
```

These are not automatically bad duplicates.

They can represent separate operational source records that need to be combined for the project's analytical grain.

---

# 11. EWR → SFO Worked Example

A useful example was:

```text
January 2025
EWR → SFO
Aircraft Type 627
```

Three Bronze records existed.

They contained:

```text
Row 1
Performed Departures: 1
Passengers: 209
Seats: 276
Distance: 2,565

Row 2
Performed Departures: 1
Passengers: 220
Seats: 276
Distance: 2,565

Row 3
Performed Departures: 126
Passengers: 30,480
Seats: 35,040
Distance: 2,565
```

Deleting two records as duplicates would therefore remove genuine operational activity.

---

# 12. Validating Monthly Aggregation

The records were aggregated using:

```sql
SELECT
    year,
    month,
    origin,
    dest,
    aircraft_type,

    SUM(departures_scheduled)
        AS departures_scheduled,

    SUM(departures_performed)
        AS departures_performed,

    SUM(passengers)
        AS passengers,

    SUM(seats)
        AS seats,

    MAX(distance)
        AS distance,

    SUM(air_time)
        AS air_time

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

```text
Scheduled Departures     126
Performed Departures     128
Passengers            30,909
Seats                 35,592
Distance               2,565
Air Time              41,954
```

## Why SUM is used

Measures such as:

```text
Passengers
Seats
Departures
Air Time
```

represent activity.

They accumulate and therefore use:

```sql
SUM()
```

## Why distance is not summed

Distance is a route characteristic.

Three records at:

```text
2,565 miles
```

do not imply that the route is:

```text
7,695 miles
```

Therefore an appropriate value such as:

```sql
MAX(distance)
```

is retained.

---

# 13. Directional Routes

The project treats:

```text
EWR → SFO
```

and:

```text
SFO → EWR
```

as different routes.

Origin and destination therefore both remain part of the analytical grain.

This allows directional demand differences to remain visible.

---

# 14. Why Month Remains in the Grain

An annual table such as:

```text
2025
EWR → SFO
Aircraft 627
```

would remove seasonality.

Keeping monthly detail allows later analysis of questions such as:

```text
When is route demand highest?

Does the best-fit aircraft change by month?

Does a route become capacity tight during peak periods?

Is an aircraft oversized during quieter months?
```

---

# Source 2 - BTS Aircraft Type Lookup

The aircraft-type reference provides readable descriptions for BTS aircraft codes.

For example:

```text
614
→ Boeing 737-800 family

698
→ Airbus A319 family

838
→ Boeing 737 MAX 8 family
```

---

# 15. Aircraft Code Matching

The operational aircraft codes were tested against the aircraft reference.

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

---

# 16. Checking for Unmatched Aircraft Codes

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

All United aircraft codes used in the relevant T-100 data had coverage in the BTS aircraft reference.

---

# 17. Why LEFT JOIN is Useful for Validation

An `INNER JOIN` would only return successful matches.

That could hide missing reference data.

Using:

```sql
LEFT JOIN
```

keeps all records from the operational dataset.

Then:

```sql
WHERE a.ac_typeid IS NULL
```

isolates failed matches.

This pattern is useful throughout data engineering for validating reference-data coverage.

---

# Source 3 - United Airlines Fleet Reference

The fleet dataset adds aircraft information including:

```text
Aircraft Type
Total Aircraft
Owned Aircraft
Leased Aircraft
Seat Configuration
Average Age
```

The source contains 19 United mainline aircraft types.

Several raw formatting issues were identified before Silver transformation.

---

# 18. Fleet Numeric Fields Stored as Text

Some fields that conceptually represent numbers contain non-numeric source values.

Examples include:

```text
—
```

and:

```text
167-203
```

Because of this, several Bronze fleet columns are intentionally stored as text.

Silver performs controlled conversion later.

---

# 19. Em-Dash Values

Some fleet fields use:

```text
—
```

where a numeric value might otherwise be expected.

For example:

```text
leased = —
```

Trying to execute:

```sql
CAST('—' AS INT)
```

would fail.

Silver therefore handles these values before numeric conversion.

---

# 20. Seat Capacity Ranges

Some aircraft have a single standard seat capacity:

```text
737-800
166 seats
```

Others have multiple configurations:

```text
767-300ER
167-203

777-200ER
276-362
```

A range cannot be represented by one integer without losing information.

## Silver decision

Seat configuration is split into:

```text
seats_min
seats_max
```

For example:

```text
167-203

becomes

seats_min = 167
seats_max = 203
```

A single value:

```text
166
```

becomes:

```text
seats_min = 166
seats_max = 166
```

This later allows the Gold layer to show both ends of the possible capacity range.

---

# 21. Aircraft Naming Differences

Different sources do not always describe the same aircraft using identical text.

Examples include differences such as:

```text
United Fleet
737 MAX 8

BTS
BOEING B737 MAX 800
```

or:

```text
United Fleet
A319-100

BTS
AIRBUS INDUSTRIE A319
```

A text join such as:

```sql
ON fleet.aircraft_type = aircraft.long_name
```

would therefore be unreliable.

## Silver decision

A controlled aircraft mapping is used instead.

---

# 22. Aircraft Family Ambiguity

The most important aircraft-mapping limitation is BTS code:

```text
627
```

The BTS source identifies this at the broader:

```text
777-200 family
```

level.

United's fleet reference separately contains:

```text
777-200
777-200ER
```

The project does not pretend the operational source can identify an exact subtype when it cannot.

This limitation remains documented throughout the model.

---

# Source 4 - OurAirports Airport Reference

The airport source provides:

```text
Airport identifiers
Airport name
Latitude
Longitude
Country
Region
Municipality
Scheduled-service indicator
```

Latitude and longitude are later used for Power BI mapping.

---

# 23. Airport Reference Matching

United airport codes were compared against the airport reference.

```sql
SELECT DISTINCT
    t.origin,
    a.iata_code,
    a.name,
    a.latitude_deg,
    a.longitude_deg

FROM bronze.t100_segment_raw AS t

LEFT JOIN bronze.airports_raw AS a
    ON t.origin = a.iata_code

WHERE t.unique_carrier = 'UA'
  AND t.class = 'F'

ORDER BY t.origin;
```

---

# 24. Checking Both Origins and Destinations

Testing only origin airports would be incomplete.

An airport might appear:

```text
only as an origin
```

or:

```text
only as a destination
```

A complete route-airport validation therefore needs both.

A combined list can be created using:

```sql
SELECT origin AS airport_code
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
  AND class = 'F'

UNION

SELECT dest
FROM bronze.t100_segment_raw
WHERE unique_carrier = 'UA'
  AND class = 'F';
```

`UNION` creates one unique list of airports used on either side of a route.

---

# 25. Palm Beach Airport Mismatch

During airport-reference validation, Palm Beach required investigation.

T-100 uses:

```text
PBI
```

while the relevant physical airport record in the OurAirports source contains:

```text
ident = KPBI
```

and an unexpected source `iata_code` value.

The discrepancy was investigated rather than silently changing Bronze.

---

# 26. LEN vs DATALENGTH Investigation

SQL Server checks were used to confirm that the unexpected airport value was not simply caused by hidden spaces.

Conceptually:

```sql
LEN(iata_code)
```

counts characters.

For an `NVARCHAR` value:

```sql
DATALENGTH(iata_code)
```

returns the number of bytes used.

For a three-character `NVARCHAR` value:

```text
LEN = 3

DATALENGTH = 6
```

is expected because Unicode characters use two bytes each.

The airport issue was therefore not caused by trailing whitespace.

---

# 27. Silver Airport-Code Decision

Bronze preserves the original airport source values.

Silver creates a separate analytical airport code:

```text
analysis_airport_code
```

For the Palm Beach record:

```text
ident
=
KPBI

analysis_airport_code
=
PBI
```

The original source value is also retained for lineage.

This keeps the raw source unchanged while allowing the analytical datasets to join correctly.

---

# Source 5 - Aircraft Range Reference

The aircraft range source contains manufacturer reference values for the 19 United fleet aircraft types.

The main fields are:

```text
Aircraft Type
Range in Nautical Miles
Range in Kilometres
Range Basis
Source
```

The values are used only for a high-level route-feasibility comparison.

---

# 28. Why Range is Included

An aircraft might have suitable seat capacity but insufficient reference range for a route.

Therefore capacity alone is not enough.

Conceptually:

```text
Capacity Suitable?
        +
Range Suitable?
        ↓
Candidate Feasibility
```

---

# 29. Nautical Miles vs Statute Miles

Aircraft reference range is stored in:

```text
nautical miles
```

T-100 route distance is treated in this project as:

```text
statute miles
```

The two values should not be compared directly.

The Gold layer therefore converts aircraft range using approximately:

```text
1 nautical mile
≈
1.15078 statute miles
```

before route-distance comparison.

---

# 30. Range Limitation

Manufacturer reference range is not the same as operational flight-planning range.

Actual usable range can depend on:

```text
Payload
Weather
Fuel reserves
Aircraft configuration
Runway conditions
Operational restrictions
```

The project therefore treats range as:

> A high-level feasibility reference, not a full aircraft performance model.

---

# Source 6 - BTS Form 41 Schedule P-5.2

The project was extended with BTS Form 41 Schedule P-5.2.

The source provides quarterly aircraft operating information including:

```text
Aircraft Fuel Expense

Total Flying Operations Expense

Direct Maintenance Expense

Flight Equipment Maintenance Expense

Total Aircraft Operating Expense

Total Air Hours

Aircraft Days Assigned

Aircraft Fuel Issued

Aircraft Type

Carrier

Operating Region

Year

Quarter
```

The raw source is stored in:

```text
bronze.aircraft_operating_cost_raw
```

---

# 31. Why Operating-Cost and Fuel Data Was Added

The original project evaluates aircraft primarily using:

```text
Passenger Demand
        +
Seat Capacity
        +
Route Distance
        ↓
Aircraft Suitability
```

This can identify:

```text
Too Small

Capacity Tight

Good Fit

Potentially Oversized

Not Suitable for Route Distance
```

However, different aircraft can produce the same capacity fit.

For example:

```text
737-700
126 seats

A319-100
126 seats
```

If both aircraft have enough range, the existing capacity and range rules may not provide enough information to distinguish between them.

The new source adds:

```text
Fuel Consumption

Operating Expense

Maintenance Expense

Aircraft Utilisation
```

The extended analytical idea becomes:

```text
Demand
+
Capacity
+
Range
+
Fuel
+
Operating Cost
        ↓
Stronger Candidate Comparison
```

The cost data does **not** replace the original suitability logic.

Instead, it adds another decision-support dimension.

---

# 32. P-5.2 Row Count

The downloaded source was checked after loading.

```sql
SELECT
    COUNT(*) AS row_count
FROM bronze.aircraft_operating_cost_raw;
```

## Result

```text
2,400 rows
```

This confirms the expected source volume was loaded into Bronze.

---

# 33. P-5.2 Year Coverage

```sql
SELECT
    year,
    COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

GROUP BY year

ORDER BY year;
```

## Finding

The downloaded source contains:

```text
2025
```

which matches the project period.

---

# 34. P-5.2 Quarter Coverage

Schedule P-5.2 is quarterly.

The source was checked using:

```sql
SELECT
    quarter,
    COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

GROUP BY quarter

ORDER BY quarter;
```

## Result

The source contains all four quarters:

```text
1
2
3
4
```

## Why this matters

The planned annual aircraft economics rates will be based on all four quarters.

Missing quarters could create misleading annual comparisons.

---

# 35. United Airlines Coverage in P-5.2

The source contains multiple airlines.

United records were identified using:

```sql
SELECT
    unique_carrier,
    unique_carrier_name,
    COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

WHERE unique_carrier = 'UA'

GROUP BY
    unique_carrier,
    unique_carrier_name;
```

## Result

```text
215 United records
```

United is represented using:

```text
unique_carrier = UA
```

## Silver impact

Silver will apply:

```sql
WHERE unique_carrier = 'UA'
```

---

# 36. United Operating Regions

United's records were grouped by region.

```sql
SELECT
    region,
    COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

WHERE unique_carrier = 'UA'

GROUP BY region

ORDER BY region;
```

## Result

```text
Region    Records
------    -------
A             42
D             76
L             67
P             30
```

The dataset therefore contains United activity across several operating regions.

---

# 37. Why Domestic Region is Used

The project scope is:

```text
United Airlines
2025
U.S. Domestic Routes
```

The operating-cost reference should align as closely as possible with the routes being analysed.

The initial Silver economics table will therefore use:

```sql
WHERE unique_carrier = 'UA'
  AND year = '2025'
  AND region = 'D'
```

This avoids mixing domestic aircraft activity with Atlantic, Latin and Pacific operations when calculating the initial cost reference.

---

# 38. United Aircraft Type Coverage in P-5.2

The new source uses the same BTS aircraft-code system already present in the operational data.

For United domestic records, the usable aircraft codes include:

```text
612
614
622
623
624
626
627
634
637
694
698
721
837
838
839
887
888
889
```

This gives:

```text
18 usable aircraft codes
```

The project can therefore reuse the existing controlled aircraft mapping.

---

# 39. Reusing the Existing Aircraft Mapping

Because the new source uses BTS aircraft codes, the project does not need a completely new aircraft naming system.

Conceptually:

```text
P-5.2 Aircraft Code
        ↓
silver.aircraft_mapping
        ↓
United Fleet Aircraft Name
```

For example:

```text
614
→ 737-800

698
→ A319-100

838
→ 737 MAX 8
```

This is a useful example of why reusable reference tables are valuable in a data model.

---

# 40. P-5.2 Aircraft Code 627 Limitation

The same aircraft-family ambiguity remains for:

```text
627
```

The cost source cannot automatically distinguish:

```text
777-200
```

from:

```text
777-200ER
```

when BTS reports the broader family.

The project will therefore continue to document this limitation rather than inventing variant-level precision.

---

# 41. Generic Aircraft Code 999

The source also contains:

```text
999
```

This represents a generic / summary aircraft record rather than one specific fleet type.

It cannot be meaningfully compared with:

```text
737-800
A319-100
787-9
```

or another specific aircraft.

## Silver impact

The aircraft economics dataset will exclude:

```sql
aircraft_type <> '999'
```

The source record remains preserved in Bronze.

---

# 42. Quarterly Coverage by Aircraft Type

The United domestic aircraft records were checked for complete quarterly coverage.

```sql
SELECT
    aircraft_type,
    COUNT(DISTINCT quarter) AS quarter_count

FROM bronze.aircraft_operating_cost_raw

WHERE unique_carrier = 'UA'
  AND region = 'D'
  AND aircraft_type <> '999'

GROUP BY aircraft_type

ORDER BY TRY_CAST(aircraft_type AS INT);
```

## Result

All:

```text
18 usable aircraft types
```

have records for:

```text
4 quarters
```

in the domestic subset.

This supports annual aggregation from Q1-Q4.

---

# 43. Blank Financial Values

The raw source contains blank financial fields for some records.

For example:

```sql
SELECT
    COUNT(*) AS rows_with_blank_operating_cost

FROM bronze.aircraft_operating_cost_raw

WHERE NULLIF(
    TRIM(tot_air_op_expenses),
    ''
) IS NULL;
```

These blanks are not automatically converted into zero.

A blank source value and a genuine zero do not necessarily mean the same thing.

Bronze therefore preserves them.

---

# 44. Why P-5.2 Numeric Fields Are Stored as NVARCHAR in Bronze

Fields such as:

```text
fuel_fly_ops

tot_air_op_expenses

total_air_hours

air_fuels_issued
```

represent numerical measures.

However, the Bronze table stores them initially as text.

This makes ingestion more tolerant of blank or unexpected source values.

Silver can then safely perform:

```sql
TRY_CAST(
    NULLIF(
        TRIM(total_air_hours),
        ''
    )
    AS DECIMAL(18,2)
)
```

The pattern is:

```text
Bronze
Raw flexible representation
        ↓
Silver
Validated numeric representation
        ↓
Gold
Business calculations
```

---

# 45. Planned Annual Economics Aggregation

Schedule P-5.2 provides quarterly records.

The project requires an annual aircraft-level reference.

For example:

```text
2025 Q1  737-800
2025 Q2  737-800
2025 Q3  737-800
2025 Q4  737-800
```

will become:

```text
2025  737-800
```

The annual totals will be calculated first.

Conceptually:

```sql
SUM(total_air_hours)

SUM(air_fuels_issued)

SUM(tot_air_op_expenses)

SUM(tot_flt_maint_memo)
```

---

# 46. Planned Fuel Efficiency Metric

The planned aircraft fuel measure is:

```text
Fuel Gallons per Airborne Hour
```

Conceptually:

```text
Total Fuel Issued
-----------------
Total Air Hours
```

SQL will use the annual totals:

```sql
SUM(air_fuels_issued)
/
NULLIF(
    SUM(total_air_hours),
    0
)
```

---

# 47. Planned Operating-Cost Metric

The planned aircraft operating-cost measure is:

```text
Operating Cost per Airborne Hour
```

Conceptually:

```text
Total Aircraft Operating Expense
---------------------------------
Total Air Hours
```

This creates a comparable aircraft-type rate that can later be joined to viable route candidates.

---

# 48. Planned Maintenance Metric

A similar calculation can be created for maintenance:

```text
Maintenance Cost per Airborne Hour
```

using:

```text
Flight Equipment Maintenance Expense
------------------------------------
Total Air Hours
```

The exact fields and terminology will remain documented in the Silver transformation.

---

# 49. Why Quarterly Ratios Should Not Be Averaged Directly

Suppose:

```text
Quarter 1
Fuel = 100
Hours = 10

Fuel Rate = 10 per hour
```

and:

```text
Quarter 2
Fuel = 900
Hours = 300

Fuel Rate = 3 per hour
```

A simple average gives:

```text
(10 + 3) / 2
=
6.5
```

but this incorrectly gives both quarters equal weight.

Instead:

```text
Total Fuel
=
1,000

Total Hours
=
310
```

Therefore:

```text
1,000 / 310
≈
3.23 per hour
```

This better reflects the underlying activity.

The project will therefore use:

```text
SUM(numerator)
/
SUM(denominator)
```

rather than averaging pre-calculated quarterly rates.

---

# 50. How Economics Extends the Business Question

The first suitability model asks:

```text
Can the aircraft fly the route?
        ↓
Range

Can the aircraft hold the observed demand?
        ↓
Capacity

How closely does the capacity match demand?
        ↓
Expected Load Factor / Capacity Gap
```

The economics extension adds:

```text
What are the fuel and cost differences
between otherwise viable aircraft?
```

The decision flow becomes:

```text
1. Range Feasibility

        ↓

2. Capacity Feasibility

        ↓

3. Capacity Fit

        ↓

4. Fuel / Operating Cost Comparison
```

Cost should not automatically override feasibility.

A lower-cost aircraft is not useful if it cannot carry the route's observed demand or satisfy the route-distance requirement.

---

# 51. Cost Data Will Be Used as a Proxy

The project will not claim:

```text
"This aircraft will save United exactly $X on this route."
```

Schedule P-5.2 provides aircraft-type operating information, not exact route-level accounting.

Instead, future Gold calculations may produce metrics such as:

```text
Estimated Route Operating-Cost Proxy
```

based on:

```text
Average Route Airborne Time
×
Aircraft Operating Cost per Airborne Hour
```

This should be interpreted as a comparison aid rather than actual route profitability.

---

# Planned Silver Route Grain

The Bronze profiling confirmed that the main operational Silver table should use:

```text
One Row
=
One Year
+ One Month
+ One Origin
+ One Destination
+ One Aircraft Type
```

Operational measures are aggregated appropriately.

Examples include:

```text
SUM Passengers

SUM Seats

SUM Departures Scheduled

SUM Departures Performed

SUM Payload

SUM Freight

SUM Mail

SUM Air Time

SUM Ramp-to-Ramp Time
```

Route distance is retained using an appropriate non-additive aggregation such as:

```sql
MAX(distance)
```

---

# Planned Silver Aircraft Economics Grain

The aircraft economics data requires a different grain.

The planned economics table will use:

```text
One Row
=
One Year
+ One BTS Aircraft Type
```

for the filtered subset:

```text
United Airlines
+
2025
+
Domestic Operating Region
```

The four quarterly P-5.2 records will be aggregated before annual efficiency rates are calculated.

The two grains remain separate:

```text
Route Performance

Year
+ Month
+ Origin
+ Destination
+ Aircraft Type
```

and:

```text
Aircraft Economics

Year
+ Aircraft Type
```

They can then be related later through the controlled aircraft mapping.

---

# Bronze Profiling Findings

The main requirements identified during Bronze profiling are:

```text
T-100 Operational Data
│
├── Filter to United Airlines
├── Filter to relevant Class F service
├── Restrict to 2025
├── Retain monthly seasonality
├── Preserve directional routes
├── Handle zero performed departures
└── Aggregate detailed source rows
    to route-month-aircraft grain


BTS Aircraft Lookup
│
├── Decode numerical aircraft codes
└── Validate operational code coverage


United Fleet
│
├── Convert text numeric values
├── Handle em-dash values
├── Parse seat ranges
├── Retain min/max capacity
└── Standardise aircraft naming


Airport Reference
│
├── Convert coordinates
├── Validate origin coverage
├── Validate destination coverage
├── Handle the PBI reference mismatch
└── Create an analysis airport code


Aircraft Range
│
├── Convert range values to numeric types
├── Preserve source information
└── Convert nautical miles before
    comparing with route distance


Aircraft Operating Economics
│
├── Filter to United Airlines
├── Restrict to 2025
├── Use domestic-region records
├── Exclude generic code 999
├── Convert raw text measures
├── Aggregate Q1-Q4
├── Reuse aircraft mapping
├── Calculate fuel per air hour
├── Calculate operating cost per air hour
└── Calculate maintenance cost per air hour
```

---

# Why Bronze Values Are Not Silently Corrected

One of the core design decisions in this project is:

> Source anomalies are documented in Bronze and corrected or standardised only in Silver when there is a justified transformation rule.

Examples include:

```text
T-100:
PBI

OurAirports:
unexpected PBI reference values
```

and:

```text
United Fleet:
167-203

Silver:
seats_min = 167
seats_max = 203
```

and:

```text
P-5.2:
blank numeric text

Silver:
NULLIF + TRY_CAST
```

This separation improves:

```text
Data lineage
Traceability
Debugging
Reproducibility
```

---

# Bronze Full-Refresh Loading Pattern

The Bronze procedure uses a full-refresh approach.

For each source:

```text
TRUNCATE TABLE
        ↓
BULK INSERT
        ↓
Next Source
```

For example:

```sql
TRUNCATE TABLE bronze.aircraft_operating_cost_raw;

BULK INSERT bronze.aircraft_operating_cost_raw

FROM '...T_F41SCHEDULE_P52.csv'

WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDQUOTE = '"',
    CODEPAGE = '65001',
    TABLOCK
);
```

---

# Why TRUNCATE is Used

`TRUNCATE TABLE` removes the existing rows before a full reload.

The table structure remains in place.

This is different from:

```sql
DROP TABLE
```

which removes the table itself.

The process therefore becomes:

```text
Existing Bronze Table
        ↓
TRUNCATE
        ↓
Empty Bronze Table
        ↓
BULK INSERT
        ↓
Fresh Source Copy
```

---

# Why FORMAT = 'CSV' is Used

```sql
FORMAT = 'CSV'
```

tells SQL Server that the input follows comma-separated-value parsing rules.

This is preferable to manually handling delimiters where the file is a standard CSV.

---

# Why FIRSTROW = 2 is Used

The CSV source files contain column names in the first row.

```sql
FIRSTROW = 2
```

starts ingestion from the first data record and skips the header.

---

# Why FIELDQUOTE is Used

CSV text can contain quoted values.

For example:

```text
"United Air Lines Inc."
```

Using:

```sql
FIELDQUOTE = '"'
```

allows SQL Server's CSV parser to treat quoted text correctly.

---

# Why CODEPAGE = '65001' is Used

```sql
CODEPAGE = '65001'
```

tells SQL Server to interpret the source as UTF-8 text.

This reduces the risk of corrupting characters when loading text from external CSV files.

---

# Why TABLOCK is Used

```sql
TABLOCK
```

allows SQL Server to use a table-level lock during the bulk load.

Because this project uses a controlled full-refresh Bronze process, concurrent editing of the Bronze table is not required during ingestion.

The option can therefore make the bulk-loading process more efficient.

---

# Stored Procedure Error Handling

The Bronze loader uses:

```sql
BEGIN TRY
```

and:

```sql
BEGIN CATCH
```

so that ingestion errors can be captured and reported.

Useful functions include:

```sql
ERROR_NUMBER()

ERROR_LINE()

ERROR_MESSAGE()
```

The procedure then uses:

```sql
THROW;
```

to re-raise the original error rather than silently hiding a failed load.

---

# Load Timing

The stored procedure captures:

```sql
SYSDATETIME()
```

before and after the load.

Elapsed time can then be calculated using:

```sql
DATEDIFF()
```

This provides simple pipeline monitoring and also demonstrates how batch duration can be measured in SQL Server.

---

# Bronze Quality Checks

The Bronze quality-check script performs source-level validation such as:

```text
Row Counts

Sample Record Review

Year Coverage

Month / Quarter Coverage

Carrier Coverage

Service Class Distribution

Aircraft Code Coverage

Airport-Code Matching

NULL / Blank Review

Known Source Anomaly Investigation
```

The purpose is not to make Bronze perfectly clean.

The purpose is to understand what was loaded and decide what Silver must do.

---

# SQL Skills Practised During Bronze

The Bronze stage provided practical use of:

```text
CREATE TABLE

DROP TABLE IF EXISTS

TRUNCATE TABLE

BULK INSERT

CREATE OR ALTER PROCEDURE

EXEC

SET NOCOUNT ON

DECLARE

DATETIME2

SYSDATETIME

DATEDIFF

PRINT

CONCAT

TRY / CATCH

ERROR_NUMBER

ERROR_LINE

ERROR_MESSAGE

THROW

SELECT

SELECT DISTINCT

COUNT

COUNT DISTINCT

GROUP BY

ORDER BY

WHERE

HAVING

SUM

MAX

CASE

LEFT JOIN

UNION

IS NULL

NULLIF

TRY_CAST

TRIM

LEN

DATALENGTH

Aliases

Conditional Aggregation

Data Grain Analysis

Reference Data Validation

Weighted Rate Reasoning
```

---

# Key Data-Engineering Concepts Practised

Beyond individual SQL functions, the Bronze work reinforced several broader concepts.

## Data lineage

Raw values remain traceable back to their source.

## Grain

The meaning of one row must be understood before aggregation.

## Additive vs non-additive measures

For example:

```text
Passengers
→ additive

Distance
→ non-additive
```

## Reference-data validation

Aircraft and airport lookup coverage should be tested rather than assumed.

## Controlled transformation

Cleaning rules belong in Silver rather than being hidden during raw ingestion.

## Reusable mappings

The BTS aircraft mapping can support more than one source.

## Weighted metrics

Annual rates should be calculated from total numerators and denominators rather than averaging ratios blindly.

---

# Bronze Limitations

The Bronze layer intentionally does not attempt to solve all source issues.

Examples include:

```text
Aircraft-family ambiguity

Airport-code discrepancies

Blank financial values

Multiple aircraft seat configurations

Quarterly vs monthly source grains

Different naming conventions
```

These are documented and handled later where appropriate.

---

# Aircraft Economics Scope Limitation

The P-5.2 extension improves the business value of the analysis, but it still does not create a complete airline cost model.

The project does not currently model:

```text
Exact aircraft availability

Tail-level aircraft assignment

Crew scheduling

Aircraft rotations

Maintenance scheduling

Airport / runway performance

Weather

Fuel-price variation by airport

Payload-specific fuel burn

Network connectivity requirements

Exact route profitability
```

The economics data should therefore be interpreted as:

> Aircraft-type decision-support information, not an exact scheduling or profitability model.

---

# Bronze Profiling Outcome

At the end of the Bronze stage:

```text
Six Raw Sources Loaded
        ↓
Source Coverage Validated
        ↓
United Carrier Codes Confirmed
        ↓
Service Class Analysed
        ↓
Monthly Coverage Validated
        ↓
Operational Grain Investigated
        ↓
Monthly Aggregation Rules Defined
        ↓
Aircraft Reference Coverage Validated
        ↓
Fleet Cleaning Requirements Identified
        ↓
Airport Matching Investigated
        ↓
PBI Reference Issue Documented
        ↓
Range Source Validated
        ↓
P-5.2 Cost / Fuel Source Added
        ↓
United Domestic Economics Records Profiled
        ↓
Quarterly Coverage Validated
        ↓
Aircraft Economics Grain Defined
        ↓
Silver Transformation Requirements Defined
```

The Bronze layer now supports two related analytical areas.

## Route Suitability

```text
Passenger Demand
+
Aircraft Capacity
+
Route Distance
```

## Aircraft Economics

```text
Fuel Use
+
Operating Expense
+
Maintenance Expense
+
Aircraft Utilisation
```

These datasets can now be transformed into clean, reusable Silver tables before being combined into business-facing Gold analysis.

---

# Next Layer

The next stage is the Silver layer.

Silver is responsible for:

```text
Filtering

Cleaning

Data Type Conversion

Standardisation

Controlled Mapping

Aggregation

Reference Reconciliation
```

The new P-5.2 source will become an aircraft-level annual economics reference.

The intended flow is:

```text
bronze.aircraft_operating_cost_raw
        ↓
Filter United
        ↓
Filter 2025
        ↓
Filter Domestic Region
        ↓
Exclude Aircraft Code 999
        ↓
TRY_CAST Numeric Measures
        ↓
Aggregate Q1-Q4
        ↓
Calculate Fuel / Cost Rates
        ↓
silver.aircraft_operating_cost
```

This new Silver table can then be integrated with the existing route-aircraft suitability model in Gold.

The original capacity-and-range logic remains intact.

The economics data extends the analysis rather than replacing it.
