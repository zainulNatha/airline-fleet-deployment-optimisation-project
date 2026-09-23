# Gold Layer

## 1. Purpose

The Gold layer converts the cleaned and standardised Silver data into business-ready analytical outputs.

The Bronze layer answers:

> What data did the source provide?

The Silver layer answers:

> How should the data be cleaned, standardised and structured?

The Gold layer answers:

> What does the cleaned data mean for the business question?

The primary suitability question for this project is:

> For each U.S. domestic route, which aircraft in United Airlines' existing fleet appears best suited based on passenger demand, aircraft capacity and route distance?

The project was later extended with aircraft operating economics.

A second analytical question is therefore:

> Among the aircraft that appear operationally viable, what fuel and operating-cost trade-offs exist?

This distinction is important.

The current ranking model is still primarily based on:

```text
Demand
+
Capacity
+
Range
```

Aircraft economics provide additional decision-support context.

They do not currently replace the original suitability logic.

---

# 2. Gold Architecture

The Gold layer follows this flow:

```text
silver.route_aircraft_monthly
        +
silver.airports
        ↓
gold.route_monthly_summary
        ↓
gold.route_aircraft_candidates
        ↑
        │
silver.united_fleet
silver.aircraft_range
silver.aircraft_mapping
silver.aircraft_operating_cost
        ↓
gold.route_aircraft_suitability
        ↓
gold.route_aircraft_ranked
        ↓
gold.route_aircraft_best_fit
        ↓
Power BI
```

The five Gold views are:

```text
gold.route_monthly_summary

gold.route_aircraft_candidates

gold.route_aircraft_suitability

gold.route_aircraft_ranked

gold.route_aircraft_best_fit
```

---

# 3. Why Gold Uses Views

Bronze and Silver primarily use physical tables.

Gold primarily uses views.

This is intentional.

Bronze physically stores raw source data.

Silver physically stores cleaned and standardised reusable data.

Gold mainly performs:

```text
aggregation

business calculations

candidate comparisons

classification

ranking

reporting logic
```

These calculations can be derived dynamically from the stable Silver layer.

Using views avoids unnecessarily duplicating the same underlying data.

For the scale of this portfolio project, views provide a simple and transparent analytical layer.

In a larger production environment, Gold tables or materialised outputs could become appropriate if:

```text
query cost became high

calculations became expensive

historical snapshots were required

performance requirements changed
```

Views are therefore a project design choice rather than a universal rule.

---

# 4. Gold Business Logic

The analytical process can be summarised as:

```text
Monthly Route Demand
        ↓
Compare Against Every Fleet Aircraft
        ↓
Check Capacity
        ↓
Check Range
        ↓
Classify Suitability
        ↓
Rank Viable Candidates
        ↓
Attach Fuel / Cost Context
        ↓
Power BI Decision Support
```

Aircraft economics do not make an aircraft viable.

For example:

```text
Cheap aircraft
+
Insufficient capacity
=
Still Too Small
```

and:

```text
Cheap aircraft
+
Insufficient range
=
Still Not Suitable for Route Distance
```

Feasibility and capacity remain the first decision layers.

---

# 5. `gold.route_monthly_summary`

## Purpose

The first Gold view summarises monthly demand at route level.

The Silver operational grain is:

```text
year
+
month
+
origin
+
destination
+
aircraft type
```

Gold removes aircraft type from the grouping.

The resulting grain is:

```text
year
+
month
+
origin
+
destination
```

This means one row represents one directional route-month.

For example:

```text
2025
July
EWR
SFO
```

represents total July demand on:

```text
EWR → SFO
```

across all aircraft types historically used on that route.

---

# 6. Why Aircraft Type Is Removed

The purpose of the route summary is to answer:

> How much passenger demand existed on this route during this month?

It is not asking:

> How many passengers were associated with one particular historically operated aircraft?

If several aircraft types operated EWR → SFO during July, their passengers and seats must first be combined to understand total route demand.

---

