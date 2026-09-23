USE AirlineRouteAnalysis;
GO

/* ============================================================
   GOLD LAYER - ANALYTICAL MODEL

   Purpose:
   Transform the cleaned Silver layer into business-ready
   analytical views for aircraft-route suitability analysis.

   Main business question:

   For each United Airlines U.S. domestic route, which aircraft
   in the existing fleet appears best suited based on:

       - passenger demand
       - aircraft capacity
       - route distance

   Gold currently contains five views:

       1. gold.route_monthly_summary
       2. gold.route_aircraft_candidates
       3. gold.route_aircraft_suitability
       4. gold.route_aircraft_ranked
       5. gold.route_aircraft_best_fit

   Important:
   These outputs provide decision-support analysis.

   They do NOT represent a complete airline scheduling model.

   Operational factors such as:
       - aircraft rotations
       - crew availability
       - maintenance requirements
       - airport restrictions
       - operating cost
       - aircraft availability

   are outside the current Version 1 model.
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

   Aircraft type is removed from the grouping because this view
   measures overall route demand rather than demand associated
   with one historically operated aircraft type.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_monthly_summary
AS

SELECT

    r.year,
    r.month,
    r.month_start_date,

    r.origin,
    r.destination,


    /* --------------------------------------------------------
       TOTAL MONTHLY PASSENGERS

       Passenger counts are additive across aircraft types
       operating the same route during the same month.
       -------------------------------------------------------- */

    SUM(r.passengers) AS total_passengers,


    /* --------------------------------------------------------
       TOTAL MONTHLY SEATS

       Total seat capacity supplied across all performed
       operations during the month.
       -------------------------------------------------------- */

    SUM(r.seats) AS total_seats,


    /* --------------------------------------------------------
       DEPARTURES
       -------------------------------------------------------- */

    SUM(r.departures_scheduled) AS departures_scheduled,

    SUM(r.departures_performed) AS departures_performed,


    /* --------------------------------------------------------
       ROUTE DISTANCE

       Distance is not additive.

       Multiple aircraft may operate the same route, but this
       should not cause the route distance to be summed.
       -------------------------------------------------------- */

    MAX(r.distance_miles) AS route_distance_miles,


    /* --------------------------------------------------------
       PASSENGERS PER FLIGHT

       Represents average observed passenger demand per
       performed flight.

       Formula:

           total passengers
           -----------------
           performed flights

       NULLIF prevents division by zero.
       -------------------------------------------------------- */

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


    /* --------------------------------------------------------
       SEATS PER FLIGHT

       Represents the average seat capacity historically
       supplied per performed flight.
       -------------------------------------------------------- */

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


    /* --------------------------------------------------------
       LOAD FACTOR

       Percentage of historically supplied seats occupied.

       Formula:

           passengers
           ----------
             seats

       multiplied by 100 to return a percentage.
       -------------------------------------------------------- */

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


/* ------------------------------------------------------------
   Join airport reference twice because every route has:

       one origin airport
       one destination airport
   ------------------------------------------------------------ */

INNER JOIN silver.airports AS origin_airport
    ON r.origin = origin_airport.analysis_airport_code

INNER JOIN silver.airports AS destination_airport
    ON r.destination = destination_airport.analysis_airport_code


/* ------------------------------------------------------------
   PROJECT SCOPE

   Keep only U.S. domestic routes where BOTH endpoints
   are located in the United States.
   ------------------------------------------------------------ */

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

   A CROSS JOIN is used because every aircraft type should be
   evaluated against every route-month.

   This view does NOT yet determine whether the aircraft is a
   good or poor fit.

   It creates the metrics required for that assessment.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_aircraft_candidates
AS

SELECT

    /* ========================================================
       ROUTE INFORMATION
       ======================================================== */

    r.year,
    r.month,
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
       CANDIDATE AIRCRAFT INFORMATION
       ======================================================== */

    f.aircraft_type AS candidate_aircraft,

    f.total_aircraft,

    f.seats_min,
    f.seats_max,


    /* ========================================================
       CAPACITY GAP

       Formula:

           candidate seats
           -
           passengers per flight

       Positive result:
           aircraft has spare capacity.

       Negative result:
           average passenger demand exceeds aircraft capacity.

       Both minimum and maximum configurations are retained
       where United reports a seat range.
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

       If passenger demand remained equal to the observed
       passengers-per-flight value, what percentage of this
       candidate aircraft's seats would be occupied?

       Both minimum and maximum seat configurations are kept.

       Example:

           passengers per flight = 150
           aircraft seats        = 166

           expected load factor
           = 150 / 166 * 100
           ≈ 90.4%
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

       Manufacturer aircraft range reference is stored in
       nautical miles.

       T-100 route distance is represented in statute miles.

       Conversion used:

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

       This is a high-level reference-range check.

       It does not model operational factors such as:

           - payload restrictions
           - weather
           - fuel reserves
           - runway performance
           - aircraft configuration
       ======================================================== */

    CASE

        WHEN ar.range_nmi IS NULL
            THEN 'Unknown'

        WHEN ar.range_nmi * 1.15078
             >= r.route_distance_miles
            THEN 'Yes'

        ELSE 'No'

    END AS range_feasible


FROM gold.route_monthly_summary AS r


/* ------------------------------------------------------------
   CROSS JOIN

   Pair every route-month with every aircraft type in the
   United fleet.

   Example:

       EWR-SFO + 737-800
       EWR-SFO + A321neo
       EWR-SFO + 787-8
       etc.
   ------------------------------------------------------------ */

