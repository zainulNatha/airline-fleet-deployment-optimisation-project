# Silver Layer

## 1. Purpose

The Silver layer transforms the raw Bronze data into cleaned, standardised and analysis-ready datasets.

The Bronze layer preserves source data as closely as possible.

The Silver layer answers a different question:

> What does the source data mean, and how should it be structured so that it can be analysed reliably?

The main responsibilities of the Silver layer are:

- cleaning text values
- converting raw text into appropriate numeric and date data types
- handling missing or unusual source values
- standardising reference data
- reconciling differences between source systems
- filtering T-100 data to the required airline, service type and year
- aggregating operational data to the required analytical grain
- creating controlled mappings between aircraft coding systems
- filtering BTS Form 41 data to the relevant United domestic records
- converting BTS financial and activity measures from `(000)` units into normal units
- calculating reusable aircraft-level fuel and cost rates
- performing quality checks before the Gold layer

No aircraft recommendation logic is applied in Silver.

Business metrics such as:

```text
Passengers per Flight
Seats per Flight
Load Factor
Capacity Gap
Expected Candidate Load Factor
Range Feasibility
Aircraft Suitability
Candidate Ranking
Estimated Route Cost
```

belong in the Gold layer.

Silver instead creates the reliable facts and reference measures required to calculate them.

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
Cleaned, standardised and reusable analytical data
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

Gold asks:

> What business insights can be calculated from the cleaned data?

---

# 3. Silver Tables

The Silver layer currently contains seven tables:

```text
silver.united_fleet

silver.aircraft_types

silver.airports

silver.aircraft_range

silver.aircraft_mapping

silver.route_aircraft_monthly

silver.aircraft_operating_cost
```

These tables have different responsibilities and grains.

Two tables are particularly important analytical fact-style datasets:

```text
silver.route_aircraft_monthly
```

represents monthly route activity.

```text
silver.aircraft_operating_cost
```

represents quarterly aircraft economics.

The two datasets are deliberately kept separate in Silver because they describe different business processes and have different grains.

---

# 4. `silver.united_fleet`

## Purpose

Stores a cleaned version of United Airlines' 2025 mainline fleet reference.

Source:

```text
bronze.united_fleet_raw
```

The Bronze source stores several fields as text because some source values cannot be converted directly into numbers.

Examples include:

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

# 5. Why Split the Seat Configuration?

Some aircraft have a single reported seat capacity:

```text
166
```

Others have a range:

```text
167-203
```

Instead of retaining the range as text, Silver separates it into:

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

This preserves the source information while making both ends of the capacity range available for later aircraft suitability calculations.

---

# 6. Important Cleaning Functions

Several SQL functions are used repeatedly throughout the Silver transformation.

## `TRIM()`

Removes leading and trailing whitespace.

```sql
TRIM(aircraft_type)
```

For example:

```text
' 737-800 '
```

becomes:

```text
'737-800'
```

---

## `NULLIF()`

The pattern:

```sql
NULLIF(TRIM(value), '')
```

means:

> If the cleaned value is an empty string, return `NULL`.

This prevents blank text from being treated as meaningful data.

---

## `TRY_CAST()`

Safely attempts to convert a value into another data type.

```sql
TRY_CAST('141' AS INT)
```

returns:

```text
141
```

If conversion fails, `TRY_CAST()` returns `NULL` rather than stopping the complete Silver load.

This allows failed conversions to be identified through quality checks.

The common transformation pattern is:

```text
Raw Text
   ↓
TRIM
   ↓
NULLIF blank value
   ↓
TRY_CAST
   ↓
Clean typed value
```

---

## `CHARINDEX()`

Finds the position of a character inside text.

```sql
CHARINDEX('-', '167-203')
```

returns:

```text
4
```

because the hyphen appears at character position four.

---

## `LEFT()`

Extracts characters from the left side of text.

```sql
LEFT('167-203', 3)
```

returns:

```text
167
```

---

## `SUBSTRING()`

Extracts text beginning from a specified position.

It is used to obtain the second value from a seat range.