# 7. U.S. Domestic Route Filter

The airport reference is joined twice:

```text
origin airport

destination airport
```

The Gold view keeps only records where:

```text
origin country = US

AND

destination country = US
```

This implements the project scope:

```text
United Airlines
2025
U.S. Domestic Nonstop Routes
```

International routes remain available in Silver but are excluded from the Gold route analysis.

---

# 8. Monthly Route Measures

The route summary contains measures such as:

```text
total_passengers

total_seats

departures_scheduled

departures_performed

route_distance_miles

passengers_per_flight

seats_per_flight

load_factor_pct
```

The additive measures use:

```sql
SUM()
```

Route distance uses:

```sql
MAX()
```

because distance is not additive.

---

# 9. Passengers per Flight

The calculation is:

```text
Total Passengers
----------------
Performed Flights
```

SQL uses:

```sql
NULLIF(
    SUM(departures_performed),
    0
)
```

to prevent division by zero.

For example:

```text
59,543 passengers
/
287 flights
≈
207.47 passengers per flight
```

This is the demand measure later compared against candidate aircraft capacity.

---

# 10. Seats per Flight

The calculation is:

```text
Total Seats
-----------
Performed Flights
```

This describes the average seat capacity historically supplied on the route during the month.

It provides useful context when comparing:

```text
historical capacity supplied
```

against:

```text
candidate capacity
```

---

# 11. Observed Load Factor

Load factor is calculated as:

```text
Passengers
----------
Seats
× 100
```

This measures how much of the historically supplied capacity was occupied.

It is different from:

```text
Expected Candidate Load Factor
```

which is calculated later for hypothetical candidate aircraft.

---

# 12. Why Load Factor Alone Is Not Enough

A route can have higher passengers per flight but a lower load factor if significantly more seats were supplied.

For example:

```text
Month A

225 passengers per flight
256 seats per flight

≈ 88% load factor
```

may have more passenger demand than:

```text
Month B

212 passengers per flight
224 seats per flight

≈ 95% load factor
```

Load factor therefore reflects both:

```text
Demand
+
Capacity supplied
```

It should not be interpreted as passenger demand alone.

---

# 13. Quarter

The economics source is quarterly while route demand is monthly.

Gold derives:

```text
quarter
```

from:

```text
month_start_date
```

The mapping is:

```text
January   → Q1
February  → Q1
March     → Q1

April     → Q2
May       → Q2
June      → Q2

July      → Q3
August    → Q3
September → Q3

October   → Q4
November  → Q4
December  → Q4
```

This allows monthly route records to use economics from the corresponding quarter.

---

# 14. Route Air Time

The route summary now also retains:

```text
total_air_time_minutes
```

and calculates:

```text
average_air_time_minutes_per_flight
```

using:

```text
Total Air Time
--------------
Performed Flights
```

The candidate view later converts this into hours.

This is required because the aircraft economics rates are reported on an airborne-hour basis.

---

# 15. Important Air-Time Assumption

The route air time is observed from the aircraft that actually operated the route.

The project then uses that route average as a common time basis when comparing candidate aircraft.

This creates a useful comparison proxy but is not a detailed flight-performance model.

Different aircraft may have slightly different:

```text
cruise speeds

climb profiles

descent profiles

routing performance
```

Therefore:

```text
average route air time
×
candidate hourly economics
```

should be interpreted as a comparison estimate rather than an exact predicted block cost.

---

# 16. `gold.route_aircraft_candidates`

## Purpose

This view compares every route-month against every aircraft type in United's mainline fleet.

The grain is:

```text
year
+
month
+
origin
+
destination
+
candidate aircraft
```

A:

```sql
CROSS JOIN
```

is used between:

```text
gold.route_monthly_summary
```

and:

```text
silver.united_fleet
```

---

# 17. Why CROSS JOIN Is Used

A normal join connects rows that already share a matching key.

That is not the question here.

The model needs to ask:

> What would every United aircraft look like if considered for every route-month?

