/*==============================================================================
    Project:     Aircraft Route Suitability Analysis
    Script:      03_proc_load_bronze.sql
    Description: Loads raw CSV source files into the Bronze layer.

    Process:
        1. Empty the existing Bronze table.
        2. Reload the latest source file using BULK INSERT.
        3. Preserve the raw source before Silver transformations begin.

    NOTE:
        Update the local file paths before executing this procedure.
==============================================================================*/

USE AirlineRouteAnalysis;
GO


CREATE OR ALTER PROCEDURE bronze.load_bronze
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE @start_time DATETIME2;
    DECLARE @end_time   DATETIME2;

    BEGIN TRY

        SET @start_time = SYSDATETIME();

        PRINT '================================================';
        PRINT 'Starting Bronze Layer Load';
        PRINT '================================================';


        /*======================================================================
            1. United Fleet
        ======================================================================*/

        PRINT 'Loading: bronze.united_fleet_raw';

        TRUNCATE TABLE bronze.united_fleet_raw;

        BULK INSERT bronze.united_fleet_raw
        FROM 'C:\AirlineRouteAnalysis\data\raw\united_fleet_2025_raw.csv'
        WITH
        (
            FORMAT = 'CSV',
            FIRSTROW = 2,
            FIELDQUOTE = '"',
            CODEPAGE = '65001',
            TABLOCK
        );


        /*======================================================================
            2. Aircraft Range Reference
        ======================================================================*/

        PRINT 'Loading: bronze.aircraft_range_raw';

        TRUNCATE TABLE bronze.aircraft_range_raw;

        BULK INSERT bronze.aircraft_range_raw
        FROM 'C:\AirlineRouteAnalysis\data\raw\aircraft_range_raw.csv'
        WITH
        (
            FORMAT = 'CSV',
            FIRSTROW = 2,
            FIELDQUOTE = '"',
            CODEPAGE = '65001',
            TABLOCK
        );


        /*======================================================================
            3. BTS Aircraft Type Lookup
        ======================================================================*/

        PRINT 'Loading: bronze.aircraft_types_raw';

        TRUNCATE TABLE bronze.aircraft_types_raw;

        BULK INSERT bronze.aircraft_types_raw
        FROM 'C:\AirlineRouteAnalysis\data\raw\T_AIRCRAFT_TYPES.csv'
        WITH
        (
            FORMAT = 'CSV',
            FIRSTROW = 2,
            FIELDQUOTE = '"',
            CODEPAGE = '65001',
            TABLOCK
        );


        /*======================================================================
            4. Airport Reference

            This source uses LF line endings, so ROWTERMINATOR = '0x0a'
            is specified explicitly.
        ======================================================================*/

        PRINT 'Loading: bronze.airports_raw';

        TRUNCATE TABLE bronze.airports_raw;

        BULK INSERT bronze.airports_raw
        FROM 'C:\AirlineRouteAnalysis\data\raw\airports.csv'
        WITH
        (
            FORMAT = 'CSV',
            FIRSTROW = 2,
            FIELDQUOTE = '"',
            ROWTERMINATOR = '0x0a',
            CODEPAGE = '65001',
            TABLOCK
        );


        /*======================================================================
            5. BTS T-100 Segment Data

            The full dataset is loaded in Bronze.

            United Airlines filtering will be performed later in Silver.
        ======================================================================*/

        PRINT 'Loading: bronze.t100_segment_raw';

        TRUNCATE TABLE bronze.t100_segment_raw;

        BULK INSERT bronze.t100_segment_raw
        FROM 'C:\AirlineRouteAnalysis\data\raw\T_T100_SEGMENT_ALL_CARRIER.csv'
        WITH
        (
            FORMAT = 'CSV',
            FIRSTROW = 2,
            FIELDQUOTE = '"',
            CODEPAGE = '65001',
            TABLOCK
        );


        /*======================================================================
            Load Summary
        ======================================================================*/

        SET @end_time = SYSDATETIME();

        PRINT '================================================';
        PRINT 'Bronze Layer Loaded Successfully';
        PRINT 'Total Load Duration: '
            + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR(20))
            + ' seconds';
        PRINT '================================================';

    END TRY


    BEGIN CATCH

        PRINT '================================================';
        PRINT 'Bronze Layer Load Failed';

        PRINT 'Error Number: '
            + CAST(ERROR_NUMBER() AS NVARCHAR(20));

        PRINT 'Error Line: '
            + CAST(ERROR_LINE() AS NVARCHAR(20));

        PRINT 'Error Message: '
            + ERROR_MESSAGE();

        PRINT '================================================';

        THROW;

    END CATCH

END;
GO


/*==============================================================================
    Execute Procedure

    Uncomment to reload the complete Bronze layer.
==============================================================================*/

-- EXEC bronze.load_bronze;
-- GO