CROSS JOIN silver.united_fleet AS f


/* ------------------------------------------------------------
   Attach aircraft reference range.
   ------------------------------------------------------------ */

LEFT JOIN silver.aircraft_range AS ar
    ON f.aircraft_type = ar.aircraft_type;
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

   Suitability categories:

       Not Suitable for Route Distance
       Too Small
       Capacity Tight
       Good Fit
       Potentially Oversized

   Important:
   These thresholds are analytical assumptions created for
   this portfolio project.

   They are NOT claimed to be official United Airlines
   fleet-planning rules.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_aircraft_suitability
AS

SELECT

    c.*,


    CASE

        /* ----------------------------------------------------
           1. RANGE FAILURE

           Range is checked before capacity.

           If the aircraft reference range is below the route
           distance, capacity suitability is irrelevant.
           ---------------------------------------------------- */

        WHEN c.range_feasible = 'No'
            THEN 'Not Suitable for Route Distance'


        /* ----------------------------------------------------
           2. TOO SMALL

           The maximum reported seat configuration is used for
           the headline classification.

           Expected load factor above 100% means average
           observed demand exceeds the candidate's capacity.
           ---------------------------------------------------- */

        WHEN c.expected_load_factor_max_seats > 100
            THEN 'Too Small'


        /* ----------------------------------------------------
           3. CAPACITY TIGHT

           Aircraft can accommodate average demand but the
           expected load factor is above 95%.

           This leaves little spare capacity.
           ---------------------------------------------------- */

        WHEN c.expected_load_factor_max_seats > 95
            THEN 'Capacity Tight'


        /* ----------------------------------------------------
           4. GOOD FIT

           Expected candidate load factor between:

               75% and 95%

           represents the project's broad reasonable
           capacity-utilisation range.
           ---------------------------------------------------- */

        WHEN c.expected_load_factor_max_seats >= 75
            THEN 'Good Fit'


        /* ----------------------------------------------------
           5. POTENTIALLY OVERSIZED

           Expected candidate load factor below 75% suggests
           that considerably more capacity is being supplied
           than average passenger demand requires.
           ---------------------------------------------------- */

        ELSE 'Potentially Oversized'

    END AS suitability_category


FROM gold.route_aircraft_candidates AS c;
GO



/* ============================================================
   4. GOLD: RANKED ROUTE-AIRCRAFT CANDIDATES

   Purpose:
   Rank viable aircraft candidates for each route-month using
   transparent capacity-fit rules.

   Aircraft excluded from ranking:

       Too Small
       Not Suitable for Route Distance

   Ranking priority:

       1. Good Fit
       2. Capacity Tight
       3. Potentially Oversized

   Within each suitability category:

       smaller positive capacity gap
       =
       closer capacity match

   DENSE_RANK is used because multiple aircraft may be
   genuinely equivalent according to the available criteria.

   No arbitrary 0-100 optimisation score is used.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_aircraft_ranked
AS


/* ============================================================
   STEP 1:
   Keep only viable candidates and assign a simple category
   priority used for ordering.
   ============================================================ */

WITH viable_candidates AS
(
    SELECT

        s.*,


        /* ----------------------------------------------------
           These values are sorting priorities only.

           They are NOT optimisation scores.
           ---------------------------------------------------- */

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


/* ============================================================
   STEP 2:
   Rank aircraft separately inside every route-month.
   ============================================================ */

ranked_candidates AS
(
    SELECT

        v.*,


        DENSE_RANK() OVER
        (
            /* ------------------------------------------------
               Restart the ranking for each route-month.
               ------------------------------------------------ */

            PARTITION BY

                v.year,
                v.month,
                v.origin,
                v.destination


            /* ------------------------------------------------
               First prefer the suitability category.

               Then prefer the candidate with the smallest
               capacity gap inside that category.
               ------------------------------------------------ */

            ORDER BY

                v.suitability_priority ASC,
                v.capacity_gap_max ASC

        ) AS candidate_rank


    FROM viable_candidates AS v
)


/* ============================================================
   STEP 3:
   Return the completed ranked candidate dataset.
   ============================================================ */

SELECT *
FROM ranked_candidates;
GO



/* ============================================================
   5. GOLD: BEST-FIT ROUTE AIRCRAFT

   Purpose:
   Return the highest-ranked aircraft candidate or candidates
   for every route-month.

   Important:
   DENSE_RANK allows genuine ties.

   Therefore this view may contain MORE THAN ONE rank-1
   aircraft for a route-month.

   Example:

       737-700
       A319-100

   may both receive rank 1 when they have identical capacity
   fit and both satisfy the same range/suitability conditions.

   Grain:
       year
       + month
       + origin
       + destination
       + joint best-fit aircraft

   This view is intended as a simplified reporting-ready
   dataset for the Power BI overview.

   It remains decision-support analysis rather than a complete
   operational aircraft scheduling recommendation.
   ============================================================ */

CREATE OR ALTER VIEW gold.route_aircraft_best_fit
AS

SELECT

    /* ========================================================
       ROUTE INFORMATION
       ======================================================== */

    year,
    month,
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
       RANGE AND SUITABILITY
       ======================================================== */

    range_miles,
    range_feasible,

    suitability_category,

    candidate_rank


FROM gold.route_aircraft_ranked


/* ------------------------------------------------------------
   Keep only the highest-ranked aircraft.

   More than one row may remain when candidates are tied.
   ------------------------------------------------------------ */

WHERE candidate_rank = 1;
GO
