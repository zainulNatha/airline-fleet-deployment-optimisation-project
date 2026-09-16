# Silver Layer

## 1. Purpose

The Silver layer transforms the raw Bronze data into cleaned, standardised and analysis-ready datasets.

The Bronze layer preserves source data as closely as possible.

The Silver layer answers a different question:

> What does the data mean, and how should it be structured so that it can be analysed reliably?

The main responsibilities of the Silver layer are:

- cleaning text values
- converting text into appropriate numeric and date data types
- handling missing or unusual source values
- standardising reference data
- reconciling differences between source systems
- filtering T-100 data to the required airline, service type and year
- aggregating operational data to the required analytical grain
- creating controlled mappings between aircraft coding systems
- performing quality checks before the Gold layer

No aircraft recommendation logic is applied in Silver.

Business metrics such as load factor, passengers per flight, capacity gap and aircraft suitability are calculated later in the Gold layer.

---

# 2. Silver Architecture

The project follows a Medallion architecture:

```text
SOURCE FILES
     ↓
BRONZE
Raw source-aligned tables
     ↓
SILVER
Cleaned and standardised analytical data
     ↓
GOLD
Business metrics and aircraft suitability logic
     ↓
POWER BI
Reporting and visualisation
```

Bronze asks:

> What did the source provide?

Silver asks:

> What does the source data mean, and how can it be made reliable?

Gold will ask:

> What business insights can be calculated from the cleaned data?

---

# 3. Silver Tables

The Silver layer contains six tables:

```text
silver.united_fleet
silver.aircraft_types
silver.airports
silver.aircraft_range
silver.aircraft_mapping
silver.route_aircraft_monthly
```

Each table has a specific responsibility.

---

# 4. `silver.united_fleet`

## Purpose

Stores a cleaned version of United Airlines' 2025 mainline fleet reference.

Source:

```text
bronze.united_fleet_raw
```

The Bronze file stores most values as text because the Silver layer is responsible for interpreting them.

Examples of raw values include:

```text
aircraft_type                    767-300ER
total                            37
owned                            37
leased                           —
seats_in_standard_configuration 167-203
average_age_years                29.8
```

The Silver version becomes:

```text
aircraft_type       767-300ER
total_aircraft      37
owned_aircraft      37
leased_aircraft     0
seats_min           167
seats_max           203
average_age_years   29.8
```

---

## Why split the seat configuration?

Some aircraft have a single reported seat capacity:

```text
166
```

Others have a range:

```text
167-203
```

Instead of keeping these as text, Silver separates them into:

```text
seats_min
seats_max
```

Therefore:

```text
166
```

becomes:

```text
seats_min = 166
seats_max = 166
```

while:

```text
167-203
```

becomes:

```text
seats_min = 167
seats_max = 203
```

This makes the values usable later when comparing route demand with candidate aircraft capacity.

---

## Important SQL functions

### `TRIM()`

Removes leading and trailing spaces.

```sql
TRIM(aircraft_type)
```

Example:

```text
' 737-800 '
```

becomes:

```text
'737-800'
```

---

### `TRY_CAST()`

Attempts to convert a value into another data type.

Example:

```sql
TRY_CAST('141' AS INT)
```

returns:

```text
141
```

Unlike `CAST()`, `TRY_CAST()` returns `NULL` if conversion fails instead of stopping the complete load.

This allows conversion failures to be identified through quality checks.

---

### `CHARINDEX()`

Finds the position of a character inside text.

Example:

```sql
CHARINDEX('-', '167-203')
```

returns:

```text
4
```

because the hyphen occurs at character position four.

---

### `LEFT()`

Extracts characters from the left-hand side of text.

```sql
LEFT('167-203', 3)
```

returns:

```text
167
```

---

### `SUBSTRING()`

Extracts part of a string beginning at a specified position.

It is used to retrieve the maximum seat value after the hyphen.

```text
167-203
    ↓
   203
```

---

# 5. `silver.aircraft_types`

## Purpose

Stores a cleaned version of the BTS aircraft type reference.

Source:

```text
bronze.aircraft_types_raw
```

The BTS T-100 dataset does not directly contain aircraft names.

