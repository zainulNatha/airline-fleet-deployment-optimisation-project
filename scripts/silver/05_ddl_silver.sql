USE AirlineRouteAnalysis;
GO

/* ============================================================
   SILVER LAYER - TABLE DEFINITIONS

   Purpose:
   Create cleaned and standardised tables used between
   the raw Bronze layer and the analytical Gold layer.
   ============================================================ */


/* ============================================================
   1. UNITED FLEET
   ============================================================ */

DROP TABLE IF EXISTS silver.united_fleet;
GO

CREATE TABLE silver.united_fleet
(
    aircraft_type       NVARCHAR(50),
    total_aircraft      INT,
    owned_aircraft      INT,
    leased_aircraft     INT,
    seats_min           INT,
    seats_max           INT,
    average_age_years   DECIMAL(4,1)
);
GO


/* ============================================================
   2. BTS AIRCRAFT TYPES
   ============================================================ */

DROP TABLE IF EXISTS silver.aircraft_types;
GO

CREATE TABLE silver.aircraft_types
(
    aircraft_type_id    INT,
    aircraft_group      INT,
    ssd_name            NVARCHAR(150),
    manufacturer        NVARCHAR(100),
    long_name           NVARCHAR(255),
    short_name          NVARCHAR(100),
    begin_date          DATE,
    end_date            DATE
);
GO


/* ============================================================
   3. AIRPORT REFERENCE
   ============================================================ */

DROP TABLE IF EXISTS silver.airports;
GO

CREATE TABLE silver.airports
(
    airport_id             INT,
    ident                  NVARCHAR(20),
    source_iata_code       NVARCHAR(10),
    analysis_airport_code  NVARCHAR(10),

    airport_name           NVARCHAR(255),
    airport_type           NVARCHAR(50),
    municipality           NVARCHAR(150),
    iso_region             NVARCHAR(50),
    iso_country            NVARCHAR(20),

    latitude_deg           DECIMAL(10,6),
    longitude_deg          DECIMAL(10,6),

    scheduled_service      NVARCHAR(10)
);
GO


/* ============================================================
   4. AIRCRAFT RANGE
   ============================================================ */

DROP TABLE IF EXISTS silver.aircraft_range;
GO

CREATE TABLE silver.aircraft_range
(
    aircraft_type   NVARCHAR(50),
    range_nmi       DECIMAL(10,2),
    range_km        DECIMAL(10,2),
    range_basis     NVARCHAR(255),
    source_name     NVARCHAR(100),
    source_url      NVARCHAR(1000)
);
GO


/* ============================================================
   5. AIRCRAFT MAPPING

   Bridges BTS aircraft codes used by T-100 with the
   aircraft names used by United's fleet reference.

   mapping_status allows source ambiguity to be documented
   instead of forcing an unsupported match.
   ============================================================ */

DROP TABLE IF EXISTS silver.aircraft_mapping;
GO

CREATE TABLE silver.aircraft_mapping
(
    aircraft_type_id        INT,
    standard_aircraft_type  NVARCHAR(50),
    united_aircraft_type    NVARCHAR(50),
    mapping_status          NVARCHAR(30),
    mapping_note            NVARCHAR(255)
);
GO


/* ============================================================
   6. MONTHLY ROUTE-AIRCRAFT PERFORMANCE

   Grain:
   One row per:
       year
       + month
       + origin
       + destination
       + aircraft type

   Routes remain directional.
   ============================================================ */

DROP TABLE IF EXISTS silver.route_aircraft_monthly;
GO

CREATE TABLE silver.route_aircraft_monthly
(
    year                    INT,
    month                   INT,
    month_start_date        DATE,

    origin                  NVARCHAR(10),
    destination             NVARCHAR(10),
    aircraft_type_id        INT,

    departures_scheduled    INT,
    departures_performed    INT,
    passengers              INT,
    seats                   INT,

    payload                 DECIMAL(18,2),
    freight                 DECIMAL(18,2),
    mail                    DECIMAL(18,2),

    distance_miles          DECIMAL(10,2),
    air_time_minutes        DECIMAL(18,2),
    ramp_to_ramp_minutes    DECIMAL(18,2),

    source_record_count     INT,

    dwh_create_date         DATETIME2 DEFAULT SYSDATETIME()
);
GO