Therefore:

```text
Route A
×
737-700

Route A
×
737-800

Route A
×
A321neo

Route A
×
787-8

...
```

Every route-month is deliberately paired with every United fleet aircraft type.

This creates the complete candidate comparison set.

---

# 18. Candidate Capacity Gap

Two capacity-gap measures are calculated:

```text
capacity_gap_min

capacity_gap_max
```

Formula:

```text
Candidate Seats
-
Passengers per Flight
```

For example:

```text
Passengers per Flight = 212

Candidate Seats = 231
```

produces:

```text
231 - 212
=
+19 seats
```

A positive result means spare capacity.

A negative result means average passenger demand exceeds candidate capacity.

---

# 19. Why Both Minimum and Maximum Seat Capacity Are Kept

Some United aircraft are reported using seat ranges.

For example:

```text
167-203 seats
```

The model therefore calculates:

```text
capacity_gap_min
```

and:

```text
capacity_gap_max
```

rather than pretending that one exact configuration applies to every aircraft.

This preserves the source limitation.

---

# 20. Expected Candidate Load Factor

The model calculates:

```text
expected_load_factor_min_seats
```

and:

```text
expected_load_factor_max_seats
```

Formula:

```text
Passengers per Flight
---------------------
Candidate Seats
× 100
```

For example:

```text
Passenger demand = 150

Candidate capacity = 166
```

gives:

```text
150 / 166 × 100
≈ 90.4%
```

This asks:

> If observed average demand remained unchanged, what percentage of this candidate aircraft's seats would be occupied?

---

# 21. Expected Load Factor Above 100%

An expected load factor greater than 100% is not interpreted as a real achievable load factor.

It means:

> Average observed demand exceeds the candidate aircraft's capacity.

For example:

```text
Passenger demand = 212

Aircraft capacity = 166

Expected load factor ≈ 128%
```

This is evidence that the aircraft appears too small for average observed demand.

---

# 22. Aircraft Range

The aircraft range reference is stored in nautical miles.

T-100 route distance is represented in statute miles.

Gold converts range using:

```text
1 nautical mile
≈
1.15078 statute miles
```

The candidate view then compares:

```text
candidate reference range
```

against:

```text
route distance
```

---

# 23. Range Feasibility

The range result is:

```text
Yes

No

Unknown
```

The calculation is intentionally a high-level reference check.

It does not model:

```text
payload

weather

fuel reserves

runway conditions

aircraft configuration

operational routing
```

Therefore:

```text
range_feasible = Yes
```

means:

> The reference range appears sufficient for the route distance.

It does not mean:

> The aircraft is operationally guaranteed to fly the route under every condition.

---

# 24. Aircraft Economics Join

The candidate view also attaches:

```text
fuel_gallons_per_air_hour

fuel_cost_per_air_hour

operating_cost_per_air_hour

maintenance_cost_per_air_hour
```

from:

```text
silver.aircraft_operating_cost
```

The economics join uses:

```text
year
+
quarter
+
aircraft type
```

This means a July route uses:

```text
Q3 economics
```

while a February route uses:

```text
Q1 economics
```

---

# 25. Why Economics Are Quarterly

BTS Form 41 Schedule P-5.2 is quarterly.

Silver deliberately preserves this useful temporal detail instead of immediately creating one annual average.

Gold can therefore combine:

```text
monthly route demand
```

with:

```text
quarterly aircraft economics
```

while respecting both source grains.

---

# 26. Reusing the Aircraft Mapping

The United fleet reference identifies aircraft using names such as:

```text
737-800

A319-100

787-9
```

P-5.2 uses BTS aircraft codes.

Gold therefore uses:

```text
silver.aircraft_mapping
```

to bridge the two systems.

This controlled mapping is the same mapping already used elsewhere in the project.

---

# 27. 777-200 Family Economics Limitation

BTS aircraft code:

```text
627
```

represents the wider:

```text
777-200 family
```

United's fleet source separately identifies:

