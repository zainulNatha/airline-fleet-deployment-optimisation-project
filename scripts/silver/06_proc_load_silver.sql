USE AirlineRouteAnalysis;
GO

/* ============================================================
   SILVER LOAD PROCEDURE

   Purpose:
   Refresh all Silver tables from the Bronze layer.

   Load strategy:
   Full refresh using TRUNCATE + INSERT.

   Main responsibilities:

   - Clean text
   - Convert data types
   - Handle missing values
   - Standardise airport codes
   - Aggregate T-100 operational records
   - Create controlled aircraft mappings
   - Filter aircraft economics to United domestic operations
   - Convert BTS (000) units into normal units
   - Calculate quarterly aircraft fuel / cost rates
   ============================================================ */

CREATE OR ALTER PROCEDURE silver.load_silver

AS

BEGIN

    SET NOCOUNT ON;


    DECLARE @start_time DATETIME2 = SYSDATETIME();

    DECLARE @end_time DATETIME2;


    BEGIN TRY


        PRINT '========================================';
        PRINT 'Starting Silver Layer Load';
        PRINT '========================================';



        /* ====================================================
           1. UNITED FLEET
           ==================================================== */

        PRINT 'Loading silver.united_fleet...';


        TRUNCATE TABLE silver.united_fleet;


        INSERT INTO silver.united_fleet
        (
            aircraft_type,

            total_aircraft,
            owned_aircraft,
            leased_aircraft,

            seats_min,
            seats_max,

            average_age_years
        )


        SELECT

            /* Standardise aircraft name text */
            TRIM(aircraft_type),


            /* Convert aircraft counts from text into integers */

            TRY_CAST(
                TRIM(total)
                AS INT
            ),


            TRY_CAST(
                TRIM(owned)
                AS INT
            ),


            /* Source uses an em dash where no aircraft
               are leased. */

            CASE

                WHEN TRIM(leased) = N'—'
                    THEN 0

                ELSE TRY_CAST(
                        TRIM(leased)
                        AS INT
                     )

            END,


            /* ------------------------------------------------
               Minimum seat configuration

               Example:

                   167-203 -> 167
                   166     -> 166
               ------------------------------------------------ */

            CASE

                WHEN CHARINDEX(
                        '-',
                        TRIM(seats_in_standard_configuration)
                     ) > 0

                THEN TRY_CAST
                (
                    LEFT
                    (
                        TRIM(seats_in_standard_configuration),

                        CHARINDEX
                        (
                            '-',
                            TRIM(seats_in_standard_configuration)
                        ) - 1
                    )

                    AS INT
                )


                ELSE TRY_CAST
                (
                    TRIM(seats_in_standard_configuration)

                    AS INT
                )

            END,


            /* ------------------------------------------------
               Maximum seat configuration

               Example:

                   167-203 -> 203
                   166     -> 166
               ------------------------------------------------ */

            CASE

                WHEN CHARINDEX(
                        '-',
                        TRIM(seats_in_standard_configuration)
                     ) > 0

                THEN TRY_CAST
                (
                    SUBSTRING
                    (
                        TRIM(seats_in_standard_configuration),

                        CHARINDEX
                        (
                            '-',
                            TRIM(seats_in_standard_configuration)
                        ) + 1,

                        LEN(
                            TRIM(seats_in_standard_configuration)
                        )
                    )

                    AS INT
                )


                ELSE TRY_CAST
                (
                    TRIM(seats_in_standard_configuration)

                    AS INT
                )

            END,


            /* Convert average aircraft age into numeric form */

            TRY_CAST
            (
                TRIM(average_age_years)

                AS DECIMAL(4,1)
            )


        FROM bronze.united_fleet_raw;



        /* ====================================================
           2. BTS AIRCRAFT TYPE REFERENCE
           ==================================================== */

        PRINT 'Loading silver.aircraft_types...';


        TRUNCATE TABLE silver.aircraft_types;


        INSERT INTO silver.aircraft_types
        (
            aircraft_type_id,
            aircraft_group,

            ssd_name,
            manufacturer,

            long_name,
            short_name,

            begin_date,
            end_date
        )


        SELECT

            ac_typeid,

            ac_group,


            TRIM(ssd_name),

            TRIM(manufacturer),

            TRIM(long_name),

            TRIM(short_name),


            /* Convert blank date text into NULL before
               conversion. */

            TRY_CAST
            (
                NULLIF(
                    TRIM(begin_date),
                    ''
                )

                AS DATE
            ),


            TRY_CAST
            (
                NULLIF(
                    TRIM(end_date),
                    ''
                )

                AS DATE
            )


        FROM bronze.aircraft_types_raw;



        /* ====================================================
           3. AIRPORT REFERENCE
           ==================================================== */

        PRINT 'Loading silver.airports...';


        TRUNCATE TABLE silver.airports;


        INSERT INTO silver.airports
        (
            airport_id,

            ident,

            source_iata_code,

            analysis_airport_code,

            airport_name,
            airport_type,

            municipality,

            iso_region,
            iso_country,

            latitude_deg,
            longitude_deg,

            scheduled_service
        )


        SELECT

            TRY_CAST(
                TRIM(id)
                AS INT
            ),


            TRIM(ident),


            /* Preserve the airport reference source value */

            NULLIF(
                TRIM(iata_code),
                ''
            ),


            /* ------------------------------------------------
               Controlled historical/reference reconciliation.

               T-100 2025 uses PBI.

               The airport record identified by KPBI contains
               a different source IATA value.

               Preserve the source value above while assigning
               PBI as the code used for this analysis.
               ------------------------------------------------ */

            CASE

                WHEN TRIM(ident) = 'KPBI'
                    THEN 'PBI'

                ELSE NULLIF(
                        TRIM(iata_code),
                        ''
                     )

            END,


            TRIM(name),

            TRIM(type),


            NULLIF(
                TRIM(municipality),
                ''
            ),


            NULLIF(
                TRIM(iso_region),
                ''
            ),


            NULLIF(
                TRIM(iso_country),
                ''
            ),


            /* Convert coordinates from text into numeric form */

            TRY_CAST
            (
                NULLIF(
                    TRIM(latitude_deg),
                    ''
                )

                AS DECIMAL(10,6)
            ),


            TRY_CAST
            (
                NULLIF(
                    TRIM(longitude_deg),
                    ''
                )

                AS DECIMAL(10,6)
            ),


            NULLIF(
                TRIM(scheduled_service),
                ''
            )


        FROM bronze.airports_raw;



        /* ====================================================
           4. AIRCRAFT RANGE
           ==================================================== */

        PRINT 'Loading silver.aircraft_range...';


        TRUNCATE TABLE silver.aircraft_range;


        INSERT INTO silver.aircraft_range
        (
            aircraft_type,

            range_nmi,
            range_km,

            range_basis,

            source_name,
            source_url
        )


        SELECT

            TRIM(aircraft_type),


            TRY_CAST
            (
                NULLIF(
                    TRIM(range_nmi),
                    ''
                )

                AS DECIMAL(10,2)
            ),


            TRY_CAST
            (
                NULLIF(
                    TRIM(range_km),
                    ''
                )

                AS DECIMAL(10,2)
            ),


            NULLIF(
                TRIM(range_basis),
                ''
            ),


            NULLIF(
                TRIM(source_name),
                ''
            ),


            NULLIF(
                TRIM(source_url),
                ''
            )


        FROM bronze.aircraft_range_raw;



        /* ====================================================
           5. AIRCRAFT MAPPING

           Controlled reference rather than a direct Bronze
           transformation.

           Aircraft code 627 is deliberately marked ambiguous
           because BTS identifies a wider 777-200 family while
           the United fleet source contains separate variants.
           ==================================================== */

        PRINT 'Loading silver.aircraft_mapping...';


        TRUNCATE TABLE silver.aircraft_mapping;


        INSERT INTO silver.aircraft_mapping
        (
            aircraft_type_id,

            standard_aircraft_type,

            united_aircraft_type,

            mapping_status,

            mapping_note
        )


        VALUES

            (
                612,
                '737-700',
                '737-700',
                'Exact',
                NULL
            ),

            (
                614,
                '737-800',
                '737-800',
                'Exact',
                NULL
            ),

            (
                622,
                '757-200',
                '757-200',
                'Exact',
                NULL
            ),

            (
                623,
                '757-300',
                '757-300',
                'Exact',
                NULL
            ),

            (
                624,
                '767-400ER',
                '767-400ER',
                'Exact',
                NULL
            ),

            (
                626,
                '767-300ER',
                '767-300ER',
                'Exact',
                NULL
            ),


            /* BTS does not distinguish the United 777-200
               and 777-200ER variants reliably at this code. */

            (
                627,
                '777-200 family',
                NULL,
                'Ambiguous',
                'BTS groups the 777-200 family while United reports 777-200 and 777-200ER separately.'
            ),


            (
                634,
                '737-900',
                '737-900',
                'Exact',
                NULL
            ),

            (
                637,
                '777-300ER',
                '777-300ER',
                'Exact',
                NULL
            ),

            (
                694,
                'A320-200',
                'A320-200',
                'Exact',
                NULL
            ),

            (
                698,
                'A319-100',
                'A319-100',
                'Exact',
                NULL
            ),

            (
                721,
                'A321neo',
                'A321neo',
                'Exact',
                NULL
            ),

            (
                837,
                '787-10',
                '787-10',
                'Exact',
                NULL
            ),

            (
                838,
                '737 MAX 8',
                '737 MAX 8',
                'Exact',
                NULL
            ),

            (
                839,
                '737 MAX 9',
                '737 MAX 9',
                'Exact',
                NULL
            ),

            (
                887,
                '787-8',
                '787-8',
                'Exact',
                NULL
            ),

            (
                888,
                '737-900ER',
                '737-900ER',
                'Exact',
                NULL
            ),

            (
                889,
                '787-9',
                '787-9',
                'Exact',
                NULL
            );



        /* ====================================================
           6. MONTHLY ROUTE-AIRCRAFT PERFORMANCE

           Grain:

               year
               + month
               + origin
               + destination
               + aircraft type

           Scope:

               United Airlines
               Class F
               2025
           ==================================================== */

        PRINT 'Loading silver.route_aircraft_monthly...';


        TRUNCATE TABLE silver.route_aircraft_monthly;


        INSERT INTO silver.route_aircraft_monthly
        (
            year,
            month,

            month_start_date,

            origin,
            destination,

            aircraft_type_id,

            departures_scheduled,
            departures_performed,

            passengers,
            seats,

            payload,
            freight,
            mail,

            distance_miles,

            air_time_minutes,
            ramp_to_ramp_minutes,

            source_record_count
        )


        SELECT

            year,

            month,


            /* Create a usable monthly date.

               Example:

                   year = 2025
                   month = 7

               becomes:

                   2025-07-01

               This represents the month rather than an
               individual flight date.
            */

            DATEFROMPARTS(
                year,
                month,
                1
            ),


            TRIM(origin),

            TRIM(dest),


            aircraft_type,


            /* Additive operational measures */

            TRY_CAST
            (
                SUM(departures_scheduled)

                AS INT
            ),


            TRY_CAST
            (
                SUM(departures_performed)

                AS INT
            ),


            TRY_CAST
            (
                SUM(passengers)

                AS INT
            ),


            TRY_CAST
            (
                SUM(seats)

                AS INT
            ),


            SUM(payload),

            SUM(freight),

            SUM(mail),


            /* Distance is not additive.

               Multiple source rows for the same route should
               not cause the route distance to be summed.
            */

            MAX(distance),


            SUM(air_time),

            SUM(ramp_to_ramp),


            /* Number of Bronze records combined into the
               resulting Silver row. */

            COUNT(*)


        FROM bronze.t100_segment_raw


        WHERE unique_carrier = 'UA'

          AND class = 'F'

          AND year = 2025


        GROUP BY

            year,

            month,

            TRIM(origin),

            TRIM(dest),

            aircraft_type;



        /* ====================================================
           7. QUARTERLY AIRCRAFT OPERATING COST

           Source:
           BTS Form 41 Schedule P-5.2

           Source grain:

               year
               + quarter
               + carrier
               + region
               + aircraft type

           Silver grain:

               year
               + quarter
               + aircraft type

           Scope:

               United Airlines
               2025
               Domestic operating region
               Specific aircraft types only

           The generic BTS aircraft code 999 is excluded.

           IMPORTANT:

           BTS reports the selected expense, activity and fuel
           fields in thousands.

           Silver converts:

               $000          -> dollars
               000 hours     -> hours
               000 days      -> days
               000 gallons   -> gallons

           Quarterly detail is intentionally preserved.
           ==================================================== */

        PRINT 'Loading silver.aircraft_operating_cost...';


        TRUNCATE TABLE silver.aircraft_operating_cost;


        INSERT INTO silver.aircraft_operating_cost
        (
            year,

            quarter,

            aircraft_type_id,

            fuel_expense_dollars,

            flying_operations_expense_dollars,

            direct_maintenance_expense_dollars,

            flight_maintenance_expense_dollars,

            aircraft_operating_expense_dollars,

            total_air_hours,

            aircraft_days_assigned,

            fuel_issued_gallons,

            fuel_gallons_per_air_hour,

            fuel_cost_per_air_hour,

            operating_cost_per_air_hour,

            maintenance_cost_per_air_hour
        )


        SELECT

            /* ------------------------------------------------
               IDENTIFIERS
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM([year]),
                    ''
                )

                AS INT
            )
                AS year,


            TRY_CAST
            (
                NULLIF(
                    TRIM(quarter),
                    ''
                )

                AS INT
            )
                AS quarter,


            TRY_CAST
            (
                NULLIF(
                    TRIM(aircraft_type),
                    ''
                )

                AS INT
            )
                AS aircraft_type_id,


            /* ------------------------------------------------
               AIRCRAFT FUEL EXPENSE

               Source:
                   $000

               Silver:
                   actual dollars
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM(fuel_fly_ops),
                    ''
                )

                AS DECIMAL(18,4)
            )
            * 1000
                AS fuel_expense_dollars,


            /* ------------------------------------------------
               TOTAL FLYING OPERATIONS EXPENSE
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM(tot_fly_ops),
                    ''
                )

                AS DECIMAL(18,4)
            )
            * 1000
                AS flying_operations_expense_dollars,


            /* ------------------------------------------------
               DIRECT MAINTENANCE EXPENSE
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM(tot_dir_maint),
                    ''
                )

                AS DECIMAL(18,4)
            )
            * 1000
                AS direct_maintenance_expense_dollars,


            /* ------------------------------------------------
               FLIGHT EQUIPMENT MAINTENANCE EXPENSE
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM(tot_flt_maint_memo),
                    ''
                )

                AS DECIMAL(18,4)
            )
            * 1000
                AS flight_maintenance_expense_dollars,


            /* ------------------------------------------------
               TOTAL AIRCRAFT OPERATING EXPENSE
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM(tot_air_op_expenses),
                    ''
                )

                AS DECIMAL(18,4)
            )
            * 1000
                AS aircraft_operating_expense_dollars,


            /* ------------------------------------------------
               AIRBORNE HOURS

               Source:
                   000 hours

               Silver:
                   actual hours
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM(total_air_hours),
                    ''
                )

                AS DECIMAL(18,4)
            )
            * 1000
                AS total_air_hours,


            /* ------------------------------------------------
               AIRCRAFT DAYS ASSIGNED
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM(air_days_assign),
                    ''
                )

                AS DECIMAL(18,4)
            )
            * 1000
                AS aircraft_days_assigned,


            /* ------------------------------------------------
               AIRCRAFT FUEL ISSUED

               Source:
                   000 gallons

               Silver:
                   actual gallons
               ------------------------------------------------ */

            TRY_CAST
            (
                NULLIF(
                    TRIM(air_fuels_issued),
                    ''
                )

                AS DECIMAL(18,4)
            )
            * 1000
                AS fuel_issued_gallons,


            /* ------------------------------------------------
               FUEL GALLONS PER AIRBORNE HOUR

               Formula:

                   fuel issued gallons
                   --------------------
                   total airborne hours
               ------------------------------------------------ */

            (
                TRY_CAST
                (
                    NULLIF(
                        TRIM(air_fuels_issued),
                        ''
                    )

                    AS DECIMAL(18,4)
                )
                * 1000
            )

            /

            NULLIF
            (
                (
                    TRY_CAST
                    (
                        NULLIF(
                            TRIM(total_air_hours),
                            ''
                        )

                        AS DECIMAL(18,4)
                    )
                    * 1000
                ),

                0
            )
                AS fuel_gallons_per_air_hour,


            /* ------------------------------------------------
               FUEL COST PER AIRBORNE HOUR

               Formula:

                   fuel expense dollars
                   --------------------
                   total airborne hours
               ------------------------------------------------ */

            (
                TRY_CAST
                (
                    NULLIF(
                        TRIM(fuel_fly_ops),
                        ''
                    )

                    AS DECIMAL(18,4)
                )
                * 1000
            )

            /

            NULLIF
            (
                (
                    TRY_CAST
                    (
                        NULLIF(
                            TRIM(total_air_hours),
                            ''
                        )

                        AS DECIMAL(18,4)
                    )
                    * 1000
                ),

                0
            )
                AS fuel_cost_per_air_hour,


            /* ------------------------------------------------
               OPERATING COST PER AIRBORNE HOUR
               ------------------------------------------------ */

            (
                TRY_CAST
                (
                    NULLIF(
                        TRIM(tot_air_op_expenses),
                        ''
                    )

                    AS DECIMAL(18,4)
                )
                * 1000
            )

            /

            NULLIF
            (
                (
                    TRY_CAST
                    (
                        NULLIF(
                            TRIM(total_air_hours),
                            ''
                        )

                        AS DECIMAL(18,4)
                    )
                    * 1000
                ),

                0
            )
                AS operating_cost_per_air_hour,


            /* ------------------------------------------------
               MAINTENANCE COST PER AIRBORNE HOUR

               Uses the total flight-equipment maintenance
               measure from P-5.2.
               ------------------------------------------------ */

            (
                TRY_CAST
                (
                    NULLIF(
                        TRIM(tot_flt_maint_memo),
                        ''
                    )

                    AS DECIMAL(18,4)
                )
                * 1000
            )

            /

            NULLIF
            (
                (
                    TRY_CAST
                    (
                        NULLIF(
                            TRIM(total_air_hours),
                            ''
                        )

                        AS DECIMAL(18,4)
                    )
                    * 1000
                ),

                0
            )
                AS maintenance_cost_per_air_hour


        FROM bronze.aircraft_operating_cost_raw


        WHERE TRIM(unique_carrier) = 'UA'


          AND TRY_CAST
          (
              NULLIF(
                  TRIM([year]),
                  ''
              )

              AS INT
          ) = 2025


          AND TRIM(region) = 'D'


          AND TRY_CAST
          (
              NULLIF(
                  TRIM(aircraft_type),
                  ''
              )

              AS INT
          ) <> 999;



        /* ====================================================
           LOAD COMPLETE
           ==================================================== */

        SET @end_time = SYSDATETIME();


        PRINT '========================================';

        PRINT 'Silver Layer Load Completed Successfully';


        PRINT CONCAT
        (
            'Duration: ',

            DATEDIFF
            (
                SECOND,
                @start_time,
                @end_time
            ),

            ' seconds'
        );


        PRINT '========================================';


    END TRY


    BEGIN CATCH


        PRINT '========================================';

        PRINT 'Silver Layer Load Failed';


        PRINT CONCAT
        (
            'Error Number: ',
            ERROR_NUMBER()
        );


        PRINT CONCAT
        (
            'Error Message: ',
            ERROR_MESSAGE()
        );


        PRINT '========================================';


        THROW;


    END CATCH;


END;
GO


/* ============================================================
   EXECUTION

   Uncomment when you want to refresh the complete
   Silver layer.
   ============================================================ */

-- EXEC silver.load_silver;

-- GO