```text
167-203
    ↓
   203
```

---

# 7. `silver.aircraft_types`

## Purpose

Stores the cleaned BTS aircraft type reference.

Source:

```text
bronze.aircraft_types_raw
```

T-100 identifies aircraft using numerical codes rather than United fleet names.

Examples include:

```text
614
839
887
```

The aircraft type reference provides descriptive information associated with those codes.

Examples:

```text
614 → Boeing 737-800 family

839 → Boeing 737 MAX 9 family

887 → Boeing 787-8 family
```

Silver cleans the descriptive fields and converts available date fields into SQL `DATE` values.

This table remains useful as the general BTS reference, while `silver.aircraft_mapping` provides the controlled mapping specifically required by this project.

---

# 8. `silver.airports`

## Purpose

Stores cleaned airport reference information used to:

- identify route airports
- supply latitude and longitude
- support Power BI route mapping
- identify U.S. domestic routes
- match T-100 airport codes to the airport reference

Source:

```text
bronze.airports_raw
```

Useful fields include:

```text
airport_id
ident
source_iata_code
analysis_airport_code
airport_name
airport_type
municipality
iso_region
iso_country
latitude_deg
longitude_deg
scheduled_service
```

Latitude and longitude are converted from text into numeric values.

---

# 9. Airport Code Reconciliation

During Bronze profiling, one airport-code mismatch required controlled handling.

T-100 uses:

```text
PBI
```

for Palm Beach.

The relevant airport reference record is identified by:

```text
ident = KPBI
```

but the source IATA value did not provide the value required to match the 2025 T-100 data.

Bronze remains unchanged.

Silver preserves:

```text
source_iata_code
```

while also creating:

```text
analysis_airport_code
```

For most airports:

```text
source_iata_code       = EWR
analysis_airport_code  = EWR
```

For the Palm Beach exception:

```text
ident                  = KPBI
source_iata_code       = original source value
analysis_airport_code  = PBI
```

This provides both:

```text
Source traceability
+
Reliable analytical joining
```

---

# 10. `silver.aircraft_range`

## Purpose

Stores cleaned aircraft range reference information.

Source:

```text
bronze.aircraft_range_raw
```

Fields include:

```text
aircraft_type
range_nmi
range_km
range_basis
source_name
source_url
```

Range values are converted from text into numeric values.

The range reference later supports the Gold-layer question:

> Is the candidate aircraft's reference range sufficient for the route distance?

Range is not treated as a score.

An aircraft having more range does not automatically make it more suitable.

It is used as a high-level feasibility check.

---

# 11. Aircraft Range Units

The aircraft reference uses:

```text
nautical miles
```

while the T-100 route distance is treated in the project as:

```text
statute miles
```

The values therefore cannot be compared directly.

Gold converts aircraft range using approximately:

```text
1 nautical mile
≈
1.15078 statute miles
```

before evaluating route feasibility.

Silver preserves the clean manufacturer/reference values.

---

# 12. `silver.aircraft_mapping`

## Purpose

Different project sources describe aircraft differently.

T-100 and Form 41 use numerical BTS aircraft codes:

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

The mapping table creates a controlled bridge between those systems.

Example:

```text
BTS Code    Standard Aircraft    United Aircraft
--------    -----------------    ----------------
614         737-800              737-800
698         A319-100             A319-100
839         737 MAX 9            737 MAX 9
```

An important benefit of this design is reuse.

The same mapping can support:

```text
T-100 operational data
+
Form 41 aircraft economics data
```

because both sources contain BTS aircraft-type codes.

---

# 13. The 777-200 Mapping Limitation

An important source limitation exists for BTS aircraft type:

```text
627
```

BTS groups the aircraft at the wider:

```text
777-200 family
```

level.

United's fleet reference separately reports:

```text
777-200
777-200ER
```

The BTS code does not provide enough information to reliably distinguish the exact United subtype.

The controlled mapping therefore stores:

```text
aircraft_type_id = 627

standard_aircraft_type = 777-200 family

united_aircraft_type = NULL

mapping_status = Ambiguous
```