Instead it contains an aircraft type ID such as:

```text
614
839
887
```

The aircraft type reference allows those codes to be interpreted.

Examples include:

```text
614 → Boeing 737-800
839 → Boeing 737 MAX 9
887 → Boeing 787-8
```

The Silver table cleans the descriptive fields and converts source date fields into proper SQL `DATE` values.

---

## `NULLIF()`

The expression:

```sql
NULLIF(TRIM(begin_date), '')
```

means:

> If the cleaned value is an empty string, return NULL.

This prevents blank text from being treated as meaningful data.

The general pattern is:

```text
raw text
   ↓
TRIM
   ↓
NULLIF blank values
   ↓
TRY_CAST to correct type
```

---

# 6. `silver.airports`

## Purpose

Stores cleaned airport reference information used to:

- identify route airports
- supply latitude and longitude
- support Power BI route mapping
- match T-100 airport codes to the airport reference

Source:

```text
bronze.airports_raw
```

Useful fields include:

```text
airport ID
airport identifier
IATA code
airport name
municipality
region
country
latitude
longitude
scheduled service indicator
```

Latitude and longitude are converted from text into numeric values.

---

# 7. Airport Code Reconciliation

During Bronze profiling, one airport-code mismatch was discovered.

The 2025 T-100 data uses:

```text
PBI
```

for Palm Beach.

The airport reference record identified by:

```text
ident = KPBI
```

contained a different current `iata_code`.

Rather than changing the Bronze data, the Silver layer preserves the source value while creating a controlled analysis code.

The Silver table therefore contains:

```text
source_iata_code
analysis_airport_code
```

For most airports:

```text
source_iata_code       = EWR
analysis_airport_code  = EWR
```

For the identified Palm Beach exception:

```text
ident                  = KPBI
source_iata_code       = source value
analysis_airport_code  = PBI
```

This preserves source traceability while allowing the 2025 T-100 data to join successfully.

Bronze remains unchanged.

---

# 8. `silver.aircraft_range`

## Purpose

Stores cleaned aircraft range reference information.

Source:

```text
bronze.aircraft_range_raw
```

The source contains:

```text
aircraft_type
range_nmi
range_km
range_basis
source_name
source_url
```

Range values are converted from text into numeric values.

The range reference will later support a feasibility check:

> Is the aircraft's reference range sufficient for the route distance?

Range is not treated as a score.

An aircraft having more range does not automatically mean it is more suitable.

The range check is simply intended to eliminate aircraft that are not appropriate for the route distance.

Before Gold compares route distance with aircraft range, the measurement units must be made consistent.

---

# 9. `silver.aircraft_mapping`

## Purpose

Different data sources describe aircraft differently.

T-100 uses numeric BTS aircraft codes:

```text
614
698
839
```

United's fleet reference uses aircraft names:

```text
737-800
A319-100
737 MAX 9
```

The mapping table creates a controlled bridge between the two systems.

Example:

```text
BTS Code    Standard Aircraft    United Aircraft
--------    -----------------    ----------------
614         737-800              737-800
698         A319-100             A319-100
839         737 MAX 9            737 MAX 9
```

---

# 10. The 777-200 Mapping Limitation

An important source limitation was identified for BTS aircraft type:

```text
627
```

The BTS aircraft classification groups the Boeing 777-200 family together.

United's fleet reference separately reports:

```text
777-200
777-200ER
```

The T-100 aircraft code alone does not provide enough information to reliably determine which United variant operated every record.

The mapping therefore deliberately stores:

```text
aircraft_type_id = 627
standard_aircraft_type = 777-200 family
united_aircraft_type = NULL
mapping_status = Ambiguous
```

The project does not invent a more precise variant than the source data supports.

This limitation should also be documented in the final project README.

---

# 11. Why Not Create Two Mapping Rows for Code 627?

Creating:

```text
627 → 777-200
627 → 777-200ER
```

would create a one-to-many join.

A route record such as:

```text
EWR → SFO | 627 | 30,909 passengers
```

could become:

```text
EWR → SFO | 627 | 777-200   | 30,909
EWR → SFO | 627 | 777-200ER | 30,909
```

