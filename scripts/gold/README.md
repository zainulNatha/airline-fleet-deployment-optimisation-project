# Gold Layer

## 1. Purpose

The Gold layer converts the cleaned and standardised Silver data into business-ready analytical outputs.

The Bronze layer answers:

> What data did the source provide?

The Silver layer answers:

> How should the data be cleaned, standardised and structured?

The Gold layer answers:

> What does the data mean for the business question?

The main business question for this project is:

> For each U.S. domestic route, which aircraft in United Airlines' existing fleet appears best suited based on passenger demand, aircraft capacity and route distance?

The Gold layer therefore focuses on:

- monthly route demand
- passengers per flight
- seats per flight
- load factor
- candidate aircraft capacity
- capacity gap
- expected candidate load factor
- aircraft range feasibility
- aircraft suitability classification

Gold does not modify the raw source data.

It builds analytical views on top of the cleaned Silver layer.

---

# 2. Gold Architecture

The Gold layer currently follows this flow:

```text
silver.route_aircraft_monthly
        ↓
gold.route_monthly_summary
        ↓
gold.route_aircraft_candidates
        ↓
gold.route_aircraft_suitability
        ↓
final candidate ranking
        ↓
Power BI