The project deliberately avoids inventing precision that the source data does not contain.

---

# 14. Why Not Map Code 627 Twice?

Creating:

```text
627 → 777-200

627 → 777-200ER
```

would create a one-to-many relationship.

An operational record such as:

```text
EWR → SFO
Aircraft 627
Passengers = 30,909
```

could incorrectly become:

```text
627 | 777-200   | 30,909

627 | 777-200ER | 30,909
```

The passenger measure would effectively be duplicated.

Maintaining one controlled mapping row avoids that problem.

The same limitation also applies when the Form 41 aircraft economics data uses code `627`.

---

# 15. `silver.route_aircraft_monthly`

## Purpose

This is the main operational Silver table.

Source:

```text
bronze.t100_segment_raw
```

The raw T-100 dataset can contain several records representing the same:

```text
year
month
origin
destination
aircraft type
```

Silver aggregates these source records into one analytical row.

---

# 16. Monthly Route Grain

The grain is:

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

remain separate.

This preserves directional demand differences.

---

# 17. Why Keep Month?

Monthly detail is central to the analysis because annual averages can hide seasonality.

For example:

```text
February
→ lower route demand

July
→ higher route demand

December
→ different demand pattern
```

The same aircraft could appear:

```text
Potentially Oversized in one month

Good Fit in another month

Capacity Tight during a peak period
```

Keeping month in Silver therefore allows Gold and Power BI to analyse changes throughout the year.

---

# 18. T-100 Filtering

The operational Silver table filters Bronze to:

```sql
WHERE unique_carrier = 'UA'

  AND class = 'F'

  AND year = 2025
```

This gives the project scope:

```text
United Airlines

2025

Relevant scheduled BTS Class F service
```

Other airlines and service types remain preserved in Bronze.

---

# 19. Why `SUM()` Is Used

Measures such as:

```text
passengers

seats

departures performed

departures scheduled

payload

freight

mail

air time

ramp-to-ramp time
```

represent activity that can be added across source records belonging to the same analytical group.

For example:

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
=
209 + 220 + 30,480
=
30,909
```

and:

```text
Performed Flights
=
1 + 1 + 126
=
128
```

---

# 20. Why Not `AVG(passengers)`?

Using:

```sql
AVG(passengers)
```

would calculate the average passengers per **Bronze source row**, not per actual performed flight.

For the previous example:

```text
(209 + 220 + 30,480) / 3
=
10,303
```

That does not represent meaningful average passenger demand per flight.

Silver therefore stores reliable totals.

Gold later calculates:

```text
Passengers per Flight
=
Total Passengers
/
Total Performed Flights
```

For the example:

```text
30,909 / 128
≈ 241.5 passengers per flight
```

---

# 21. Why `MAX(distance)` Is Used

Distance is not additive.

If three source records for the same route each contain:

```text
2,565 miles
```

then:

```sql
SUM(distance)
```

would incorrectly produce:

```text
7,695 miles
```

The route has not become three times longer.

Silver therefore uses:

```sql
MAX(distance)
```

to retain the route distance after aggregation.

---

# 22. `source_record_count`

The operational table contains:

```text
source_record_count
```

This is created using:

```sql
COUNT(*)
```

and records how many Bronze rows were combined into each Silver row.

For the January EWR → SFO aircraft 627 example:

```text
source_record_count = 3
```

This improves traceability and helps validate aggregation behaviour.

---

# 23. `silver.aircraft_operating_cost`

## Purpose

Stores cleaned quarterly aircraft operating economics for United Airlines domestic operations.

Source:

```text
bronze.aircraft_operating_cost_raw
```

The source is BTS Form 41 Schedule P-5.2.

The table contains measures related to:

```text
Aircraft fuel expense

Flying operations expense

Maintenance expense

Aircraft operating expense

Airborne hours

Aircraft days assigned

Fuel issued
```

Silver also calculates comparable rates on an airborne-hour basis.

---

# 24. Aircraft Economics Filtering

The Bronze P-5.2 source contains:

```text
Multiple airlines

