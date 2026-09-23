USE AirlineRouteAnalysis;
GO

/* ============================================================
   SILVER LAYER QUALITY CHECKS

   Purpose:

   Validate that Bronze-to-Silver transformations produced
   logically correct and analysis-ready data.

   Important:

   Some queries are expected to return rows for investigation.

   Comments explain the expected behaviour.
   ============================================================ */


/* ============================================================
   1. UNITED FLEET - ROW COUNT

   Expected:
   19 United mainline fleet records.
   ============================================================ */

SELECT
    COUNT(*) AS united_fleet_rows

FROM silver.united_fleet;
GO


/* ============================================================
   2. UNITED FLEET - REVIEW CLEANED DATA
   ============================================================ */

SELECT *

FROM silver.united_fleet

ORDER BY aircraft_type;
GO


/* ============================================================
   3. UNITED FLEET - FAILED CONVERSION CHECK

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.united_fleet

WHERE total_aircraft IS NULL

   OR owned_aircraft IS NULL

   OR leased_aircraft IS NULL

   OR seats_min IS NULL

   OR seats_max IS NULL

   OR average_age_years IS NULL;
GO


/* ============================================================
   4. UNITED FLEET - SEAT RANGE LOGIC

   seats_min should never exceed seats_max.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.united_fleet

WHERE seats_min > seats_max;
GO


/* ============================================================
   5. AIRCRAFT TYPES - BRONZE VS SILVER ROW COUNT
   ============================================================ */

SELECT

    (
        SELECT COUNT(*)
        FROM bronze.aircraft_types_raw
    )
        AS bronze_rows,


    (
        SELECT COUNT(*)
        FROM silver.aircraft_types
    )
        AS silver_rows;
GO


/* ============================================================
   6. AIRCRAFT TYPES - DUPLICATE AIRCRAFT IDs

   Each BTS aircraft type ID should represent one
   reference record.

   Expected:
   0 rows.
   ============================================================ */

SELECT

    aircraft_type_id,

    COUNT(*) AS record_count

FROM silver.aircraft_types

GROUP BY aircraft_type_id

HAVING COUNT(*) > 1;
GO


/* ============================================================
   7. AIRCRAFT TYPES - NULL ID CHECK

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_types

WHERE aircraft_type_id IS NULL;
GO


/* ============================================================
   8. AIRPORTS - BRONZE VS SILVER ROW COUNT
   ============================================================ */

SELECT

    (
        SELECT COUNT(*)
        FROM bronze.airports_raw
    )
        AS bronze_rows,


    (
        SELECT COUNT(*)
        FROM silver.airports
    )
        AS silver_rows;
GO


/* ============================================================
   9. AIRPORTS - REVIEW CONTROLLED PBI MAPPING

   Confirms that:

   - source value remains visible
   - PBI is available as the analysis code
   ============================================================ */

SELECT

    ident,

    source_iata_code,

    analysis_airport_code,

    airport_name,

    municipality,

    latitude_deg,

    longitude_deg

FROM silver.airports

WHERE ident = 'KPBI';
GO


/* ============================================================
   10. AIRPORTS - COORDINATE CHECK

   Investigate scheduled-service airports without
   latitude or longitude.

   Ideally no relevant United airports should fail.
   ============================================================ */

SELECT *

FROM silver.airports

WHERE scheduled_service = 'yes'

  AND
  (
      latitude_deg IS NULL

      OR longitude_deg IS NULL
  );
GO


/* ============================================================
   11. AIRPORTS - DUPLICATE ANALYSIS CODES

   Duplicate codes should be investigated before joins.

   This query is investigative rather than automatically
   assuming every returned row is an error.
   ============================================================ */

SELECT

    analysis_airport_code,

    COUNT(*) AS record_count

FROM silver.airports

WHERE analysis_airport_code IS NOT NULL

GROUP BY analysis_airport_code

HAVING COUNT(*) > 1

ORDER BY record_count DESC;
GO


/* ============================================================
   12. AIRPORT COVERAGE FOR UNITED 2025

   Collect every origin and destination used by United,
   then verify that each can match the Silver airport table.

   Expected:
   0 rows.
   ============================================================ */

WITH united_airports AS
(
    SELECT

        TRIM(origin) AS airport_code

    FROM bronze.t100_segment_raw

    WHERE unique_carrier = 'UA'

      AND class = 'F'

      AND year = 2025


    UNION


    SELECT

        TRIM(dest) AS airport_code

    FROM bronze.t100_segment_raw

    WHERE unique_carrier = 'UA'

      AND class = 'F'

      AND year = 2025
)