This would duplicate the operational data and could incorrectly double passenger totals.

Maintaining one mapping row and explicitly marking the code as ambiguous avoids this problem.

---

# 12. `silver.route_aircraft_monthly`

## Purpose

This is the main operational Silver table.

Source:

```text
bronze.t100_segment_raw
```

The raw T-100 dataset can contain multiple records representing the same:

```text
year
month
origin
destination
aircraft type
```

The Silver layer aggregates these records into one analytical row.

---

# 13. Silver Grain

The grain of the table is:

> One year + one month + one origin + one destination + one aircraft type.

For example:

```text
2025
January
EWR
SFO
Aircraft type 627
```

represents one Silver row.

Routes remain directional.

Therefore:

```text
EWR → SFO
```

and:

```text
SFO → EWR
```

are treated as separate routes.

This preserves directional demand differences.

---

# 14. Why Keep Month?

Monthly grain is important because annual averages can hide seasonal demand.

For example:

```text
February → lower passenger demand
July     → high passenger demand
December → high passenger demand
```

An aircraft may appear appropriately sized when viewed across the whole year but could be:

```text
oversized in February
well-sized in April
capacity-tight in July
```

Keeping month therefore allows the final analysis to investigate seasonality.

---

# 15. T-100 Filtering

The Silver route table filters Bronze to:

```sql
WHERE unique_carrier = 'UA'
  AND class = 'F'
  AND year = 2025
```

This means the analysis includes:

```text
United Airlines
2025
scheduled service represented by BTS Class F
```

Other carriers and service classes remain available in Bronze but are outside Version 1 of this project.

---

# 16. Why `SUM()`?

Measures such as:

```text
passengers
seats
departures performed
departures scheduled
air time
ramp-to-ramp time
```

represent activity that can be added across records belonging to the same monthly group.

Example Bronze records:

```text
January 2025
EWR → SFO
Aircraft 627

Row 1
Passengers = 209
Performed flights = 1

Row 2
Passengers = 220
Performed flights = 1

Row 3
Passengers = 30,480
Performed flights = 126
```

Silver combines them:

```text
Passengers
209 + 220 + 30,480
= 30,909

Performed flights
1 + 1 + 126
= 128
```

Therefore the Silver row contains:

```text
Passengers = 30,909
Performed departures = 128
```

---

# 17. Why Not `AVG(passengers)`?

Using:

```sql
AVG(passengers)
```

would calculate the average per Bronze record.

For the example:

```text
(209 + 220 + 30,480) / 3
= 10,303
```

This does not represent average passengers per flight because the three Bronze records represent very different numbers of flights.

Instead, Silver stores the reliable totals.

Gold can later calculate:

```text
Passengers per Flight
=
Total Passengers / Total Flights

30,909 / 128
≈ 241.5
```

This is a meaningful operational average.

---

# 18. Why `MAX(distance)`?

Distance is not additive.

Suppose three source records for the same route each contain:

```text
2,565
```

Using:

```sql
SUM(distance)
```

would incorrectly produce:

```text
7,695
```

The route has not become three times longer.

Therefore:

```sql
MAX(distance)
```

is used to preserve the route distance after grouping.

This assumes the grouped records represent the same route and therefore should contain a consistent distance.

Distance consistency can also be checked during data quality testing.

---

# 19. `source_record_count`

The Silver route table includes:

```text
source_record_count
```

This is created using:

```sql
COUNT(*)
```

It records how many Bronze rows were combined to create a Silver row.

For the EWR → SFO example:

```text
source_record_count = 3
```

This improves traceability and makes aggregation behaviour easier to audit.

---

# 20. Why Are Business Metrics Not Stored in Silver?

Silver deliberately stores clean operational facts such as:

```text
passengers
seats
departures performed
route distance
air time
```

Metrics such as:

```text
Passengers per Flight
Seats per Flight
Load Factor
Capacity Gap
Expected Candidate Load Factor
Aircraft Suitability
```

are business calculations.

They therefore belong in Gold.

For example:

```text
Passengers per Flight
=
Passengers / Departures Performed
```

```text
Seats per Flight
=
Seats / Departures Performed
```

```text
Load Factor
=
Passengers / Seats
```