Multiple operating regions

Generic aircraft records

Quarterly records
```

Silver restricts the source using:

```sql
WHERE TRIM(unique_carrier) = 'UA'

  AND year = 2025

  AND TRIM(region) = 'D'

  AND aircraft_type <> 999
```

This means the Silver table represents:

```text
United Airlines

2025

Domestic operating region

Specific aircraft types
```

---

# 25. Aircraft Economics Grain

The grain of:

```text
silver.aircraft_operating_cost
```

is:

> One year + one quarter + one BTS aircraft type.

For example:

```text
2025
Quarter 3
Aircraft type 614
```

represents one Silver row.

With:

```text
18 usable aircraft types
×
4 quarters
```

the expected table contains:

```text
72 rows
```

---

# 26. Why Keep Quarter?

The first design considered immediately aggregating all four quarters into one annual aircraft record.

However, keeping the quarterly grain provides more analytical flexibility.

The route data is monthly.

The economics data is quarterly.

This allows Gold to map months to the relevant quarter:

```text
January  → Q1
February → Q1
March    → Q1

April    → Q2
May      → Q2
June     → Q2

July     → Q3
August   → Q3
September→ Q3

October  → Q4
November → Q4
December → Q4
```

For example:

```text
July EWR → SFO
```

can use:

```text
Q3 aircraft economics
```

instead of applying one annual average to every month.

Keeping detail in Silver also means annual metrics can still be calculated later if required.

Aggregation is easy to perform later.

Lost quarterly detail cannot be recreated once removed.

---

# 27. P-5.2 Units

Several selected Schedule P-5.2 fields are reported in thousands.

Examples include measures reported as:

```text
$000

000 hours

000 days

000 gallons
```

Bronze preserves the raw values.

Silver converts them into normal units.

For example:

```text
Source:
109.43 thousand hours
```

becomes:

```text
109,430 hours
```

and:

```text
Source:
2,500 thousand dollars
```

becomes:

```text
$2,500,000
```

The general Silver conversion is:

```text
Source Value
×
1,000
=
Normal Unit
```

This makes downstream Gold and Power BI calculations easier to interpret.

---

# 28. Why Convert Units in Silver?

Silver is the appropriate layer for making source data analytically consistent.

Keeping fields such as:

```text
75,000 (000 gallons)
```

would require every later query and visual to remember the source scale.

Instead, Silver stores:

```text
75,000,000 gallons
```

This makes downstream fields self-explanatory.

Examples include:

```text
fuel_expense_dollars

total_air_hours

aircraft_days_assigned

fuel_issued_gallons
```

The column names communicate the actual stored unit.

---

# 29. Fuel Gallons per Airborne Hour

Silver calculates:

```text
Fuel Gallons per Air Hour
=
Fuel Issued Gallons
/
Total Air Hours
```

SQL conceptually performs:

```sql
fuel_issued_gallons
/
NULLIF(total_air_hours, 0)
```

This provides a common basis for comparing reported fuel use between aircraft types.

Because both source measures were originally reported in thousands:

```text
000 gallons
/
000 hours
```

the scaling would cancel mathematically.

However, the Silver calculation uses the fully converted normal-unit values for clarity and consistency.

---

# 30. Fuel Cost per Airborne Hour

Silver also calculates:

```text
Fuel Cost per Air Hour
=
Aircraft Fuel Expense
/
Total Air Hours
```

This differs from physical fuel burn.

Two separate measures are therefore retained:

```text
fuel_gallons_per_air_hour
```

and:

```text
fuel_cost_per_air_hour
```

One represents reported fuel quantity.

The other represents reported fuel expense.

---

# 31. Operating Cost per Airborne Hour

The primary broader economics metric is:

```text
Operating Cost per Air Hour
=
Total Aircraft Operating Expense
/
Total Air Hours
```

This provides a comparable aircraft-type measure that can later be combined with average route airborne time.

For example, Gold may calculate an estimated route-level comparison proxy:

```text
Average Route Air Time
×
Operating Cost per Air Hour
```

This will be a decision-support estimate rather than actual route accounting cost.

---

# 32. Maintenance Cost per Airborne Hour

Silver also calculates:

```text
Maintenance Cost per Air Hour
=
Flight Equipment Maintenance Expense
/
Total Air Hours
```

This gives an additional economics measure for deeper aircraft comparison.

It does not mean maintenance is caused only by airborne hours.

The metric simply normalises the reported quarterly expense onto a common activity basis.

---

# 33. Why Economics Rates Are Calculated in Silver

Earlier in the project, Silver deliberately avoided business metrics such as:

```text
Load Factor

