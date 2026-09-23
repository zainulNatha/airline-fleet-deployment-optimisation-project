USE AirlineRouteAnalysis;
GO


/* ============================================================
   GOLD LAYER - ANALYTICAL MODEL

   Purpose:

   Transform the cleaned Silver layer into business-ready
   analytical views for aircraft-route suitability and
   aircraft economics comparison.

   Primary suitability question:

   For each United Airlines U.S. domestic route, which aircraft
   in the existing fleet appears best suited based on:

       - passenger demand
       - aircraft capacity
       - route distance

   Economics extension:

   Among viable aircraft candidates, what fuel and operating
   cost differences exist?

   Gold contains five views:

       1. gold.route_monthly_summary
       2. gold.route_aircraft_candidates
       3. gold.route_aircraft_suitability
       4. gold.route_aircraft_ranked
       5. gold.route_aircraft_best_fit

   IMPORTANT:

   Economics currently provide additional comparison context.

   They do NOT determine the candidate ranking.

   Candidate ranking remains based on:

       - range feasibility
       - capacity suitability
       - capacity fit

   These outputs provide decision-support analysis.

   They do NOT represent a complete airline scheduling,
   optimisation or profitability model.

   Factors outside the current model include:

       - aircraft rotations
       - exact aircraft availability
       - crew availability
       - maintenance scheduling
       - airport restrictions
       - weather
       - network scheduling
       - route-specific fuel prices
       - route revenue
       - exact route profitability
   ============================================================ */


/* ============================================================
   1. GOLD: MONTHLY ROUTE SUMMARY

   Purpose:

   Summarise monthly passenger demand across all aircraft types
   used on each United U.S. domestic route.

   Silver grain:

       year
       + month
       + origin
       + destination
       + aircraft type

   Gold grain:

       year
       + month
       + origin
       + destination

   Aircraft type is removed because this view measures total
   route demand rather than one historically operated aircraft.

   Additional economics-support fields:

       quarter
       total_air_time_minutes
       average_air_time_minutes_per_flight

   Quarter allows monthly route records to later join to the
   quarterly P-5.2 aircraft economics dataset.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_monthly_summary
AS

SELECT

    /* ========================================================
       TIME
       ======================================================== */

    r.year,

    r.month,

    r.month_start_date,


    /* --------------------------------------------------------
       Calendar quarter derived from the route month.

       Jan-Mar  -> Q1
       Apr-Jun  -> Q2
       Jul-Sep  -> Q3
       Oct-Dec  -> Q4
       -------------------------------------------------------- */

    DATEPART(
        QUARTER,
        r.month_start_date
    ) AS quarter,


    /* ========================================================
       ROUTE
       ======================================================== */

    r.origin,

    r.destination,


    /* ========================================================
       MONTHLY TOTALS
       ======================================================== */

    SUM(r.passengers)
        AS total_passengers,


    SUM(r.seats)
        AS total_seats,


    SUM(r.departures_scheduled)
        AS departures_scheduled,


    SUM(r.departures_performed)
        AS departures_performed,


    /* --------------------------------------------------------
       ROUTE DISTANCE

       Distance is not additive.

       Several aircraft may operate one route during a month,
       but the route distance must not be summed.
       -------------------------------------------------------- */

    MAX(r.distance_miles)
        AS route_distance_miles,


    /* ========================================================
       AIR TIME

       Total airborne minutes across the route-month.

       This becomes useful because aircraft economics are
       reported on an airborne-hour basis.
       ======================================================== */

    SUM(r.air_time_minutes)
        AS total_air_time_minutes,


    /* --------------------------------------------------------
       Average airborne time per performed flight.

       Formula:

           total airborne minutes
           ----------------------
           performed departures

       NULLIF prevents division by zero.
       -------------------------------------------------------- */

    CAST(
        SUM(r.air_time_minutes)
        AS DECIMAL(18,2)
    )
    /
    NULLIF(
        SUM(r.departures_performed),
        0
    )
        AS average_air_time_minutes_per_flight,


    /* ========================================================
       PASSENGERS PER FLIGHT
       ======================================================== */

    CAST(
        SUM(r.passengers)
        AS DECIMAL(18,2)
    )
    /
    NULLIF(
        SUM(r.departures_performed),
        0
    )
        AS passengers_per_flight,


    /* ========================================================
       SEATS PER FLIGHT
       ======================================================== */

    CAST(
        SUM(r.seats)
        AS DECIMAL(18,2)
    )
    /
    NULLIF(
        SUM(r.departures_performed),
        0
    )
        AS seats_per_flight,


    /* ========================================================
       OBSERVED LOAD FACTOR

       Formula:

           passengers
           ----------
             seats

       multiplied by 100.
       ======================================================== */

    CAST(
        SUM(r.passengers)
        AS DECIMAL(18,2)
    )
    /
    NULLIF(
        SUM(r.seats),
        0
    )
    * 100
        AS load_factor_pct


