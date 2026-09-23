USE AirlineRouteAnalysis;
GO

/* ============================================================
   GOLD LAYER QUALITY CHECKS

   Purpose:
   Validate that the Gold analytical views preserve the
   intended grain and apply the business rules correctly.

   Important:
   Some queries are expected to return rows for investigation.
   Comments explain the expected behaviour.
   ============================================================ */


/* ============================================================
   1. ROUTE MONTHLY SUMMARY - ROW COUNT
   ============================================================ */

SELECT
    COUNT(*) AS route_monthly_rows
FROM gold.route_monthly_summary;
GO


/* ============================================================
   2. ROUTE MONTHLY SUMMARY - GRAIN CHECK

   Grain:
   year + month + origin + destination

   Each route-month should appear once.

   Expected:
   0 rows.
   ============================================================ */

SELECT
    year,
    month,
    origin,
    destination,
    COUNT(*) AS record_count
FROM gold.route_monthly_summary
GROUP BY
    year,
    month,
    origin,
    destination
HAVING COUNT(*) > 1;
GO


/* ============================================================
   3. ROUTE MONTHLY SUMMARY - KEY NULL CHECK

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_monthly_summary
WHERE year IS NULL
   OR month IS NULL
   OR month_start_date IS NULL
   OR origin IS NULL
   OR destination IS NULL;
GO


/* ============================================================
   4. ROUTE MONTHLY SUMMARY - DOMESTIC ROUTE CHECK

   Gold should contain only routes where both airports
   are located in the United States.

   Expected:
   0 rows.
   ============================================================ */

SELECT
    r.origin,
    origin_airport.iso_country AS origin_country,
    r.destination,
    destination_airport.iso_country AS destination_country
FROM gold.route_monthly_summary AS r

LEFT JOIN silver.airports AS origin_airport
    ON r.origin = origin_airport.analysis_airport_code

LEFT JOIN silver.airports AS destination_airport
    ON r.destination = destination_airport.analysis_airport_code

WHERE origin_airport.iso_country <> 'US'
   OR destination_airport.iso_country <> 'US'
   OR origin_airport.iso_country IS NULL
   OR destination_airport.iso_country IS NULL;
GO


/* ============================================================
   5. ROUTE MONTHLY SUMMARY - METRIC SANITY CHECK

   These values should not normally be negative.

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_monthly_summary
WHERE total_passengers < 0
   OR total_seats < 0
   OR departures_performed < 0
   OR passengers_per_flight < 0
   OR seats_per_flight < 0
   OR load_factor_pct < 0;
GO


/* ============================================================
   6. CANDIDATE VIEW - EXPECTED ROW EXPANSION

   CROSS JOIN should create:

       number of route-month rows
       ×
       number of United fleet aircraft types

   Compare expected vs actual.
   ============================================================ */

SELECT
    (SELECT COUNT(*)
     FROM gold.route_monthly_summary)
    *
    (SELECT COUNT(*)
     FROM silver.united_fleet)
        AS expected_candidate_rows,

    (SELECT COUNT(*)
     FROM gold.route_aircraft_candidates)
        AS actual_candidate_rows;
GO


/* ============================================================
   7. CANDIDATE VIEW - GRAIN CHECK

   Grain:
   year + month + origin + destination + candidate aircraft

   Expected:
   0 rows.
   ============================================================ */

SELECT
    year,
    month,
    origin,
    destination,
    candidate_aircraft,
    COUNT(*) AS record_count
FROM gold.route_aircraft_candidates
GROUP BY
    year,
    month,
    origin,
    destination,
    candidate_aircraft
HAVING COUNT(*) > 1;
GO


/* ============================================================
   8. CANDIDATE VIEW - CAPACITY GAP CHECK

   capacity_gap_max should equal:

       seats_max - passengers_per_flight

   Expected:
   0 rows.

   Small rounding differences are tolerated.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_candidates
WHERE ABS(
        capacity_gap_max
        -
        (
            CAST(seats_max AS DECIMAL(18,2))
            - passengers_per_flight
        )
      ) > 0.01;
GO


/* ============================================================
   9. CANDIDATE VIEW - EXPECTED LOAD FACTOR CHECK

   Expected candidate load factor should equal:

       passengers_per_flight / seats_max * 100

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_candidates
WHERE seats_max > 0

  AND ABS(
        expected_load_factor_max_seats
        -
        (
            passengers_per_flight
            / seats_max
            * 100
        )
      ) > 0.01;
GO


/* ============================================================
   10. RANGE FEASIBILITY VALUES

   Review the values produced by the model.
   ============================================================ */

SELECT
    range_feasible,
    COUNT(*) AS record_count
FROM gold.route_aircraft_candidates
GROUP BY range_feasible;
GO


/* ============================================================
   11. SUITABILITY CATEGORY DISTRIBUTION

   Descriptive check.

   Shows how candidate combinations are currently classified.
   ============================================================ */

SELECT
    suitability_category,
    COUNT(*) AS candidate_count
FROM gold.route_aircraft_suitability
GROUP BY suitability_category
ORDER BY candidate_count DESC;
GO