Passengers per Flight

Capacity Gap

Aircraft Suitability
```

Those still belong in Gold.

The economics rates are slightly different.

Fields such as:

```text
fuel_gallons_per_air_hour

operating_cost_per_air_hour
```

are reusable **source-standardisation rates** derived directly from the P-5.2 measures.

They do not decide:

```text
which aircraft is best
```

or:

```text
whether an aircraft should operate a route
```

They simply convert the reported aircraft economics into a consistent comparison basis.

Therefore the architecture remains:

```text
SILVER

Clean facts
+
Reusable aircraft economics rates

        ↓

GOLD

Route metrics
+
Candidate comparison
+
Suitability
+
Ranking
+
Route cost proxy

        ↓

POWER BI

Decision-support reporting
```

---

# 34. Quarterly Economics Variation

The first Silver results demonstrate why retaining quarter is useful.

For example, aircraft code `612` showed variation in reported quarterly operating cost per airborne hour.

The purpose of preserving this variation is not to claim that aircraft efficiency physically changes every quarter.

Reported operating economics can also be influenced by:

```text
Utilisation

Fuel prices

Maintenance timing

Operating mix

Expense allocation

Other airline operating factors
```

Therefore these measures should be interpreted as:

> Reported United aircraft-type economics for that operating quarter.

They are not pure engineering performance specifications.

---

# 35. Relationship Between Monthly Routes and Quarterly Economics

The two main Silver datasets have different grains.

## Route performance

```text
year
+
month
+
origin
+
destination
+
aircraft_type
```

## Aircraft economics

```text
year
+
quarter
+
aircraft_type
```

Gold will relate them by:

```text
year
+
derived quarter
+
aircraft type
```

For example:

```text
Route Month:
July 2025

Derived Quarter:
Q3

Candidate:
737-800

        ↓

Use 2025 Q3 737-800 economics
```

This keeps each Silver table at its natural analytical grain.

---

# 36. Why Aircraft Names Are Not Duplicated in the Economics Table

`silver.aircraft_operating_cost` stores:

```text
aircraft_type_id
```

rather than repeatedly storing aircraft names.

Readable names can be obtained through:

```text
silver.aircraft_mapping
```

For example:

```text
614
↓
737-800
```

This avoids duplicating descriptive data and keeps one controlled mapping source.

---

# 37. Why Business Metrics Are Still Mostly Gold Logic

Silver stores clean reusable facts.

Examples from the route table include:

```text
passengers

seats

departures performed

route distance

air time
```

Examples from the economics table include:

```text
fuel issued

airborne hours

aircraft operating expense

fuel per airborne hour

operating cost per airborne hour
```

Gold calculates the business interpretation.

Examples include:

```text
Passengers per Flight

Seats per Flight

Load Factor

Capacity Gap

Expected Candidate Load Factor

Range Feasibility

Suitability Category

Candidate Rank

Estimated Route Operating-Cost Proxy
```

This prevents the clean-data layer from becoming mixed with route-specific decision logic.

---

# 38. Full Refresh Strategy

The Silver load uses a full-refresh approach.

Each Silver table follows the pattern:

```sql
TRUNCATE TABLE silver.table_name;