FROM silver.route_aircraft_monthly AS r


/* ============================================================
   AIRPORT JOINS

   Airport reference is joined twice because each route has:

       one origin
       one destination
   ============================================================ */

INNER JOIN silver.airports AS origin_airport

    ON r.origin =
       origin_airport.analysis_airport_code


INNER JOIN silver.airports AS destination_airport

    ON r.destination =
       destination_airport.analysis_airport_code


/* ============================================================
   PROJECT SCOPE

   Keep only U.S. domestic routes.

   Both endpoints must be located in the United States.
   ============================================================ */

WHERE origin_airport.iso_country = 'US'

  AND destination_airport.iso_country = 'US'


GROUP BY

    r.year,

    r.month,

    r.month_start_date,

    r.origin,

    r.destination;
GO



/* ============================================================
   2. GOLD: ROUTE-AIRCRAFT CANDIDATE COMPARISON

   Purpose:

   Compare every monthly domestic route against every aircraft
   type in United's existing mainline fleet.

   Grain:

       year
       + month
       + origin
       + destination
       + candidate aircraft

   A CROSS JOIN evaluates every fleet aircraft against every
   route-month.

   The view combines:

       - route demand
       - aircraft capacity
       - aircraft range
       - quarterly aircraft economics

   Economics are matched using:

       route year
       + route quarter
       + aircraft type

   Economics provide comparison context only.

   They do NOT currently determine suitability category or
   candidate rank.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_aircraft_candidates
AS

SELECT

    /* ========================================================
       ROUTE INFORMATION
       ======================================================== */

    r.year,

    r.month,

    r.quarter,

    r.month_start_date,

    r.origin,

    r.destination,

    r.route_distance_miles,

    r.total_passengers,

    r.departures_performed,

    r.passengers_per_flight,

    r.seats_per_flight,

    r.load_factor_pct,


    /* ========================================================
       ROUTE AIR TIME
       ======================================================== */

    r.total_air_time_minutes,

    r.average_air_time_minutes_per_flight,


    /* Convert average airborne minutes into hours because
       P-5.2 economics are normalised per airborne hour.
    */

    r.average_air_time_minutes_per_flight
    /
    60.0
        AS average_air_time_hours_per_flight,


    /* ========================================================
       CANDIDATE AIRCRAFT INFORMATION
       ======================================================== */

    f.aircraft_type
        AS candidate_aircraft,

    f.total_aircraft,

    f.seats_min,

    f.seats_max,


    /* ========================================================
       CAPACITY GAP

       Formula:

           candidate seats
           -
           passengers per flight

       Positive:
           spare capacity

       Negative:
           observed average demand exceeds capacity

       Both minimum and maximum seat configurations are kept.
       ======================================================== */

    CAST(
        f.seats_min
        AS DECIMAL(18,2)
    )
    -
    r.passengers_per_flight
        AS capacity_gap_min,


    CAST(
        f.seats_max
        AS DECIMAL(18,2)
    )
    -
    r.passengers_per_flight
        AS capacity_gap_max,


    /* ========================================================
       EXPECTED CANDIDATE LOAD FACTOR

       Question:

       If observed passenger demand remained unchanged,
       what proportion of this candidate aircraft's seats
       would be occupied?

       Both minimum and maximum seat configurations are kept.
       ======================================================== */

    CAST(
        r.passengers_per_flight
        AS DECIMAL(18,4)
    )
    /
    NULLIF(
        f.seats_min,
        0
    )
    * 100
        AS expected_load_factor_min_seats,


    CAST(
        r.passengers_per_flight
        AS DECIMAL(18,4)
    )
    /
    NULLIF(
        f.seats_max,
        0
    )
    * 100
        AS expected_load_factor_max_seats,


    /* ========================================================
       AIRCRAFT RANGE

       Manufacturer/reference range is stored in nautical miles.

       T-100 route distance is represented in statute miles.

       Conversion:

           1 nautical mile
           ≈ 1.15078 statute miles
       ======================================================== */

    ar.range_nmi,


    CAST(
        ar.range_nmi * 1.15078
        AS DECIMAL(10,2)
    )
        AS range_miles,


    /* ========================================================
       RANGE FEASIBILITY

       High-level reference check only.

       Does not model:

           payload restrictions
           weather
           fuel reserves
           runway performance
           exact aircraft configuration
       ======================================================== */

    CASE

        WHEN ar.range_nmi IS NULL
            THEN 'Unknown'

        WHEN ar.range_nmi * 1.15078
             >= r.route_distance_miles
            THEN 'Yes'

        ELSE 'No'

    END
        AS range_feasible,


    /* ========================================================
       ECONOMICS AIRCRAFT ID

       Useful for lineage and troubleshooting the economics
       mapping.

       777-200 / 777-200ER remain NULL because BTS code 627
       cannot be reliably assigned to one exact United subtype.
       ======================================================== */

    cost.aircraft_type_id
        AS economics_aircraft_type_id,


    /* ========================================================
       QUARTERLY AIRCRAFT ECONOMICS

       Source:
           silver.aircraft_operating_cost

       The route month determines the quarter used.

       Example:

           July 2025
           -> Q3 economics
       ======================================================== */

    cost.fuel_gallons_per_air_hour,

    cost.fuel_cost_per_air_hour,

    cost.operating_cost_per_air_hour,

    cost.maintenance_cost_per_air_hour,


    /* ========================================================
       ESTIMATED FUEL USE PER FLIGHT

       Formula:

           average route airborne hours
           ×
           candidate fuel gallons per airborne hour

       Comparison proxy only.

       Actual aircraft fuel burn depends on many additional
       operational factors.
       ======================================================== */

    (
        r.average_air_time_minutes_per_flight
        /
        60.0
    )
    *
    cost.fuel_gallons_per_air_hour

        AS estimated_fuel_gallons_per_flight,


    /* ========================================================
       ESTIMATED FUEL COST PER FLIGHT

       Formula:

           average route airborne hours
           ×
           candidate fuel cost per airborne hour
       ======================================================== */

    (
        r.average_air_time_minutes_per_flight
        /
        60.0
    )
    *
    cost.fuel_cost_per_air_hour

        AS estimated_fuel_cost_per_flight,


    /* ========================================================
       ESTIMATED OPERATING COST PER FLIGHT

       Formula:

           average route airborne hours
           ×
           candidate operating cost per airborne hour

       IMPORTANT:

       This is an analytical comparison proxy.

       It is NOT exact route-level accounting cost.
       ======================================================== */

    (
        r.average_air_time_minutes_per_flight
        /
        60.0
    )
    *
    cost.operating_cost_per_air_hour

        AS estimated_operating_cost_per_flight,


    /* ========================================================
       ESTIMATED MAINTENANCE COST PER FLIGHT
       ======================================================== */

    (
        r.average_air_time_minutes_per_flight
        /
        60.0
    )
    *
    cost.maintenance_cost_per_air_hour

        AS estimated_maintenance_cost_per_flight