/* ============================================================
   12. SUITABILITY - NULL CATEGORY CHECK

   Every candidate should receive a category.

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_suitability
WHERE suitability_category IS NULL;
GO


/* ============================================================
   13. TOO SMALL RULE CHECK

   Too Small should mean expected load factor > 100%,
   unless range failure has already taken priority.

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_suitability
WHERE suitability_category = 'Too Small'
  AND expected_load_factor_max_seats <= 100;
GO


/* ============================================================
   14. CAPACITY TIGHT RULE CHECK

   Expected range:
       > 95%
       <= 100%

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_suitability
WHERE suitability_category = 'Capacity Tight'
  AND (
        expected_load_factor_max_seats <= 95
        OR expected_load_factor_max_seats > 100
      );
GO


/* ============================================================
   15. GOOD FIT RULE CHECK

   Expected range:
       >= 75%
       <= 95%

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_suitability
WHERE suitability_category = 'Good Fit'
  AND (
        expected_load_factor_max_seats < 75
        OR expected_load_factor_max_seats > 95
      );
GO


/* ============================================================
   16. POTENTIALLY OVERSIZED RULE CHECK

   Expected:
       expected load factor < 75%

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_suitability
WHERE suitability_category = 'Potentially Oversized'
  AND expected_load_factor_max_seats >= 75;
GO


/* ============================================================
   17. RANGE FAILURE CLASSIFICATION CHECK

   Any candidate with range_feasible = No should be labelled
   Not Suitable for Route Distance.

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_suitability
WHERE range_feasible = 'No'
  AND suitability_category <> 'Not Suitable for Route Distance';
GO


/* ============================================================
   18. RANKED VIEW - EXCLUDED CATEGORY CHECK

   The ranked view should not contain:
       Too Small
       Not Suitable for Route Distance

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_ranked
WHERE suitability_category IN
(
    'Too Small',
    'Not Suitable for Route Distance'
);
GO


/* ============================================================
   19. RANKED VIEW - RANK 1 COVERAGE

   Every route-month represented in the ranked dataset
   should have at least one candidate ranked 1.

   Expected:
   0 rows.
   ============================================================ */

SELECT
    year,
    month,
    origin,
    destination
FROM gold.route_aircraft_ranked
GROUP BY
    year,
    month,
    origin,
    destination
HAVING MIN(candidate_rank) <> 1;
GO


/* ============================================================
   20. ROUTES WITH NO VIABLE CANDIDATE

   Important investigative check.

   Shows route-months present in the route summary but with
   no aircraft surviving into the ranked candidate view.

   Ideally:
   0 rows.

   If rows appear, investigate rather than deleting them.
   ============================================================ */

SELECT
    r.year,
    r.month,
    r.origin,
    r.destination,
    r.passengers_per_flight,
    r.route_distance_miles

FROM gold.route_monthly_summary AS r

LEFT JOIN
(
    SELECT DISTINCT
        year,
        month,
        origin,
        destination
    FROM gold.route_aircraft_ranked
) AS ranked

    ON r.year = ranked.year
   AND r.month = ranked.month
   AND r.origin = ranked.origin
   AND r.destination = ranked.destination

WHERE ranked.origin IS NULL

ORDER BY
    r.year,
    r.month,
    r.origin,
    r.destination;
GO


/* ============================================================
   21. BEST-FIT VIEW - ONLY RANK 1 CHECK

   Expected:
   0 rows.
   ============================================================ */

SELECT *
FROM gold.route_aircraft_best_fit
WHERE candidate_rank <> 1;
GO


/* ============================================================
   22. BEST-FIT VIEW - TIED BEST FIT CANDIDATES

   This is NOT necessarily an error.

   DENSE_RANK deliberately allows aircraft with identical
   suitability and capacity fit to share rank 1.

   Returned rows identify route-months with joint best-fit
   candidates.
   ============================================================ */

SELECT
    year,
    month,
    origin,
    destination,
    COUNT(*) AS best_fit_candidate_count

FROM gold.route_aircraft_best_fit

GROUP BY
    year,
    month,
    origin,
    destination

HAVING COUNT(*) > 1

ORDER BY
    best_fit_candidate_count DESC,
    year,
    month,
    origin,
    destination;
GO


/* ============================================================
   23. REVIEW ONE KNOWN TIE

   January 2025
   ABE -> EWR

   Previous investigation identified:
       737-700
       A319-100

   Both have:
       126 seats
       identical capacity gap
       identical expected load factor

   Both should therefore receive rank 1.
   ============================================================ */

SELECT
    year,
    month,
    origin,
    destination,

    passengers_per_flight,

    suggested_aircraft,

    suggested_seats_min,
    suggested_seats_max,

    capacity_gap_max,
    expected_load_factor_max_seats,

    suitability_category,
    candidate_rank

FROM gold.route_aircraft_best_fit

WHERE year = 2025
  AND month = 1
  AND origin = 'ABE'
  AND destination = 'EWR';
GO


/* ============================================================
   24. REVIEW EWR -> SFO MONTHLY RESULTS

   Useful worked example for confirming that the suggested
   aircraft changes as monthly passenger demand changes.
   ============================================================ */

SELECT
    year,
    month,
    origin,
    destination,

    passengers_per_flight,
    load_factor_pct,

    suggested_aircraft,
    suggested_seats_max,

    capacity_gap_max,
    expected_load_factor_max_seats,

    suitability_category

FROM gold.route_aircraft_best_fit

WHERE origin = 'EWR'
  AND destination = 'SFO'

ORDER BY month;
GO