INSERT INTO silver.table_name
SELECT ...
FROM bronze.table_name;
```

`TRUNCATE` removes the existing data while preserving the table structure.

This prevents duplicate records when the load procedure is rerun.

For the current portfolio-scale dataset, this is simple, transparent and appropriate.

---

# 39. Silver Load Procedure

The complete load logic is stored in:

```text
06_proc_load_silver.sql
```

The procedure:

1. starts a timer
2. truncates each Silver table
3. transforms and reloads the datasets
4. cleans and standardises reference data
5. aggregates T-100 operational activity
6. filters and converts P-5.2 aircraft economics
7. calculates reusable quarterly economics rates
8. reports completion time
9. uses `TRY/CATCH` for error handling
10. rethrows failed loads using `THROW`

The complete Silver layer can be refreshed using:

```sql
EXEC silver.load_silver;
```

---

# 40. Silver Quality Checks

Quality checks are stored in:

```text
07_silver_quality_checks.sql
```

The checks validate both data conversion and analytical meaning.

Checks include:

```text
Fleet row counts

Failed fleet conversions

Seat range logic

Aircraft reference duplicates

Airport row reconciliation

Airport coordinate validation

Airport coverage

Aircraft range coverage

Aircraft mapping coverage

777-200 ambiguity review

Monthly route grain validation

Route NULL checks

Month validation

Negative-value checks

Zero-departure review

Bronze-to-Silver passenger reconciliation

Bronze-to-Silver seat reconciliation

Bronze-to-Silver departure reconciliation

Aircraft economics row count

Quarterly aircraft grain validation

Quarter coverage

Economics NULL checks

Positive-value checks

Aircraft mapping coverage for P-5.2

Fuel rate recalculation

Fuel cost rate recalculation

Operating cost rate recalculation

Maintenance rate recalculation

Filtered Bronze-to-Silver economics reconciliation
```

The purpose is not simply to prove that SQL executed successfully.

The checks test whether the resulting data is logically suitable for later analysis.

---

# 41. Economics Quality-Check Expectations

The current P-5.2 Silver subset is expected to contain:

```text
18 aircraft types

4 quarters per aircraft

72 total rows
```

The intended grain is:

```text
year
+
quarter
+
aircraft_type_id
```

The duplicate-grain check should therefore return:

```text
0 rows
```

Each aircraft should have:

```text
quarter_count = 4
```

The key derived economics measures should also be:

```text
non-NULL

positive
```

for the usable records.

---

# 42. Recalculating Derived Rates

An important quality-control approach is to independently recalculate the derived Silver rates.

For example:

```text
Stored Fuel Rate
```

should equal:

```text
fuel_issued_gallons
/
total_air_hours
```

within a small rounding tolerance.

Likewise:

```text
operating_cost_per_air_hour
```

should equal:

```text
aircraft_operating_expense_dollars
/
total_air_hours
```

This helps catch transformation errors even when the SQL procedure completes successfully.

---

# 43. Key Data Quality Principles

The Silver layer follows several principles:

```text
Do not alter Bronze source data.

Clean and standardise in Silver.

Use TRY_CAST so failed conversions remain detectable.

Use NULL rather than meaningless blank strings.

Preserve useful source fields for traceability.

Use controlled mappings for known source-system differences.

Do not guess when source data is ambiguous.

Aggregate measures according to their business meaning.

Validate the intended table grain.

Do not mix different grains unnecessarily.

Keep route decision logic in Gold.

Retain useful temporal detail when it may support later analysis.

Recalculate derived rates during quality testing.
```

---

# 44. Known Limitations

## BTS 777-200 Family

Aircraft code:

```text
627
```

cannot currently be reliably separated between:

```text
777-200
777-200ER
```

This remains explicitly marked as ambiguous.

The limitation affects both:

```text
T-100 operational records
```

and:

```text
Form 41 economics records
```

because both sources use the BTS aircraft classification.

---

## Aircraft Range

Manufacturer/reference range figures do not represent complete operational flight-planning capability.

Real-world usable range may depend on:

```text
Payload

Weather

Airport conditions

Fuel reserves

Aircraft configuration

Engine variant

Operational procedures
```

Range is therefore treated only as a high-level feasibility check.

---

## Seat Configuration

United reports some aircraft using seat ranges.

These are preserved using:

```text
seats_min