FROM gold.route_monthly_summary AS r


/* ============================================================
   CROSS JOIN

   Pair every route-month with every aircraft type in the
   United fleet.
   ============================================================ */

CROSS JOIN silver.united_fleet AS f


/* ============================================================
   AIRCRAFT RANGE
   ============================================================ */

LEFT JOIN silver.aircraft_range AS ar

    ON f.aircraft_type = ar.aircraft_type


/* ============================================================
   AIRCRAFT MAPPING

   Fleet uses United aircraft names.

   P-5.2 uses BTS aircraft codes.

   The controlled Silver mapping bridges the systems.

   Only exact United mappings automatically receive economics.

   BTS code 627 remains deliberately ambiguous.
   ============================================================ */

LEFT JOIN silver.aircraft_mapping AS map

    ON f.aircraft_type = map.united_aircraft_type


/* ============================================================
   QUARTERLY AIRCRAFT ECONOMICS

   Match:

       year
       + quarter
       + aircraft type
   ============================================================ */

LEFT JOIN silver.aircraft_operating_cost AS cost

    ON r.year = cost.year

   AND r.quarter = cost.quarter

   AND map.aircraft_type_id = cost.aircraft_type_id;
GO



/* ============================================================
   3. GOLD: ROUTE-AIRCRAFT SUITABILITY

   Purpose:

   Convert candidate capacity and range metrics into clear
   analytical suitability categories.

   Grain:

       year
       + month
       + origin
       + destination
       + candidate aircraft

   Categories:

       Not Suitable for Route Distance
       Too Small
       Capacity Tight
       Good Fit
       Potentially Oversized

   IMPORTANT:

   These thresholds are project analytical assumptions.

   They are NOT official United Airlines planning rules.

   Economics are carried through this view but currently do
   NOT alter the suitability category.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_aircraft_suitability
AS

SELECT

    c.*,


    CASE

        /* ----------------------------------------------------
           1. RANGE FAILURE

           Range takes priority over capacity.
           ---------------------------------------------------- */

        WHEN c.range_feasible = 'No'
            THEN 'Not Suitable for Route Distance'


        /* ----------------------------------------------------
           2. TOO SMALL

           Even the maximum reported seat configuration would
           require an expected load factor above 100%.
           ---------------------------------------------------- */

        WHEN c.expected_load_factor_max_seats > 100
            THEN 'Too Small'


        /* ----------------------------------------------------
           3. CAPACITY TIGHT

           Candidate can accommodate average demand but would
           operate above 95% expected load factor.
           ---------------------------------------------------- */

        WHEN c.expected_load_factor_max_seats > 95
            THEN 'Capacity Tight'


        /* ----------------------------------------------------
           4. GOOD FIT

           Project assumption:

               75% to 95%
           ---------------------------------------------------- */

        WHEN c.expected_load_factor_max_seats >= 75
            THEN 'Good Fit'


        /* ----------------------------------------------------
           5. POTENTIALLY OVERSIZED

           Expected load factor below 75%.
           ---------------------------------------------------- */

        ELSE 'Potentially Oversized'

    END AS suitability_category