```text
777-200

777-200ER
```

The source does not provide enough information to confidently assign the family-level economics to either exact subtype.

Therefore the project deliberately leaves economics as:

```text
NULL
```

for:

```text
777-200

777-200ER
```

rather than inventing a false exact mapping.

This is a documented source limitation, not a failed join.

---

# 28. Estimated Fuel Gallons per Flight

The candidate view calculates:

```text
Estimated Fuel Gallons per Flight
```

using:

```text
Average Route Air Time in Hours
×
Fuel Gallons per Air Hour
```

For example:

```text
Average route time = 5.43 hours

Fuel rate = 690 gallons/hour
```

produces approximately:

```text
3,747 gallons
```

This is a comparison proxy.

It is not an aircraft flight-planning fuel calculation.

---

# 29. Estimated Fuel Cost per Flight

The calculation is:

```text
Average Route Air Time
×
Fuel Cost per Air Hour
```

This allows alternative aircraft to be compared on a common route-time basis.

It does not model airport-specific fuel prices or exact uplift decisions.

---

# 30. Estimated Operating Cost per Flight

The main economics proxy is:

```text
Estimated Operating Cost per Flight
```

Formula:

```text
Average Route Air Time in Hours
×
Operating Cost per Air Hour
```

This is designed to answer:

> If these aircraft were compared using the same observed route airborne time, how do their reported operating-cost profiles differ?

It should not be described as:

```text
Exact flight cost

Exact route cost

Profitability
```

---

# 31. Estimated Maintenance Cost per Flight

The model also calculates:

```text
Estimated Maintenance Cost per Flight
```

using:

```text
Average Route Air Time
×
Maintenance Cost per Air Hour
```

This provides additional economics context but is not used in suitability ranking.

---

# 32. `gold.route_aircraft_suitability`

## Purpose

The suitability view converts candidate metrics into understandable business categories.

The categories are:

```text
Not Suitable for Route Distance

Too Small

Capacity Tight

Good Fit

Potentially Oversized
```

The view carries the economics fields forward but does not currently use them in classification.

---

# 33. Suitability Rule Order

The `CASE` statement is evaluated in order.

The current logic is:

```text
1. Range failure
        ↓
Not Suitable for Route Distance

2. Expected LF > 100%
        ↓
Too Small

3. Expected LF > 95%
        ↓
Capacity Tight

4. Expected LF >= 75%
        ↓
Good Fit

5. Otherwise
        ↓
Potentially Oversized
```

Rule order matters.

For example, an aircraft with suitable capacity but insufficient range should still be:

```text
Not Suitable for Route Distance
```

because the range test has priority.

---

# 34. Why Maximum Seat Configuration Is Used for Headline Suitability

For aircraft with a seating range, the suitability category uses:

```text
expected_load_factor_max_seats
```

This effectively gives the aircraft the most favourable reported capacity configuration.

For example:

```text
167-203 seats
```

uses:

```text
203 seats
```

for the headline classification.

The minimum-seat calculations remain available for additional context.

---

# 35. Suitability Thresholds

The project uses:

```text
Expected LF > 100%
→ Too Small

Expected LF > 95% and <= 100%
→ Capacity Tight

Expected LF >= 75% and <= 95%
→ Good Fit

Expected LF < 75%
→ Potentially Oversized
```

These are analytical assumptions created for this portfolio project.

They are not presented as official United Airlines or industry fleet-planning rules.

This assumption is deliberately transparent and easy to explain.

---

# 36. Why No 0-100 Optimisation Score Is Used

The project does not create an arbitrary weighted score such as:

```text
Capacity = 40%

Range = 30%

Cost = 20%

Fleet Size = 10%
```

because those weights would introduce assumptions that are difficult to justify with the available data.

Instead, the model uses transparent rules that can be explained individually.

This makes the output easier to defend in a stakeholder or interview discussion.

---

# 37. `gold.route_aircraft_ranked`

## Purpose