seats_max
```

rather than assuming one exact seat configuration.

---

## Aircraft Operating Economics

The new P-5.2 source improves the project by providing reported fuel and operating economics.

However, these values are:

```text
Aircraft-type level

Quarterly

Carrier-reported

Operating-region based
```

They are not:

```text
Exact route costs

Exact flight costs

Tail-level aircraft costs

Route profitability
```

The project therefore treats the economics information as comparison data rather than exact accounting.

---

## Domestic Operating Region

The P-5.2 table is filtered to:

```text
region = D
```

to align the economics source with the project's U.S. domestic route scope.

Some aircraft, especially widebody types, may have relatively less domestic activity than aircraft primarily used on domestic routes.

Their quarterly domestic economics may therefore be based on a different operating mix and activity volume.

This should be considered when interpreting comparisons.

---

## Quarterly Economics vs Monthly Demand

Route demand is monthly while economics are quarterly.

A monthly route record therefore uses the economics associated with its corresponding quarter.

For example:

```text
August
→ Q3
```

The economics are not month-specific.

---

## Cost Does Not Equal Profitability

Even with operating-cost data, the project does not model:

```text
Ticket revenue

Cargo revenue

Airport charges

Crew-specific route cost

Route-specific fuel price

Aircraft positioning

Connection value

Maintenance scheduling

Aircraft availability

Network opportunity cost
```

Therefore the project will not claim:

```text
"This aircraft is the most profitable aircraft for this route."
```

A more defensible interpretation is:

> This aircraft has a particular reported operating-cost profile among the viable capacity and range candidates.

---

# 45. SQL Skills Practised in Silver

The Silver layer provides practical experience with:

```text
CREATE TABLE

DROP TABLE IF EXISTS

CREATE OR ALTER PROCEDURE

TRUNCATE TABLE

INSERT INTO

SELECT

TRIM

NULLIF

TRY_CAST

CASE

CHARINDEX

LEFT

SUBSTRING

LEN

DATEFROMPARTS

SUM

MAX

COUNT

COUNT DISTINCT

GROUP BY

HAVING

WHERE

LEFT JOIN

UNION

NULL handling

DECIMAL conversion

Date conversion

Data-type standardisation

Controlled mappings

Grain analysis

Aggregation

Source reconciliation

Unit conversion

Rate calculations

Division-by-zero protection

Quality-control tolerances
```

---

# 46. Data-Modelling Concepts Practised

The Silver layer also reinforces broader data-engineering concepts.

## Grain

Each table has a clearly defined row meaning.

Examples:

```text
Route table:
one route-aircraft-month

Economics table:
one aircraft-quarter
```

---

## Reusable Reference Data

The aircraft mapping is shared across multiple datasets instead of rebuilding mapping logic each time.

---

## Separation of Concerns

```text
Bronze
Source preservation

Silver
Cleaning and reusable transformation

Gold
Business interpretation

Power BI
Presentation
```

---

## Additive vs Non-Additive Measures

Examples:

```text
Passengers
→ additive

Seats
→ additive

Distance
→ non-additive
```

---

## Different Source Grains

The project now combines sources at different levels:

```text
T-100
Monthly route-aircraft activity

P-5.2
Quarterly aircraft economics

Fleet
Aircraft-type reference

Range
Aircraft-type reference

Airports
Airport reference
```

Understanding the grain of each source prevents incorrect joins and duplicated measures.

---

# 47. Silver Output

After successful completion, the Silver layer contains:

```text
silver.united_fleet

silver.aircraft_types

silver.airports

silver.aircraft_range

silver.aircraft_mapping

silver.route_aircraft_monthly

silver.aircraft_operating_cost
```

Together these tables provide clean reusable data for:

```text
Route Demand

Aircraft Capacity

Airport Geography

Aircraft Range

Aircraft Mapping

Fuel Consumption

Operating Cost

Maintenance Cost
```

---

# 48. How Silver Supports Gold

The original Gold model uses:

```text
silver.route_aircraft_monthly
        +