FROM gold.route_aircraft_candidates AS c;
GO



/* ============================================================
   4. GOLD: RANKED ROUTE-AIRCRAFT CANDIDATES

   Purpose:

   Rank viable candidates for each route-month using
   transparent suitability and capacity-fit rules.

   Excluded:

       Too Small
       Not Suitable for Route Distance

   Ranking priority:

       1. Good Fit
       2. Capacity Tight
       3. Potentially Oversized

   Within each category:

       smaller capacity gap
       =
       closer capacity match

   DENSE_RANK is used because genuinely equivalent aircraft
   are allowed to share a rank.

   IMPORTANT:

   Economics are available for comparison but do NOT currently
   affect candidate_rank.

   This avoids making an unsupported assumption that the
   lowest reported operating-cost proxy must automatically
   be the best aircraft deployment choice.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_aircraft_ranked
AS


WITH viable_candidates AS
(
    SELECT

        s.*,


        /* Sorting priority only.
           This is NOT an optimisation score.
        */

        CASE

            WHEN s.suitability_category = 'Good Fit'
                THEN 1

            WHEN s.suitability_category = 'Capacity Tight'
                THEN 2

            WHEN s.suitability_category = 'Potentially Oversized'
                THEN 3

        END AS suitability_priority


    FROM gold.route_aircraft_suitability AS s


    WHERE s.range_feasible = 'Yes'

      AND s.suitability_category IN
      (
          'Good Fit',
          'Capacity Tight',
          'Potentially Oversized'
      )
),


