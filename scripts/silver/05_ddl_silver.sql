USE AirlineRouteAnalysis;
GO

/* ============================================================
   SILVER LAYER - TABLE DEFINITIONS

   Purpose:

   Create cleaned and standardised tables used between
   the raw Bronze layer and the analytical Gold layer.

   Silver tables:

   1. United Fleet
   2. BTS Aircraft Types
   3. Airport Reference
   4. Aircraft Range
   5. Aircraft Mapping
   6. Monthly Route-Aircraft Performance
   7. Quarterly Aircraft Operating Cost
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

    /* Preserve the original airport source value */
    source_iata_code       NVARCHAR(10),

    /* Code used consistently by this analysis */
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

   Bridges BTS aircraft codes used by T-100 and Form 41
   with the aircraft names used by United's fleet reference.

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

   Example:

       EWR -> SFO

   remains separate from:

       SFO -> EWR
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

    /* Number of raw Bronze rows aggregated into this row */
    source_record_count     INT,

    dwh_create_date         DATETIME2
        DEFAULT SYSDATETIME()
);
GO


/* ============================================================
   7. QUARTERLY AIRCRAFT OPERATING COST

   Source:
   BTS Form 41 Schedule P-5.2

   Purpose:
   Store cleaned aircraft-level operating economics for
   United Airlines domestic operations.

   Silver grain:

       one row per:

       year
       + quarter
       + BTS aircraft type

   The source is kept quarterly rather than immediately
   aggregated to an annual value.

   This preserves useful variation throughout the year.

   Later Gold analysis can map:

       January - March    -> Q1
       April - June       -> Q2
       July - September   -> Q3
       October - December -> Q4

   BTS reports the selected financial, fuel and activity
   measures in thousands.

   Silver converts them to normal units:

       $000          -> dollars
       000 hours     -> hours
       000 days      -> days
       000 gallons   -> gallons

   Derived rates are calculated using the converted values.
   ============================================================ */

DROP TABLE IF EXISTS silver.aircraft_operating_cost;
GO

CREATE TABLE silver.aircraft_operating_cost
(
    /* --------------------------------------------------------
       IDENTIFIERS / GRAIN
       -------------------------------------------------------- */

    year                                    INT,

    quarter                                 INT,

    aircraft_type_id                        INT,


    /* --------------------------------------------------------
       QUARTERLY EXPENSE TOTALS

       Stored in actual dollar units after conversion from
       BTS $000 source values.
       -------------------------------------------------------- */

    fuel_expense_dollars                    DECIMAL(18,2),

    flying_operations_expense_dollars       DECIMAL(18,2),

    direct_maintenance_expense_dollars      DECIMAL(18,2),

    flight_maintenance_expense_dollars      DECIMAL(18,2),

    aircraft_operating_expense_dollars      DECIMAL(18,2),


    /* --------------------------------------------------------
       QUARTERLY AIRCRAFT ACTIVITY

       Stored in normal units rather than source (000) units.
       -------------------------------------------------------- */

    total_air_hours                         DECIMAL(18,2),

    aircraft_days_assigned                  DECIMAL(18,2),

    fuel_issued_gallons                     DECIMAL(18,2),


    /* --------------------------------------------------------
       DERIVED QUARTERLY ECONOMICS METRICS

       These put aircraft on a common airborne-hour basis.
       -------------------------------------------------------- */

    fuel_gallons_per_air_hour               DECIMAL(18,2),

    fuel_cost_per_air_hour                  DECIMAL(18,2),

    operating_cost_per_air_hour             DECIMAL(18,2),

    maintenance_cost_per_air_hour           DECIMAL(18,2),


    /* --------------------------------------------------------
       DATA WAREHOUSE METADATA
       -------------------------------------------------------- */

    dwh_create_date                         DATETIME2
        DEFAULT SYSDATETIME()
);
GO
