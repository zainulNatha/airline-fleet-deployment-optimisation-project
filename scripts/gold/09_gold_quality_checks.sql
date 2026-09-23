USE AirlineRouteAnalysis;
GO


/* ============================================================
   GOLD LAYER QUALITY CHECKS

   Purpose:

   Validate that the Gold analytical views:

       - preserve their intended grain
       - apply suitability rules correctly
       - preserve candidate ranking logic
       - attach quarterly economics correctly
       - calculate route fuel / cost proxies correctly

   Some queries are investigative and are expected to return
   rows.

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

       year
       + month
       + origin
       + destination

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

   OR quarter IS NULL

   OR month_start_date IS NULL

   OR origin IS NULL

   OR destination IS NULL;
GO



/* ============================================================
   4. ROUTE MONTHLY SUMMARY - DOMESTIC ROUTE CHECK

   Both airports must be in the United States.

   Expected:
   0 rows.
   ============================================================ */

SELECT

    r.origin,

    origin_airport.iso_country
        AS origin_country,

    r.destination,

    destination_airport.iso_country
        AS destination_country


FROM gold.route_monthly_summary AS r


LEFT JOIN silver.airports AS origin_airport

    ON r.origin =
       origin_airport.analysis_airport_code


LEFT JOIN silver.airports AS destination_airport

    ON r.destination =
       destination_airport.analysis_airport_code


WHERE origin_airport.iso_country <> 'US'

   OR destination_airport.iso_country <> 'US'

   OR origin_airport.iso_country IS NULL

   OR destination_airport.iso_country IS NULL;
GO



/* ============================================================
   5. ROUTE MONTHLY SUMMARY - METRIC SANITY CHECK

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM gold.route_monthly_summary

WHERE total_passengers < 0

   OR total_seats < 0

   OR departures_performed < 0

   OR total_air_time_minutes < 0

   OR passengers_per_flight < 0

   OR seats_per_flight < 0

   OR average_air_time_minutes_per_flight < 0

   OR load_factor_pct < 0;
GO



/* ============================================================
   6. CANDIDATE VIEW - EXPECTED ROW EXPANSION

   CROSS JOIN should create:

       route-month rows
       ×
       United fleet aircraft types

   Expected:
   expected_candidate_rows = actual_candidate_rows

   This also helps detect accidental row duplication from
   economics joins.
   ============================================================ */

SELECT

    (
        SELECT COUNT(*)
        FROM gold.route_monthly_summary
    )

    *

    (
        SELECT COUNT(*)
        FROM silver.united_fleet
    )
        AS expected_candidate_rows,


    (
        SELECT COUNT(*)
        FROM gold.route_aircraft_candidates
    )
        AS actual_candidate_rows;
GO



/* ============================================================
   7. CANDIDATE VIEW - GRAIN CHECK

   Grain:

       year
       + month
       + origin
       + destination
       + candidate aircraft

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

       seats_max
       -
       passengers_per_flight

   Expected:
   0 rows.

   Tolerance allows small decimal rounding differences.
   ============================================================ */

SELECT *

FROM gold.route_aircraft_candidates

WHERE ABS
(
    capacity_gap_max

    -

    (
        CAST(
            seats_max
            AS DECIMAL(18,2)
        )

        -

        passengers_per_flight
    )
)
> 0.01;
GO



/* ============================================================
   9. CANDIDATE VIEW - EXPECTED LOAD FACTOR CHECK

   Formula:

       passengers_per_flight
       ---------------------
       seats_max

       × 100

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM gold.route_aircraft_candidates

WHERE seats_max > 0

  AND ABS
  (
      expected_load_factor_max_seats

      -

      (
          passengers_per_flight

          /

          seats_max

          * 100
      )
  )
  > 0.01;
GO



/* ============================================================
   10. RANGE FEASIBILITY VALUES

   Descriptive check.
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

   Too Small should have expected LF > 100%.

   Range failure is checked first in the CASE statement.

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

  AND
  (
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

  AND
  (
      expected_load_factor_max_seats < 75

      OR expected_load_factor_max_seats > 95
  );
GO



/* ============================================================
   16. POTENTIALLY OVERSIZED RULE CHECK

   Expected:

       expected LF < 75%

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

   range_feasible = No should always be classified:

       Not Suitable for Route Distance

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM gold.route_aircraft_suitability

WHERE range_feasible = 'No'

  AND suitability_category <>
      'Not Suitable for Route Distance';
GO



/* ============================================================
   18. RANKED VIEW - EXCLUDED CATEGORY CHECK

   Ranked candidates should not contain:

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

   Every route-month represented in the ranked view should
   have at least one rank-1 candidate.

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

   Investigative check.

   Shows route-months present in route_monthly_summary but
   absent from the ranked view.

   Ideally:
   0 rows.

   Returned rows should be investigated rather than removed.
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
   22. BEST-FIT VIEW - TIED BEST-FIT CANDIDATES

   DENSE_RANK deliberately allows ties.

   This is NOT automatically an error.

   Returned rows identify route-months where multiple
   candidates are analytically equivalent under the current
   suitability and capacity criteria.
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
   23. REVIEW KNOWN TIE

   January 2025
   ABE -> EWR

   Earlier investigation identified:

       737-700
       A319-100

   Both have:

       126 seats
       identical capacity gap
       identical expected load factor

   Both should therefore receive rank 1.

   Their economics may differ, but economics do not currently
   break the suitability ranking tie.
   ============================================================ */