The ranking view keeps only viable candidates and ranks them within each route-month.

Excluded categories are:

```text
Too Small

Not Suitable for Route Distance
```

The remaining candidates are:

```text
Good Fit

Capacity Tight

Potentially Oversized
```

---

# 38. Suitability Priority

The ranking assigns:

```text
Good Fit
→ 1

Capacity Tight
→ 2

Potentially Oversized
→ 3
```

These values are:

```text
sorting priorities
```

not:

```text
business scores
```

Their purpose is simply to control ranking order.

---

# 39. Capacity Gap as the Second Ranking Rule

Within each suitability category, candidates are ordered by:

```text
capacity_gap_max ASC
```

This means the model prefers the aircraft whose capacity most closely exceeds observed passenger demand.

For example:

```text
Aircraft A
Gap = +18 seats

Aircraft B
Gap = +30 seats
```

Aircraft A is treated as the closer capacity fit.

---

# 40. `PARTITION BY`

Ranking uses:

```sql
PARTITION BY
    year,
    month,
    origin,
    destination
```

This means ranking restarts independently for every route-month.

For example:

```text
July EWR → SFO
```

has its own:

```text
Rank 1
Rank 2
Rank 3
...
```

and:

```text
July IAH → LAX
```

starts again from:

```text
Rank 1
```

---

# 41. Why `DENSE_RANK()` Is Used

`DENSE_RANK()` allows genuine ties.

If two aircraft have:

```text
same suitability category

same capacity gap
```

they can both receive:

```text
candidate_rank = 1
```

Using:

```sql
ROW_NUMBER()
```

would force SQL Server to choose one aircraft over another even when the available criteria do not justify that distinction.

The project deliberately avoids arbitrary ranking.

---

# 42. Known Tie Example

For:

```text
January 2025
ABE → EWR
```

the model identified:

```text
737-700

A319-100
```

Both have:

```text
126 seats
```

For the route demand, they therefore have:

```text
identical capacity gap

identical expected load factor

same suitability category
```

Both legitimately receive:

```text
candidate_rank = 1
```

The economics data may show that their reported costs differ.

However, economics currently remain comparison information rather than an automatic tie-breaker.

---

# 43. Why Economics Do Not Yet Break Ranking Ties

It would be technically possible to add:

```text
operating cost
```

as another ranking rule.

However, that would imply:

> Lowest reported operating-cost proxy should automatically determine the preferred aircraft.

The available data does not fully support that conclusion.

Actual deployment also depends on:

```text
aircraft availability

crew

maintenance

rotations

network requirements

airport constraints

revenue implications
```

The current model therefore keeps:

```text
Suitability Ranking
```

separate from:

```text
Economic Comparison
```

This gives stakeholders more information without overstating the recommendation.

---

# 44. Example: Capacity Fit vs Economics

A route may produce:

```text
Aircraft A
Rank 1
Excellent capacity fit
Estimated operating cost = higher

Aircraft B
Rank 2
Slightly more spare capacity
Estimated operating cost = lower
```

This is useful decision-support information.

The model does not hide the trade-off by collapsing everything into one opaque score.

---

# 45. `gold.route_aircraft_best_fit`

## Purpose

The final reporting-ready view keeps:

```text
candidate_rank = 1
```

It provides a simpler output for Power BI.

However, because the model uses:

```text
DENSE_RANK()
```

the view may contain more than one row per route-month.

---

# 46. Best-Fit View Grain

The grain is therefore more accurately described as:

```text
year
+
month
+
origin
+
destination
+
joint best-fit candidate
```

rather than always:

```text
one row per route-month
```

For a route with one clear top candidate:

```text
one row
```

For a route with two tied candidates:

```text
two rows
```

This behaviour is intentional.

---

# 47. Best-Fit Economics

The final view includes:

```text
fuel_gallons_per_air_hour

fuel_cost_per_air_hour

operating_cost_per_air_hour

maintenance_cost_per_air_hour

estimated_fuel_gallons_per_flight

estimated_fuel_cost_per_flight

estimated_operating_cost_per_flight

estimated_maintenance_cost_per_flight
```

