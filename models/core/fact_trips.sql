{{ config(materialized='table') }}

with green_data as (
    select 
        *,
        'Green' as service_type
    from {{ ref('stg_green_tripdata') }}
),

yellow_data as (
    select
        *,
        cast(null as integer) as trip_type,
        cast(null as numeric) as ehail_fee,
        'Yellow' as service_type
    from {{ ref('stg_yellow_tripdata') }}
),

trips_unioned as (
    select * from green_data
    union all
    select * from yellow_data
)

select
    vendorid,
    service_type,
    pickup_datetime,
    dropoff_datetime,
    pickup_locationid,
    dropoff_locationid,
    passenger_count,
    trip_distance,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    total_amount,
    payment_type,
    congestion_surcharge
from trips_unioned