silver.united_fleet
        +
silver.airports
        +
silver.aircraft_range
```

to calculate route-aircraft suitability.

The economics extension adds:

```text
silver.aircraft_operating_cost
```

The intended flow becomes:

```text
Route Demand
+
Fleet Capacity
+
Aircraft Range
+
Quarterly Aircraft Economics
        ↓
Gold Candidate Comparison
```

Gold can derive the correct quarter from the route month and attach the corresponding aircraft economics.

---

# 49. Planned Gold Economics Integration

For a route-month such as:

```text
July 2025
EWR → SFO
```

Gold can derive:

```text
Quarter = 3
```

Each candidate aircraft can then receive its Q3 economics values:

```text
Fuel Gallons per Air Hour

Fuel Cost per Air Hour

Operating Cost per Air Hour

Maintenance Cost per Air Hour
```

The existing suitability logic remains based primarily on:

```text
Demand

Capacity

Range
```

Economics adds an additional comparison dimension.

---

# 50. Estimated Route Operating-Cost Proxy

Because T-100 contains air-time information, Gold can calculate average route airborne time.

Conceptually:

```text
Average Air Time per Flight
=
Total Air Time
/
Performed Flights
```

Then:

```text
Estimated Route Operating-Cost Proxy
=
Average Air Time in Hours
×
Candidate Operating Cost per Air Hour
```

This gives a comparable estimate across candidate aircraft.

It should not be interpreted as exact route accounting cost.

---

# 51. Why Economics Should Not Automatically Override Suitability

The decision sequence should remain logical.

```text
1. Can the aircraft cover the route distance?

2. Can the aircraft accommodate observed passenger demand?

3. How closely does capacity match demand?

4. What are the economics of the viable alternatives?
```

A cheaper aircraft is not useful if:

```text
its range is insufficient
```

or:

```text
its capacity is too small
```

Therefore fuel and cost information extends the decision rather than replacing the existing capacity and range logic.

---

# 52. Silver Outcome

At the end of the Silver stage:

```text
Raw Bronze Sources
        ↓
Clean Text
        ↓
Convert Data Types
        ↓
Reconcile Airport Codes
        ↓
Create Aircraft Mapping
        ↓
Aggregate T-100 to Monthly Route-Aircraft Grain
        ↓
Filter P-5.2 to United Domestic Operations
        ↓
Convert P-5.2 (000) Units
        ↓
Preserve Quarterly Aircraft Economics
        ↓
Calculate Reusable Fuel / Cost Rates
        ↓
Validate Both Analytical Grains
        ↓
Reconcile Bronze and Silver
        ↓
Provide Reliable Inputs to Gold
```

The Silver layer now supports two major analytical components.

## Operational Route Data

```text
Demand

Capacity Supplied

Departures

Distance

Air Time

Seasonality
```

## Aircraft Economics

```text
Fuel Use

Fuel Expense

Operating Expense

Maintenance Expense

Aircraft Utilisation
```

---

# 53. Next Layer

The Gold layer transforms the Silver data into business-facing analytical outputs.

Existing Gold metrics include:

```text
Passengers per Flight

Seats per Flight

Load Factor

Capacity Gap

Expected Candidate Load Factor

Range Feasibility

Suitability Category

Candidate Ranking

Best-Fit Candidate(s)
```

The aircraft economics extension will add measures such as:

```text
Quarter

Fuel Gallons per Air Hour

Fuel Cost per Air Hour

Operating Cost per Air Hour

Maintenance Cost per Air Hour

Average Route Air Time

Estimated Route Operating-Cost Proxy
```

The final analytical question is evolving from:

> Which aircraft in United's existing fleet appears best suited to each U.S. domestic route based on demand, capacity and distance?

to a broader decision-support question:

> Which aircraft appear operationally suitable based on demand, capacity and range, and what fuel and operating-cost trade-offs exist between the viable alternatives?

The output remains a decision-support model rather than a complete airline scheduling or profitability optimisation system.