SELECT

    year,

    month,

    quarter,

    origin,

    destination,

    passengers_per_flight,

    suggested_aircraft,

    suggested_seats_min,

    suggested_seats_max,

    capacity_gap_max,

    expected_load_factor_max_seats,

    operating_cost_per_air_hour,

    estimated_operating_cost_per_flight,

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

   Confirms that monthly demand can produce different
   best-fit aircraft throughout the year.
   ============================================================ */

SELECT

    year,

    month,

    quarter,

    origin,

    destination,

    passengers_per_flight,

    load_factor_pct,

    suggested_aircraft,

    suggested_seats_max,

    capacity_gap_max,

    expected_load_factor_max_seats,

    operating_cost_per_air_hour,

    estimated_operating_cost_per_flight,

    suitability_category


FROM gold.route_aircraft_best_fit


WHERE origin = 'EWR'

  AND destination = 'SFO'


ORDER BY month;
GO



/* ============================================================
   25. QUARTER MAPPING CHECK

   Route month should map to the correct calendar quarter.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM gold.route_monthly_summary


WHERE quarter <>
    CASE

        WHEN month BETWEEN 1 AND 3
            THEN 1

        WHEN month BETWEEN 4 AND 6
            THEN 2

        WHEN month BETWEEN 7 AND 9
            THEN 3

        WHEN month BETWEEN 10 AND 12
            THEN 4

    END;
GO



/* ============================================================
   26. AVERAGE AIR TIME CALCULATION CHECK

   Formula:

       total air time minutes
       ----------------------
       performed departures

   Expected:
   0 rows.

   Small tolerance allows decimal rounding.
   ============================================================ */

SELECT *

FROM gold.route_monthly_summary


WHERE departures_performed > 0


  AND ABS
  (
      average_air_time_minutes_per_flight

      -

      (
          total_air_time_minutes

          /

          NULLIF(
              departures_performed,
              0
          )
      )
  )
  > 0.01;
GO



/* ============================================================
   27. ECONOMICS COVERAGE

   Identify candidates without operating-cost economics.

   Expected known limitation:

       777-200
       777-200ER

   These correspond to ambiguous BTS aircraft family code 627.
   ============================================================ */

SELECT

    candidate_aircraft,

    COUNT(*) AS missing_economics_rows


FROM gold.route_aircraft_candidates


WHERE operating_cost_per_air_hour IS NULL


GROUP BY candidate_aircraft


ORDER BY candidate_aircraft;
GO



/* ============================================================
   28. UNEXPECTED ECONOMICS GAPS

   Excluding the documented 777-200 family ambiguity,
   all other candidates should have economics.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM gold.route_aircraft_candidates


WHERE operating_cost_per_air_hour IS NULL


  AND candidate_aircraft NOT IN
  (
      '777-200',

      '777-200ER'
  );
GO



/* ============================================================
   29. ESTIMATED FUEL PROXY CHECK

   Formula:

       average route airborne hours
       ×
       candidate fuel gallons per airborne hour

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM gold.route_aircraft_candidates


WHERE fuel_gallons_per_air_hour IS NOT NULL


  AND ABS
  (
      estimated_fuel_gallons_per_flight

      -

      (
          average_air_time_hours_per_flight

          *

          fuel_gallons_per_air_hour
      )
  )
  > 0.01;
GO



/* ============================================================
   30. ESTIMATED OPERATING COST PROXY CHECK

   Formula:

       average route airborne hours
       ×
       candidate operating cost per airborne hour

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM gold.route_aircraft_candidates


WHERE operating_cost_per_air_hour IS NOT NULL


  AND ABS
  (
      estimated_operating_cost_per_flight

      -

      (
          average_air_time_hours_per_flight

          *

          operating_cost_per_air_hour
      )
  )
  > 0.01;
GO



/* ============================================================
   31. NEGATIVE ECONOMICS CHECK

   Fuel and cost measures should not be negative.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM gold.route_aircraft_candidates


WHERE fuel_gallons_per_air_hour < 0

   OR fuel_cost_per_air_hour < 0

   OR operating_cost_per_air_hour < 0

   OR maintenance_cost_per_air_hour < 0

   OR estimated_fuel_gallons_per_flight < 0

   OR estimated_fuel_cost_per_flight < 0

   OR estimated_operating_cost_per_flight < 0

   OR estimated_maintenance_cost_per_flight < 0;
GO



/* ============================================================
   32. BEST-FIT ECONOMICS MISSING REVIEW

   Investigative check.

   A returned row is not automatically an error because a
   rank-1 candidate could theoretically belong to the known
   ambiguous 777-200 family.
   ============================================================ */

SELECT

    year,

    month,

    quarter,

    origin,

    destination,

    suggested_aircraft,

    suitability_category,

    operating_cost_per_air_hour,

    estimated_operating_cost_per_flight


FROM gold.route_aircraft_best_fit


WHERE operating_cost_per_air_hour IS NULL


ORDER BY

    year,

    month,

    origin,

    destination;
GO



/* ============================================================
   33. EWR -> SFO ECONOMICS WORKED EXAMPLE

   Confirms:

       - monthly best-fit aircraft
       - correct quarter
       - quarterly economics
       - estimated route cost proxy
   ============================================================ */

SELECT

    year,

    month,

    quarter,

    origin,

    destination,

    suggested_aircraft,

    passengers_per_flight,

    expected_load_factor_max_seats,

    fuel_gallons_per_air_hour,

    operating_cost_per_air_hour,

    estimated_fuel_gallons_per_flight,

    estimated_operating_cost_per_flight,

    suitability_category


FROM gold.route_aircraft_best_fit


WHERE origin = 'EWR'

  AND destination = 'SFO'


ORDER BY month;
GO