The architecture therefore remains:

```text
SILVER
Reliable operational facts
        ↓
GOLD
Business calculations
        ↓
POWER BI
Analysis and reporting
```

---

# 21. Why This Still Allows Route Investigation

Although Silver aggregates raw rows, it does not aggregate away the route.

The table still contains:

```text
year
month
origin
destination
aircraft type
```

Therefore if Power BI identifies unusually high demand in July, the analysis can drill into July and determine which routes and aircraft contributed to the result.

For example:

```text
July
 ↓
EWR → SFO
EWR → LAX
ORD → DEN
IAH → MCO
...
```

The model therefore supports both:

```text
high-level monthly trends
```

and:

```text
route-level investigation
```

---

# 22. Full Refresh Strategy

The Silver load currently uses a full-refresh approach.

Each table follows the pattern:

```sql
TRUNCATE TABLE silver.table_name;

INSERT INTO silver.table_name
SELECT ...
FROM bronze.table_name;
```

`TRUNCATE` removes existing rows but preserves the table structure.

This prevents duplicate records when the load procedure is rerun.

For the current portfolio-scale dataset, this approach is simple, transparent and appropriate.

---

# 23. Silver Load Procedure

The final load logic is contained in:

```text
06_proc_load_silver.sql
```

The procedure:

1. starts a timer
2. truncates the existing Silver tables
3. transforms and reloads each dataset
4. reports completion time
5. uses `TRY/CATCH` for error handling
6. rethrows errors using `THROW`

The procedure can be run with:

```sql
EXEC silver.load_silver;
```

---

# 24. Silver Quality Checks

Quality checks are stored in:

```text
07_silver_quality_checks.sql
```

Checks include:

```text
row-count reconciliation
NULL conversion checks
duplicate reference IDs
airport coordinate validation
airport coverage against T-100
route grain validation
month validation
aggregation reconciliation
aircraft range validation
aircraft mapping validation
United fleet mapping coverage
```

The purpose of these checks is not simply to prove that SQL ran successfully.

They test whether the resulting data is logically correct.

---

# 25. Key Data Quality Principles Used

The Silver layer follows several principles:

```text
Do not alter Bronze source data.

Clean and standardise only in Silver.

Use TRY_CAST so failed conversions can be identified.

Use NULL instead of meaningless blank strings.

Preserve source values where useful for traceability.

Use controlled mappings for known source-system differences.

Do not guess when source data is ambiguous.

Aggregate measures according to their business meaning.

Validate the intended table grain.

Keep business calculations separate from data cleaning.
```

---

# 26. Known Limitations

## BTS 777-200 family

Aircraft code 627 cannot currently be reliably separated between:

```text
777-200
777-200ER
```

This remains explicitly marked as ambiguous.

---

## Aircraft range

Manufacturer range figures are reference values and do not model all operational conditions.

Real-world usable range may depend on factors such as:

```text
payload
weather
airport conditions
reserves
engine variant
aircraft configuration
operational procedures
```

Version 1 therefore uses range only as a high-level feasibility check.

---

## Seat configuration

United reports some aircraft using seat ranges.

These have been retained as:

```text
seats_min
seats_max
```

Rather than assuming one exact seat configuration.

---

## Operational cost

Version 1 does not attempt to estimate:

```text
fuel burn
operating cost
profitability
crew cost
maintenance cost
```

These would require additional data and assumptions.

---

# 27. Silver Output

After successful completion, the Silver layer contains:

```text
silver.united_fleet
silver.aircraft_types
silver.airports
silver.aircraft_range
silver.aircraft_mapping
silver.route_aircraft_monthly
```

These tables provide the clean foundation required for the Gold layer.

---

# 28. Next Layer

The Gold layer will transform Silver data into business-ready analytical outputs.

Planned metrics include:

```text
Passengers per Flight
Seats per Flight
Load Factor
Capacity Gap
Expected Candidate Load Factor
Range Feasibility
Aircraft Suitability Category
```

The final objective remains:

> For each route, which aircraft in United's existing fleet appears best suited based on passenger demand, aircraft capacity and route distance?

The output is intended as decision-support analysis rather than an operational scheduling recommendation.