ranked_candidates AS
(
    SELECT

        v.*,


        DENSE_RANK() OVER
        (
            PARTITION BY

                v.year,
                v.month,
                v.origin,
                v.destination


            ORDER BY

                v.suitability_priority ASC,

                v.capacity_gap_max ASC

        ) AS candidate_rank


    FROM viable_candidates AS v
)


SELECT *

FROM ranked_candidates;
GO



/* ============================================================
   5. GOLD: BEST-FIT ROUTE AIRCRAFT

   Purpose:

   Return the highest-ranked candidate or candidates for each
   route-month.

   DENSE_RANK deliberately allows ties.

   Therefore one route-month may contain multiple rank-1
   aircraft when the available suitability criteria cannot
   meaningfully distinguish between them.

   Example:

       737-700
       A319-100

   may both receive rank 1 when they have:

       identical capacity
       identical suitability category
       identical capacity gap

   Grain:

       year
       + month
       + origin
       + destination
       + joint best-fit aircraft

   Economics are included so Power BI can show the economic
   profile of the best-fit candidate(s).

   Candidate ranking itself remains capacity/range based.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_aircraft_best_fit
AS

SELECT

    /* ========================================================
       TIME / ROUTE
       ======================================================== */

    year,

    month,

    quarter,

    month_start_date,

    origin,

    destination,

    route_distance_miles,


    /* ========================================================
       OBSERVED ROUTE DEMAND
       ======================================================== */

    total_passengers,

    departures_performed,

    passengers_per_flight,

    seats_per_flight,

    load_factor_pct,


    /* ========================================================
       ROUTE AIR TIME
       ======================================================== */

    total_air_time_minutes,

    average_air_time_minutes_per_flight,

    average_air_time_hours_per_flight,


    /* ========================================================
       SUGGESTED / JOINT BEST-FIT AIRCRAFT
       ======================================================== */

    candidate_aircraft
        AS suggested_aircraft,


    seats_min
        AS suggested_seats_min,


    seats_max
        AS suggested_seats_max,


    /* ========================================================
       CAPACITY COMPARISON
       ======================================================== */

    capacity_gap_min,

    capacity_gap_max,

    expected_load_factor_min_seats,

    expected_load_factor_max_seats,


    /* ========================================================
       RANGE
       ======================================================== */

    range_miles,

    range_feasible,


    /* ========================================================
       QUARTERLY AIRCRAFT ECONOMICS
       ======================================================== */

    fuel_gallons_per_air_hour,

    fuel_cost_per_air_hour,

    operating_cost_per_air_hour,

    maintenance_cost_per_air_hour,


    /* ========================================================
       ESTIMATED ROUTE ECONOMICS PROXIES
       ======================================================== */

    estimated_fuel_gallons_per_flight,

    estimated_fuel_cost_per_flight,

    estimated_operating_cost_per_flight,

    estimated_maintenance_cost_per_flight,


    /* ========================================================
       SUITABILITY / RANK
       ======================================================== */

    suitability_category,

    candidate_rank


FROM gold.route_aircraft_ranked


WHERE candidate_rank = 1;
GO