This allows Power BI to show both:

```text
Why the aircraft fits
```

and:

```text
What its reported economic profile looks like
```

---

# 48. EWR → SFO Worked Example

EWR → SFO is used throughout the project as a worked example.

The route demonstrates that monthly demand changes throughout the year.

Different months therefore produce different best-fit candidates.

Examples observed during testing included:

```text
A321neo

767-300ER

767-400ER

787-8
```

depending on monthly passenger demand.

This demonstrates why preserving monthly seasonality was important.

---

# 49. EWR → SFO Economics Example

For July 2025, the model uses:

```text
Q3 economics
```

because July belongs to:

```text
Quarter 3
```

A candidate such as the 767-400ER can therefore be evaluated using:

```text
capacity fit

expected load factor

range feasibility

fuel gallons per air hour

operating cost per air hour

estimated operating cost per flight
```

The route example demonstrates that:

> The closest capacity match is not necessarily the lowest-cost viable candidate.

That is one of the most valuable insights added by the economics extension.

---

# 50. Gold Quality Checks

Gold quality checks are stored in:

```text
09_gold_quality_checks.sql
```

The checks validate:

```text
Route-summary grain

Domestic-route filtering

Metric sanity

CROSS JOIN row expansion

Candidate grain

Capacity-gap calculation

Expected-load-factor calculation

Range categories

Suitability categories

Suitability thresholds

Ranking exclusions

Rank-1 coverage

Routes with no viable candidate

Best-fit rank

Tied best-fit candidates

Known tie examples

Quarter mapping

Average air-time calculation

Economics coverage

Known 777 economics limitation

Estimated fuel calculation

Estimated operating-cost calculation

Negative economics values

Best-fit economics coverage
```

---

# 51. Why Candidate Row Count Is Checked

The candidate view should contain:

```text
Number of Route-Months
×
Number of United Fleet Aircraft Types
```

This is particularly important after adding aircraft economics.

A bad economics join could accidentally create:

```text
multiple economics rows
```

for one candidate and duplicate the candidate dataset.

Comparing expected and actual row counts helps detect that problem.

---

# 52. Why Economics Coverage Is Checked

The candidate view explicitly checks which aircraft have:

```text
operating_cost_per_air_hour IS NULL
```

The expected documented gaps are:

```text
777-200

777-200ER
```

because of BTS aircraft code 627.

Any other aircraft with missing economics would require investigation.

---

# 53. Why Proxy Calculations Are Recalculated

Quality checks independently recalculate:

```text
estimated fuel gallons per flight
```

and:

```text
estimated operating cost per flight
```

from their underlying components.

For example:

```text
Stored Estimated Operating Cost
```

is compared with:

```text
Average Air Time Hours
×
Operating Cost per Hour
```

A small tolerance is allowed for decimal rounding.

This tests the calculation rather than merely checking whether the column is populated.

---

# 54. Power BI Reporting Story

The Gold model is intended to support a small number of clear report pages rather than one overloaded dashboard.

The planned report story is:

```text
Page 1
Executive Overview

        ↓

Page 2
Route Deep Dive

        ↓

Page 3
Fleet / Economics Insights
```

A methodology panel or hidden information page can explain:

```text
data sources

threshold assumptions

model limitations
```

without disrupting the main stakeholder story.

---

# 55. Executive Overview

The first page should answer:

> Where should a stakeholder pay attention?

Potential visuals include:

```text
Total passengers

Average load factor

Routes analysed

Suitability distribution

Domestic route map

Monthly demand trend

Routes requiring review
```

The purpose is to provide the network-level picture before asking the user to investigate one route.

---

# 56. Route Deep Dive

The route page should allow the user to select:

```text
Origin

Destination

Month
```

The story should flow from:

