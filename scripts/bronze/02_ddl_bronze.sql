/*==============================================================================
Project: Aircraft Route Suitability Analysis

Script: 02_ddl_bronze.sql

Description: Creates the raw Bronze-layer tables used to ingest
the project source datasets.
==============================================================================*/

USE AirlineRouteAnalysis;

GO


/*==============================================================================

1. BTS T-100 Segment Data

Main operational dataset containing:

- Passenger demand
- Seats
- Departures
- Route distance
- Aircraft type
- Origin and destination
- Month and year

No airline filtering or business transformations are performed in Bronze.

==============================================================================*/

DROP TABLE IF EXISTS bronze.t100_segment_raw;

GO

CREATE TABLE bronze.t100_segment_raw

(

departures_scheduled DECIMAL(18,2),

departures_performed DECIMAL(18,2),

payload DECIMAL(18,2),

seats DECIMAL(18,2),

passengers DECIMAL(18,2),

freight DECIMAL(18,2),

mail DECIMAL(18,2),

distance DECIMAL(18,2),

ramp_to_ramp DECIMAL(18,2),

air_time DECIMAL(18,2),

unique_carrier NVARCHAR(10),

airline_id INT,

unique_carrier_name NVARCHAR(150),

origin_airport_id INT,

origin NVARCHAR(10),

origin_city_name NVARCHAR(100),

origin_state_abr NVARCHAR(10),

dest_airport_id INT,

dest NVARCHAR(10),

dest_city_name NVARCHAR(100),

dest_state_abr NVARCHAR(10),

aircraft_type INT,

aircraft_config INT,

year INT,

quarter INT,

month INT,

class NVARCHAR(10)

);

GO


/*==============================================================================

2. BTS Aircraft Type Lookup

Used later to translate BTS aircraft codes into readable aircraft
names and manufacturers.

==============================================================================*/

DROP TABLE IF EXISTS bronze.aircraft_types_raw;

GO

CREATE TABLE bronze.aircraft_types_raw

(

ac_typeid INT,

ac_group INT,

ssd_name NVARCHAR(150),

manufacturer NVARCHAR(100),

long_name NVARCHAR(255),

short_name NVARCHAR(100),

begin_date NVARCHAR(50),

end_date NVARCHAR(50)

);

GO


/*==============================================================================

3. United Airlines Fleet Reference

Raw fleet values are initially stored as text because source fields
contain values such as:

—

167-203

276-362

These values will be cleaned and converted in the Silver layer.

==============================================================================*/

DROP TABLE IF EXISTS bronze.united_fleet_raw;

GO

CREATE TABLE bronze.united_fleet_raw

(

aircraft_type NVARCHAR(50),

total NVARCHAR(20),

owned NVARCHAR(20),

leased NVARCHAR(20),

seats_in_standard_configuration NVARCHAR(20),

average_age_years NVARCHAR(20)

);

GO


/*==============================================================================

4. Airport Reference Data

Airport coordinates and identifiers are preserved in raw text form
during ingestion and will be converted to appropriate data types
during Silver transformation.

==============================================================================*/

DROP TABLE IF EXISTS bronze.airports_raw;

GO

CREATE TABLE bronze.airports_raw

(

id NVARCHAR(50),

ident NVARCHAR(20),

type NVARCHAR(50),

name NVARCHAR(255),

latitude_deg NVARCHAR(50),

longitude_deg NVARCHAR(50),

elevation_ft NVARCHAR(50),

continent NVARCHAR(20),

iso_country NVARCHAR(20),

iso_region NVARCHAR(50),

municipality NVARCHAR(150),

scheduled_service NVARCHAR(20),

icao_code NVARCHAR(20),

iata_code NVARCHAR(20),

gps_code NVARCHAR(20),

local_code NVARCHAR(20),

home_link NVARCHAR(500),

wikipedia_link NVARCHAR(500),

keywords NVARCHAR(MAX)

);

GO


/*==============================================================================

5. Aircraft Range Reference

Manufacturer-published aircraft range information used later as
a high-level route feasibility check.

==============================================================================*/

DROP TABLE IF EXISTS bronze.aircraft_range_raw;

GO

CREATE TABLE bronze.aircraft_range_raw

(

aircraft_type NVARCHAR(50),

range_nmi NVARCHAR(50),

range_km NVARCHAR(50),

range_basis NVARCHAR(255),

source_name NVARCHAR(100),

source_url NVARCHAR(1000)

);

GO


/*==============================================================================

6. BTS Form 41 Schedule P-5.2

Quarterly aircraft operating expense, fuel, maintenance and
utilisation data.

The source contains:

- Multiple airlines
- Multiple operating regions
- Multiple aircraft types
- Quarterly records

No United Airlines, domestic-region or aircraft filtering is
performed in Bronze.

Numeric-looking values are initially stored as text because the
raw source contains blank values.

Data type conversion and analytical filtering will be performed
later in the Silver layer.

==============================================================================*/

DROP TABLE IF EXISTS bronze.aircraft_operating_cost_raw;

GO

CREATE TABLE bronze.aircraft_operating_cost_raw

(

fuel_fly_ops NVARCHAR(50),

tot_fly_ops NVARCHAR(50),

tot_dir_maint NVARCHAR(50),

tot_flt_maint_memo NVARCHAR(50),

tot_air_op_expenses NVARCHAR(50),

total_air_hours NVARCHAR(50),

air_days_assign NVARCHAR(50),

air_fuels_issued NVARCHAR(50),

aircraft_config NVARCHAR(20),

aircraft_group NVARCHAR(20),

aircraft_type NVARCHAR(20),

unique_carrier NVARCHAR(20),

unique_carrier_name NVARCHAR(200),

region NVARCHAR(20),

year NVARCHAR(10),

quarter NVARCHAR(10)

);

GO
