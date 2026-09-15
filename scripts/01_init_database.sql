
/*==============================================================================
    Project:     Aircraft Route Suitability Analysis
    Script:      01_init_database.sql
    Description: Creates the project database and Medallion architecture schemas.
==============================================================================*/

USE master;
GO


/*==============================================================================
    Create Database

    The database is only created if it does not already exist, allowing
    the script to be safely rerun during development.
==============================================================================*/

IF NOT EXISTS (
    SELECT 1
    FROM sys.databases
    WHERE name = 'AirlineRouteAnalysis'
)
BEGIN
    CREATE DATABASE AirlineRouteAnalysis;
END;
GO


USE AirlineRouteAnalysis;
GO


/*==============================================================================
    Create Medallion Schemas

    Bronze - Raw source data
    Silver - Cleaned and standardised data
    Gold   - Business-ready analytical data
==============================================================================*/


-- Bronze Schema
IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'bronze'
)
BEGIN
    EXEC('CREATE SCHEMA bronze');
END;
GO


-- Silver Schema
IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'silver'
)
BEGIN
    EXEC('CREATE SCHEMA silver');
END;
GO


-- Gold Schema
IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'gold'
)
BEGIN
    EXEC('CREATE SCHEMA gold');
END;
GO


/*==============================================================================
    Validation
==============================================================================*/

SELECT DB_NAME() AS current_database;
GO