SELECT

    u.airport_code

FROM united_airports AS u


LEFT JOIN silver.airports AS a

    ON u.airport_code = a.analysis_airport_code


WHERE a.analysis_airport_code IS NULL


ORDER BY u.airport_code;
GO


/* ============================================================
   13. AIRCRAFT RANGE - ROW COUNT

   Expected:
   19 records.
   ============================================================ */

SELECT

    COUNT(*) AS aircraft_range_rows

FROM silver.aircraft_range;
GO


/* ============================================================
   14. AIRCRAFT RANGE - FAILED CONVERSION CHECK

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_range

WHERE aircraft_type IS NULL

   OR range_nmi IS NULL

   OR range_km IS NULL;
GO


/* ============================================================
   15. AIRCRAFT RANGE - DUPLICATE AIRCRAFT TYPE

   Expected:
   0 rows.
   ============================================================ */

SELECT

    aircraft_type,

    COUNT(*) AS record_count

FROM silver.aircraft_range

GROUP BY aircraft_type

HAVING COUNT(*) > 1;
GO


/* ============================================================
   16. AIRCRAFT RANGE - FLEET COVERAGE

   Every United fleet aircraft should ideally have a
   corresponding range reference.

   Expected:
   0 rows.
   ============================================================ */

SELECT

    f.aircraft_type

FROM silver.united_fleet AS f


LEFT JOIN silver.aircraft_range AS r

    ON f.aircraft_type = r.aircraft_type


WHERE r.aircraft_type IS NULL


ORDER BY f.aircraft_type;
GO


/* ============================================================
   17. AIRCRAFT MAPPING - REVIEW
   ============================================================ */

SELECT *

FROM silver.aircraft_mapping

ORDER BY aircraft_type_id;
GO


/* ============================================================
   18. AIRCRAFT MAPPING - DUPLICATE BTS CODE

   Each BTS code should appear once.

   Expected:
   0 rows.
   ============================================================ */

SELECT

    aircraft_type_id,

    COUNT(*) AS record_count

FROM silver.aircraft_mapping

GROUP BY aircraft_type_id

HAVING COUNT(*) > 1;
GO


/* ============================================================
   19. AIRCRAFT MAPPING - T-100 COVERAGE

   Check whether every aircraft type appearing in the
   United monthly route table has a mapping.

   Expected:
   0 rows.
   ============================================================ */

SELECT DISTINCT

    r.aircraft_type_id

FROM silver.route_aircraft_monthly AS r


LEFT JOIN silver.aircraft_mapping AS m

    ON r.aircraft_type_id = m.aircraft_type_id


WHERE m.aircraft_type_id IS NULL


ORDER BY r.aircraft_type_id;
GO


/* ============================================================
   20. AIRCRAFT MAPPING - VALIDATE EXACT UNITED NAMES

   Exact mappings should correspond to a real aircraft
   name in silver.united_fleet.

   Code 627 is deliberately excluded because its mapping
   status is Ambiguous.

   Expected:
   0 rows.
   ============================================================ */

SELECT

    m.aircraft_type_id,

    m.standard_aircraft_type,

    m.united_aircraft_type,

    m.mapping_status

FROM silver.aircraft_mapping AS m


LEFT JOIN silver.united_fleet AS f

    ON m.united_aircraft_type = f.aircraft_type


WHERE m.mapping_status = 'Exact'

  AND f.aircraft_type IS NULL;
GO


/* ============================================================
   21. AIRCRAFT MAPPING - REVIEW AMBIGUITIES

   Expected:
   BTS code 627 should appear here.
   ============================================================ */

SELECT *

FROM silver.aircraft_mapping

WHERE mapping_status <> 'Exact';
GO


/* ============================================================
   22. ROUTE TABLE - ROW COUNT
   ============================================================ */

SELECT

    COUNT(*) AS route_aircraft_monthly_rows

FROM silver.route_aircraft_monthly;
GO


/* ============================================================
   23. ROUTE TABLE - GRAIN DUPLICATE CHECK

   Grain:

       year
       + month
       + origin
       + destination
       + aircraft type

   Expected:
   0 rows.
   ============================================================ */