```text
Current Route Performance
        ↓
Aircraft Historically Operated
        ↓
Suitable Alternatives
        ↓
Capacity / Range Comparison
        ↓
Fuel / Cost Trade-Off
```

This page is expected to be the main decision-support page.

---

# 57. Current Aircraft vs Alternatives

A key Power BI requirement is to show:

```text
What aircraft is currently being used?
```

alongside:

```text
What alternative aircraft appear suitable?
```

The comparison can include:

```text
Aircraft Type

Seats

Passengers per Flight

Expected Load Factor

Capacity Gap

Range Feasible

Fuel per Hour

Operating Cost per Hour

Estimated Operating Cost per Flight

Suitability Category

Candidate Rank
```

This makes the recommendation understandable rather than presenting only a final aircraft name.

---

# 58. Fleet / Economics Insights

The fleet page can compare aircraft across:

```text
Fuel Burn

Operating Cost

Maintenance Cost

Seat Capacity

Range
```

This helps explain why aircraft with similar capacities may have different reported economics.

For example:

```text
737-700

vs

A319-100
```

may look identical from a seating perspective but different from an operating-cost perspective.

---

# 59. Important Economics Interpretation

The model should not claim:

```text
Aircraft X will save United exactly $Y.
```

The economics are based on:

```text
quarterly aircraft-type averages

domestic operating-region data

average observed route airborne time
```

A better description is:

> Estimated operating-cost proxy based on reported quarterly United aircraft-type economics and observed average route airborne time.

---

# 60. What the Model Does Not Include

The current project does not model:

```text
Tail-level aircraft assignment

Aircraft location

Crew rotations

Crew costs by route

Maintenance scheduling

Airport gate constraints

Runway-performance calculations

Weather

Exact payload restrictions

Route-specific fuel prices

Passenger revenue

Cargo revenue

Connection value

Schedule optimisation

Aircraft substitution recovery

Exact flight profitability
```

These factors matter in real fleet planning.

They remain outside the current project scope.

---

# 61. Why the Project Is Still Useful

The model is not intended to replace airline fleet-planning systems.

It demonstrates a first-pass analytical framework that can:

```text
identify route demand

measure seasonality

compare capacity

test high-level range feasibility

classify aircraft suitability

rank viable alternatives

surface ties honestly

add aircraft economics context

explain assumptions transparently
```

This makes it useful as a decision-support and portfolio analytics project.

---

# 62. SQL Concepts Practised in Gold

The Gold layer uses concepts including:

```text
CREATE OR ALTER VIEW

SUM

MAX

CAST

NULLIF

CASE

INNER JOIN

LEFT JOIN

CROSS JOIN

GROUP BY

WHERE

CTEs

DENSE_RANK

PARTITION BY

ORDER BY

DATEPART

ABS

COUNT

COUNT DISTINCT
```

It also practises broader analytical concepts such as:

```text
grain

additive vs non-additive measures

candidate generation

rule-based classification

transparent ranking

tie handling

temporal grain alignment

economic normalisation

proxy calculations

data-quality reconciliation
```

---

# 63. Gold Output

The final Gold flow is:

```text
Monthly Route Demand
        ↓
Candidate Generation
        ↓
Capacity Comparison
        ↓
Range Feasibility
        ↓
Quarterly Economics Join
        ↓
Suitability Classification
        ↓
Candidate Ranking
        ↓
Best-Fit / Joint Best-Fit Output
        ↓
Power BI
```

The project now provides both:

```text
Operational Suitability
```

and:

```text
Economic Comparison Context
```

without combining them into an unsupported single optimisation score.

---

# 64. Final Interpretation

The final output should be interpreted as:

> A transparent first-pass assessment of which United fleet aircraft appear suitable for each monthly U.S. domestic route based on observed passenger demand, reported seat capacity and reference range, with quarterly fuel and operating-cost information added to help compare viable alternatives.

It should not be interpreted as:

> A definitive operational scheduling instruction or exact profitability recommendation.

That distinction is central to keeping the project analytically defensible.
