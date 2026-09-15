/*==============================================================================
    Project:     Aircraft Route Suitability Analysis
    Script:      04_bronze_quality_checks.sql
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
FROM bronze.t100_segment_raw;
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
GO