SELECT

    year,

    month,

    origin,

    destination,

    aircraft_type_id,

    COUNT(*) AS record_count

FROM silver.route_aircraft_monthly


GROUP BY

    year,

    month,

    origin,

    destination,

    aircraft_type_id


HAVING COUNT(*) > 1;
GO


/* ============================================================
   24. ROUTE TABLE - KEY NULL CHECK

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.route_aircraft_monthly

WHERE year IS NULL

   OR month IS NULL

   OR month_start_date IS NULL

   OR origin IS NULL

   OR destination IS NULL

   OR aircraft_type_id IS NULL;
GO


/* ============================================================
   25. ROUTE TABLE - MONTH VALIDATION

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.route_aircraft_monthly

WHERE month NOT BETWEEN 1 AND 12;
GO


/* ============================================================
   26. ROUTE TABLE - NEGATIVE VALUE CHECK

   Negative values for these operational measures would
   require investigation.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.route_aircraft_monthly

WHERE departures_scheduled < 0

   OR departures_performed < 0

   OR passengers < 0

   OR seats < 0;
GO


/* ============================================================
   27. ROUTE TABLE - ZERO PERFORMED DEPARTURES

   These records are not automatically treated as errors.

   Bronze profiling identified source records where no
   departures were performed.

   They are retained for traceability.

   Later calculations should use NULLIF() to avoid
   division-by-zero errors.
   ============================================================ */

SELECT

    COUNT(*) AS zero_performed_route_month_rows

FROM silver.route_aircraft_monthly

WHERE departures_performed = 0;
GO


/* ============================================================
   28. ROUTE TABLE - SOURCE RECORD COUNT

   Every Silver row should originate from at least one
   Bronze record.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.route_aircraft_monthly

WHERE source_record_count <= 0

   OR source_record_count IS NULL;
GO


/* ============================================================
   29. VALIDATE KNOWN EWR -> SFO EXAMPLE

   January 2025
   EWR -> SFO
   Aircraft code 627

   Earlier Bronze profiling found three records.

   Expected approximately:

       departures_scheduled = 126
       departures_performed = 128
       passengers = 30,909
       seats = 35,592
       distance = 2,565
       source_record_count = 3
   ============================================================ */

SELECT *

FROM silver.route_aircraft_monthly

WHERE year = 2025

  AND month = 1

  AND origin = 'EWR'

  AND destination = 'SFO'

  AND aircraft_type_id = 627;
GO


/* ============================================================
   30. AGGREGATION RECONCILIATION - PASSENGERS

   Total United Class F 2025 passengers in Bronze should
   equal the total represented in Silver.

   Grouping should change row count but should not change
   additive totals.
   ============================================================ */

SELECT

    (
        SELECT SUM(passengers)

        FROM bronze.t100_segment_raw

        WHERE unique_carrier = 'UA'

          AND class = 'F'

          AND year = 2025
    )
        AS bronze_passengers,


    (
        SELECT SUM(passengers)

        FROM silver.route_aircraft_monthly
    )
        AS silver_passengers;
GO


/* ============================================================
   31. AGGREGATION RECONCILIATION - SEATS
   ============================================================ */

SELECT

    (
        SELECT SUM(seats)

        FROM bronze.t100_segment_raw

        WHERE unique_carrier = 'UA'

          AND class = 'F'

          AND year = 2025
    )
        AS bronze_seats,


    (
        SELECT SUM(seats)

        FROM silver.route_aircraft_monthly
    )
        AS silver_seats;
GO


/* ============================================================
   32. AGGREGATION RECONCILIATION - PERFORMED DEPARTURES
   ============================================================ */

SELECT

    (
        SELECT SUM(departures_performed)

        FROM bronze.t100_segment_raw

        WHERE unique_carrier = 'UA'

          AND class = 'F'

          AND year = 2025
    )
        AS bronze_departures_performed,


    (
        SELECT SUM(departures_performed)

        FROM silver.route_aircraft_monthly
    )
        AS silver_departures_performed;
GO


/* ============================================================
   33. OPTIONAL ROUTE ANALYTICAL PREVIEW

   These metrics are NOT permanently stored in Silver.

   This query demonstrates how Silver provides the
   clean building blocks required by Gold.

   NULLIF prevents division by zero.
   ============================================================ */

