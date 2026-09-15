# Aircraft Route Suitability Analysis

### United Airlines Case Study | SQL · Data Modelling · Power BI

## Project Overview

This project explores a simple airline planning question:

> **Which aircraft within an airline's existing fleet is best suited to each route?**

United Airlines will be used as the case study.

The analysis will compare:

- Passenger demand
- Aircraft seating capacity
- Route distance
- Monthly demand patterns
- Current aircraft used on each route

The aim is to identify whether the aircraft currently operating a route appears appropriately matched to demand and, where it may not be, identify other aircraft within the existing fleet that could provide a better fit.

This is designed as a **decision-support analysis**, not a complete airline scheduling or fleet optimisation system.

---

## Business Question

> **For each route, which aircraft in the airline's existing fleet appears best suited based on passenger demand, aircraft capacity and route distance?**

Supporting questions:

- How many passengers typically travel on each flight?
- How many seats are currently being provided?
- Is the current aircraft too small, appropriately sized or potentially too large?
- Does passenger demand change significantly throughout the year?
- Which other aircraft within the fleet could operate the route?
- Which aircraft provides the closest match between observed demand and available capacity?

---

## Business Value

Airlines operate large numbers of routes using multiple aircraft types.

This analysis aims to help identify:

- Routes where aircraft capacity appears well matched to demand
- Routes where capacity may be consistently tight
- Routes where excess capacity may be regularly provided
- Alternative aircraft that may provide a closer capacity-to-demand fit

The output is intended to give fleet-planning teams a focused starting point for further investigation.

---

## Project Scope

| Area | Scope |
|---|---|
| Airline | United Airlines |
| Period | 2025 |
| Geography | U.S. domestic routes |
| Fleet | United mainline fleet |
| Data frequency | Monthly |
| Analysis | SQL |
| Data modelling | Dimensional model |
| Visualisation | Power BI |

---

## Core Metrics

### Passengers
Total passengers transported on a route.

### Available Seats
Total passenger seats supplied.

### Load Factor

`Load Factor = Passengers / Available Seats`

Shows how much of the available seat capacity was used.

### Passengers per Flight

`Passengers per Flight = Passengers / Departures Performed`

Shows average passenger demand for an operated flight.

### Seats per Flight

`Seats per Flight = Available Seats / Departures Performed`

Shows average capacity being supplied per flight.

### Capacity Gap

`Capacity Gap = Aircraft Seats - Passengers per Flight`

Helps identify whether an aircraft may be too small or larger than required for observed demand.

### Expected Load Factor

`Expected Load Factor = Passengers per Flight / Candidate Aircraft Seats`

Used to estimate how another aircraft could fit the same observed passenger demand.

### Route Distance

Used to check whether candidate aircraft are suitable for the route.

### Monthly Demand

Demand and capacity will also be analysed by month.

This helps identify whether aircraft suitability changes throughout the year because of seasonality.

---

## Aircraft Suitability Logic

The first version will use simple and explainable rules.

For each route:

1. Identify the average passenger demand per flight.
2. Identify the aircraft currently operating the route.
3. Compare the route against aircraft already within United's mainline fleet.
4. Remove aircraft that do not have sufficient route capability.
5. Compare passenger demand with aircraft seating capacity.
6. Identify aircraft that provide the closest reasonable capacity match.
7. Review monthly demand to ensure the recommendation is not based only on an annual average.

Aircraft may be classified as:

- **Too Small**
- **Capacity Tight**
- **Good Fit**
- **Potentially Oversized**
- **Not Suitable for Route Distance**

The objective is to keep the recommendation transparent and easy to explain.

---

## Planned Data Sources

### BTS T-100 Domestic Segment

Primary source for:

- Airline
- Origin airport
- Destination airport
- Aircraft type
- Passengers
- Available seats
- Scheduled departures
- Performed departures
- Route distance
- Month
- Year

### United Airlines Public Fleet Information

Used for:

- Aircraft type
- Standard seating configuration
- Fleet size
- Mainline fleet identification

### Aircraft Manufacturer Information

Used later for aircraft range information.

### OurAirports

Used for:

- Airport code
- Airport name
- City
- Latitude
- Longitude

---

## Planned Data Model

### DIM_AIRCRAFT
One row per aircraft type.

### DIM_AIRPORT
One row per airport.

### DIM_ROUTE
One row per origin-destination route.

### DIM_DATE
Calendar and monthly reporting information.

### FACT_ROUTE_PERFORMANCE
Monthly route activity including passengers, seats, flights and aircraft.

### AIRCRAFT_ROUTE_COMPARISON
Analytical output comparing each route against suitable aircraft within the fleet.

---

## Power BI Dashboard

The first version will contain two pages.

### Page 1 — Airline Overview

Purpose:

Identify routes where aircraft capacity appears:

- Well matched
- Capacity tight
- Potentially oversized
- Worth further review

Planned visuals:

- Routes analysed
- Good-fit routes
- Routes requiring review
- Capacity-tight routes
- Route map
- Monthly demand vs capacity
- Top routes requiring review
- Suitability by aircraft type

---

### Page 2 — Route Aircraft Comparison

Purpose:

Allow the user to select an individual route and compare the current aircraft against alternative aircraft.

Planned information:

- Origin and destination
- Route distance
- Current aircraft
- Average passengers per flight
- Current seats
- Current load factor
- Monthly demand trend
- Candidate aircraft
- Candidate seating capacity
- Expected load factor
- Capacity gap
- Route suitability
- Ranked aircraft alternatives

---

## Limitations

Real airline aircraft allocation depends on significantly more information than is publicly available.

This project does not currently model:

- Aircraft rotations
- Crew availability
- Maintenance requirements
- Aircraft availability by airport
- Gate restrictions
- Detailed runway performance
- Premium cabin demand
- Connecting passenger strategy
- Cargo requirements
- Route profitability
- Fuel costs
- Internal airline scheduling strategy

Results should therefore be interpreted as **aircraft suitability indicators for further investigation**, not operational scheduling instructions.

---

## SQL Skills Demonstrated

This project will apply:

- SELECT
- WHERE
- GROUP BY
- Aggregate functions
- CASE statements
- JOINs
- Common Table Expressions
- Subqueries
- CROSS JOIN
- Window functions
- ROW_NUMBER / RANK
- Data cleaning
- KPI calculations

---

## Project Progress

### Phase 1 - Project Setup
- Created the `AirlineRouteAnalysis` SQL Server database.
- Created Bronze, Silver and Gold schemas following a Medallion architecture.
- Structured the repository so SQL scripts are separated by warehouse layer.

### Phase 2 - Bronze Layer
The Bronze layer has been created to preserve source data as close to its original form as possible.

Five raw source tables have been created:

- `bronze.t100_segment_raw`
- `bronze.aircraft_types_raw`
- `bronze.united_fleet_raw`
- `bronze.airports_raw`
- `bronze.aircraft_range_raw`

The Bronze ingestion process uses SQL Server `BULK INSERT` to load the CSV source files.

The load process includes:

- `TRUNCATE TABLE` before each reload
- CSV parsing
- Header-row handling
- UTF-8 character encoding
- Table-level locking during bulk loads
- Specific LF row-terminator handling for the airport dataset
- Stored procedure error handling using `TRY...CATCH`
- Load-duration tracking

Initial validation checks confirm that data has loaded into each Bronze table before transformation begins.

### Current Status

```text
Source CSV Files
        │
        ▼
   Bronze Layer        ✅ Complete
        │
        ▼
   Silver Layer        ⏳ Next
        │
        ▼
    Gold Layer
        │
        ▼
     Power BI




