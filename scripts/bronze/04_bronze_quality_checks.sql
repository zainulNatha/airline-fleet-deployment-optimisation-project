/*==============================================================================
Project: Aircraft Route Suitability Analysis

Script: 04_bronze_quality_checks.sql

Description: Performs initial checks following Bronze ingestion.

Purpose:

- Confirm that each source was successfully loaded.

- Review sample records.

- Detect obvious ingestion problems before Silver transformation.
==============================================================================*/

USE AirlineRouteAnalysis;

GO


/*==============================================================================

1. Row Count Validation

==============================================================================*/

SELECT

'United Fleet' AS source_table,

COUNT(*) AS row_count

FROM bronze.united_fleet_raw


UNION ALL


SELECT

'Aircraft Range',

COUNT(*)

FROM bronze.aircraft_range_raw


UNION ALL


SELECT

'Aircraft Types',

COUNT(*)

FROM bronze.aircraft_types_raw


UNION ALL


SELECT

'Airports',

COUNT(*)

FROM bronze.airports_raw


UNION ALL


SELECT

'T-100 Segment',

COUNT(*)

FROM bronze.t100_segment_raw


UNION ALL


SELECT

'Aircraft Operating Cost',

COUNT(*)

FROM bronze.aircraft_operating_cost_raw;

GO


/*==============================================================================

2. Sample Record Validation

Small samples are reviewed rather than returning every record,
particularly for the large T-100 dataset.

==============================================================================*/


-- United Fleet

SELECT TOP 20 *

FROM bronze.united_fleet_raw;


-- Aircraft Range

SELECT TOP 20 *

FROM bronze.aircraft_range_raw;


-- BTS Aircraft Types

SELECT TOP 20 *

FROM bronze.aircraft_types_raw;


-- Airports

SELECT TOP 20 *

FROM bronze.airports_raw;


-- T-100 Segment Data

SELECT TOP 20 *

FROM bronze.t100_segment_raw;


-- BTS Form 41 Schedule P-5.2

SELECT TOP 20 *

FROM bronze.aircraft_operating_cost_raw;

GO


/*==============================================================================

3. Schedule P-5.2 Year Validation

The downloaded operating-cost source was selected for 2025.

Expected:

2025 only.

==============================================================================*/

SELECT

year,

COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

GROUP BY year

ORDER BY year;

GO


/*==============================================================================

4. Schedule P-5.2 Quarter Validation

Schedule P-5.2 is reported quarterly.

Expected:

Quarter 1
Quarter 2
Quarter 3
Quarter 4

==============================================================================*/

SELECT

quarter,

COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

GROUP BY quarter

ORDER BY quarter;

GO


/*==============================================================================

5. United Airlines Record Validation

Confirms that United Airlines records exist in the raw source.

No carrier filtering is performed in Bronze.

==============================================================================*/

SELECT

unique_carrier,

unique_carrier_name,

COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

WHERE unique_carrier = 'UA'

GROUP BY

unique_carrier,

unique_carrier_name;

GO


/*==============================================================================

6. United Operating Region Distribution

The source reports records across different operating regions.

This check helps understand the source before Silver selects the
domestic records required for this project.

==============================================================================*/

SELECT

region,

COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

WHERE unique_carrier = 'UA'

GROUP BY region

ORDER BY region;

GO


/*==============================================================================

7. United Aircraft Type Distribution

Shows the BTS aircraft type codes available for United.

The generic aircraft code 999 will be reviewed and excluded later
during Silver transformation.

==============================================================================*/

SELECT

aircraft_type,

COUNT(*) AS record_count

FROM bronze.aircraft_operating_cost_raw

WHERE unique_carrier = 'UA'

GROUP BY aircraft_type

ORDER BY TRY_CAST(aircraft_type AS INT);

GO


/*==============================================================================

8. Blank Operating Expense Review

The raw BTS source contains blank financial values for some rows.

This is not automatically an ingestion error.

Bronze preserves those source values and Silver will determine
which records are suitable for analysis.

==============================================================================*/

SELECT

COUNT(*) AS rows_with_blank_operating_cost

FROM bronze.aircraft_operating_cost_raw

WHERE NULLIF(

TRIM(tot_air_op_expenses),

''

) IS NULL;

GO