SELECT TOP 100

    year,

    month,

    origin,

    destination,

    aircraft_type_id,

    passengers,

    seats,

    departures_performed,


    /* Average passengers carried per performed flight */

    CAST(
        passengers
        AS DECIMAL(18,2)
    )

    /

    NULLIF(
        departures_performed,
        0
    )
        AS passengers_per_flight,


    /* Average seats supplied per performed flight */

    CAST(
        seats
        AS DECIMAL(18,2)
    )

    /

    NULLIF(
        departures_performed,
        0
    )
        AS seats_per_flight,


    /* Percentage of available seats occupied */

    CAST(
        passengers
        AS DECIMAL(18,2)
    )

    /

    NULLIF(
        seats,
        0
    )

    * 100
        AS load_factor_pct


FROM silver.route_aircraft_monthly


ORDER BY

    year,

    month,

    origin,

    destination,

    aircraft_type_id;
GO


/* ============================================================
   34. AIRCRAFT OPERATING COST - ROW COUNT

   Silver grain:

       year
       + quarter
       + aircraft type

   Expected:

       18 aircraft types
       ×
       4 quarters
       =
       72 rows
   ============================================================ */

SELECT

    COUNT(*) AS aircraft_operating_cost_rows

FROM silver.aircraft_operating_cost;
GO


/* ============================================================
   35. AIRCRAFT OPERATING COST - GRAIN DUPLICATE CHECK

   Each:

       year
       + quarter
       + aircraft type

   combination should appear once.

   Expected:
   0 rows.
   ============================================================ */

SELECT

    year,

    quarter,

    aircraft_type_id,

    COUNT(*) AS record_count

FROM silver.aircraft_operating_cost


GROUP BY

    year,

    quarter,

    aircraft_type_id


HAVING COUNT(*) > 1;
GO


/* ============================================================
   36. AIRCRAFT OPERATING COST - KEY NULL CHECK

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_operating_cost

WHERE year IS NULL

   OR quarter IS NULL

   OR aircraft_type_id IS NULL;
GO


/* ============================================================
   37. AIRCRAFT OPERATING COST - YEAR / QUARTER VALIDATION

   Project period:

       2025

   Valid quarter:

       1 - 4

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_operating_cost

WHERE year <> 2025

   OR quarter NOT BETWEEN 1 AND 4;
GO


/* ============================================================
   38. AIRCRAFT OPERATING COST - AIRCRAFT COVERAGE

   Expected:
   18 distinct usable BTS aircraft types.
   ============================================================ */

SELECT

    COUNT(
        DISTINCT aircraft_type_id
    )
        AS distinct_aircraft_types

FROM silver.aircraft_operating_cost;
GO


/* ============================================================
   39. AIRCRAFT OPERATING COST - QUARTER COVERAGE

   Every aircraft should have all four quarters.

   Expected:

       quarter_count = 4

   for every aircraft.
   ============================================================ */

SELECT

    aircraft_type_id,

    COUNT(
        DISTINCT quarter
    )
        AS quarter_count

FROM silver.aircraft_operating_cost


GROUP BY aircraft_type_id


ORDER BY aircraft_type_id;
GO


/* ============================================================
   40. AIRCRAFT OPERATING COST - MISSING QUARTER CHECK

   Failure-only version of the previous check.

   Expected:
   0 rows.
   ============================================================ */

SELECT

    aircraft_type_id,

    COUNT(
        DISTINCT quarter
    )
        AS quarter_count

FROM silver.aircraft_operating_cost


GROUP BY aircraft_type_id


HAVING COUNT(
    DISTINCT quarter
) <> 4;
GO


/* ============================================================
   41. AIRCRAFT OPERATING COST - POSITIVE VALUE CHECK

   Fuel, airborne hours and operating expense should be
   positive for the usable analytical records.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_operating_cost

WHERE total_air_hours <= 0

   OR fuel_issued_gallons <= 0

   OR aircraft_operating_expense_dollars <= 0

   OR fuel_gallons_per_air_hour <= 0

   OR operating_cost_per_air_hour <= 0;
GO


/* ============================================================
   42. AIRCRAFT OPERATING COST - NULL ECONOMICS CHECK

   These are the main aircraft economics metrics required
   by later Gold analysis.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_operating_cost

WHERE fuel_gallons_per_air_hour IS NULL

   OR fuel_cost_per_air_hour IS NULL

   OR operating_cost_per_air_hour IS NULL

   OR maintenance_cost_per_air_hour IS NULL;
GO


/* ============================================================
   43. AIRCRAFT OPERATING COST - MAPPING COVERAGE

   Every aircraft code in the economics table should exist
   in the controlled aircraft mapping.

   LEFT JOIN keeps unmatched economics codes visible.

   Expected:
   0 rows.
   ============================================================ */

SELECT DISTINCT

    c.aircraft_type_id

FROM silver.aircraft_operating_cost AS c


LEFT JOIN silver.aircraft_mapping AS m

    ON c.aircraft_type_id = m.aircraft_type_id


WHERE m.aircraft_type_id IS NULL


ORDER BY c.aircraft_type_id;
GO


/* ============================================================
   44. AIRCRAFT OPERATING COST - FUEL RATE CHECK

   Recalculate:

       fuel gallons
       ------------
       airborne hours

   and compare against the stored derived value.

   A 0.01 tolerance allows for decimal rounding.

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_operating_cost

WHERE ABS
(
    fuel_gallons_per_air_hour

    -

    (
        fuel_issued_gallons

        /

        NULLIF(
            total_air_hours,
            0
        )
    )
)
> 0.01;
GO


/* ============================================================
   45. AIRCRAFT OPERATING COST - FUEL COST RATE CHECK

   Recalculate:

       fuel expense
       ------------
       airborne hours

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_operating_cost

WHERE ABS
(
    fuel_cost_per_air_hour

    -

    (
        fuel_expense_dollars

        /

        NULLIF(
            total_air_hours,
            0
        )
    )
)
> 0.01;
GO


/* ============================================================
   46. AIRCRAFT OPERATING COST - OPERATING COST RATE CHECK

   Recalculate:

       aircraft operating expense
       ---------------------------
       airborne hours

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_operating_cost

WHERE ABS
(
    operating_cost_per_air_hour

    -

    (
        aircraft_operating_expense_dollars

        /

        NULLIF(
            total_air_hours,
            0
        )
    )
)
> 0.01;
GO


/* ============================================================
   47. AIRCRAFT OPERATING COST - MAINTENANCE RATE CHECK

   Recalculate:

       flight maintenance expense
       --------------------------
       airborne hours

   Expected:
   0 rows.
   ============================================================ */

SELECT *

FROM silver.aircraft_operating_cost

WHERE ABS
(
    maintenance_cost_per_air_hour

    -

    (
        flight_maintenance_expense_dollars

        /

        NULLIF(
            total_air_hours,
            0
        )
    )
)
> 0.01;
GO


/* ============================================================
   48. AIRCRAFT OPERATING COST - BRONZE VS SILVER ROW COUNT

   Bronze is filtered to:

       United Airlines
       2025
       Domestic region
       Aircraft code != 999

   Since the quarterly grain is preserved, the filtered
   Bronze record count should equal the Silver record count.

   Expected:
       72 vs 72
   ============================================================ */

SELECT

    (
        SELECT COUNT(*)

        FROM bronze.aircraft_operating_cost_raw

        WHERE TRIM(unique_carrier) = 'UA'

          AND TRY_CAST(
                NULLIF(TRIM([year]), '')
                AS INT
              ) = 2025

          AND TRIM(region) = 'D'

          AND TRY_CAST(
                NULLIF(TRIM(aircraft_type), '')
                AS INT
              ) <> 999
    )
        AS filtered_bronze_rows,


    (
        SELECT COUNT(*)

        FROM silver.aircraft_operating_cost
    )
        AS silver_rows;
GO


/* ============================================================
   49. AIRCRAFT ECONOMICS WITH READABLE AIRCRAFT NAMES

   Analytical preview.

   The economics table stores the BTS aircraft ID.

   The controlled mapping supplies a readable aircraft name.

   Code 627 remains deliberately represented at family level
   because exact United subtype identification is not
   supported by the BTS aircraft code.
   ============================================================ */

SELECT

    c.year,

    c.quarter,

    c.aircraft_type_id,

    m.standard_aircraft_type,

    m.united_aircraft_type,

    m.mapping_status,

    c.fuel_gallons_per_air_hour,

    c.fuel_cost_per_air_hour,

    c.operating_cost_per_air_hour,

    c.maintenance_cost_per_air_hour


FROM silver.aircraft_operating_cost AS c


LEFT JOIN silver.aircraft_mapping AS m

    ON c.aircraft_type_id = m.aircraft_type_id


ORDER BY

    c.aircraft_type_id,

    c.quarter;
GO
