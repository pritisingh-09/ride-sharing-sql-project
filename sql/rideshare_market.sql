-- Ride Sharing Market Efficiency Analysis
-- SQL queries for demand-supply analysis, fulfillment rates, and market optimization

-- =============================================
-- TRIP FULFILLMENT AND COMPLETION RATES
-- =============================================

-- Overall platform efficiency metrics
SELECT 
    COUNT(*) as total_trip_requests,
    COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
    COUNT(CASE WHEN trip_status = 'cancelled_rider' THEN 1 END) as rider_cancellations,
    COUNT(CASE WHEN trip_status = 'cancelled_driver' THEN 1 END) as driver_cancellations,
    COUNT(CASE WHEN trip_status = 'no_show' THEN 1 END) as no_shows,
    
    -- Fulfillment rate (completed / total requested)
    ROUND(
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as fulfillment_rate_pct,
    
    -- Cancellation breakdown
    ROUND(
        COUNT(CASE WHEN trip_status = 'cancelled_rider' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as rider_cancellation_rate,
    ROUND(
        COUNT(CASE WHEN trip_status = 'cancelled_driver' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as driver_cancellation_rate,
    
    -- Average fare for completed trips
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN fare_amount END), 2) as avg_completed_fare
FROM trips;

-- Hourly demand patterns and fulfillment rates
SELECT 
    EXTRACT(HOUR FROM trip_datetime) as hour_of_day,
    COUNT(*) as trip_requests,
    COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
    COUNT(DISTINCT driver_id) as active_drivers,
    
    -- Fulfillment rate by hour
    ROUND(
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as hourly_fulfillment_rate,
    
    -- Demand per driver ratio
    ROUND(
        COUNT(*) * 1.0 / NULLIF(COUNT(DISTINCT driver_id), 0), 2
    ) as requests_per_driver,
    
    -- Average surge during this hour
    ROUND(AVG(surge_multiplier), 2) as avg_surge_multiplier,
    
    -- Peak hour indicator
    CASE 
        WHEN COUNT(*) >= (SELECT AVG(hourly_requests) * 1.5 FROM (
            SELECT EXTRACT(HOUR FROM trip_datetime) as hour, COUNT(*) as hourly_requests
            FROM trips GROUP BY EXTRACT(HOUR FROM trip_datetime)
        ) avg_calc) THEN 'Peak Hour'
        WHEN COUNT(*) <= (SELECT AVG(hourly_requests) * 0.7 FROM (
            SELECT EXTRACT(HOUR FROM trip_datetime) as hour, COUNT(*) as hourly_requests
            FROM trips GROUP BY EXTRACT(HOUR FROM trip_datetime)
        ) avg_calc) THEN 'Off-Peak'
        ELSE 'Normal'
    END as demand_classification
FROM trips
GROUP BY EXTRACT(HOUR FROM trip_datetime)
ORDER BY hour_of_day;

-- Borough-wise market efficiency
SELECT 
    pickup_borough,
    COUNT(*) as total_requests,
    COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
    COUNT(DISTINCT driver_id) as unique_drivers_served,
    
    -- Market efficiency metrics
    ROUND(
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as completion_rate,
    
    ROUND(AVG(surge_multiplier), 2) as avg_surge_level,
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN fare_amount END), 2) as avg_fare,
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN distance_miles END), 2) as avg_distance,
    
    -- Cancellation analysis
    ROUND(
        COUNT(CASE WHEN trip_status = 'cancelled_driver' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as driver_cancel_rate,
    
    -- Market penetration score
    ROUND(
        (COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) * 
         AVG(CASE WHEN trip_status = 'completed' THEN fare_amount END)) / 1000, 2
    ) as market_value_score
FROM trips
GROUP BY pickup_borough
ORDER BY completion_rate DESC;

-- =============================================
-- SURGE PRICING EFFECTIVENESS
-- =============================================

-- Surge multiplier impact on completion rates
SELECT 
    CASE 
        WHEN surge_multiplier = 1.0 THEN 'No Surge (1.0x)'
        WHEN surge_multiplier <= 1.2 THEN 'Low Surge (1.1-1.2x)'
        WHEN surge_multiplier <= 1.5 THEN 'Medium Surge (1.3-1.5x)'
        ELSE 'High Surge (1.6x+)'
    END as surge_category,
    
    COUNT(*) as total_requests,
    COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
    
    -- Completion rates by surge level
    ROUND(
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as completion_rate,
    
    -- Rider behavior during surge
    ROUND(
        COUNT(CASE WHEN trip_status = 'cancelled_rider' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as rider_cancellation_rate,
    
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN fare_amount END), 2) as avg_fare,
    ROUND(AVG(surge_multiplier), 2) as avg_surge_in_category
FROM trips
GROUP BY 
    CASE 
        WHEN surge_multiplier = 1.0 THEN 'No Surge (1.0x)'
        WHEN surge_multiplier <= 1.2 THEN 'Low Surge (1.1-1.2x)'
        WHEN surge_multiplier <= 1.5 THEN 'Medium Surge (1.3-1.5x)'
        ELSE 'High Surge (1.6x+)'
    END
ORDER BY avg_surge_in_category;

-- Surge effectiveness by time and location
SELECT 
    pickup_borough,
    EXTRACT(HOUR FROM trip_datetime) as hour,
    COUNT(*) as trip_count,
    ROUND(AVG(surge_multiplier), 2) as avg_surge,
    
    -- Before vs after surge comparison
    ROUND(
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as completion_rate,
    
    ROUND(
        COUNT(CASE WHEN trip_status = 'cancelled_rider' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as rider_rejection_rate,
    
    -- Revenue impact
    ROUND(SUM(CASE WHEN trip_status = 'completed' THEN fare_amount END), 2) as total_revenue,
    
    CASE 
        WHEN AVG(surge_multiplier) >= 1.5 THEN 'High Demand Period'
        WHEN AVG(surge_multiplier) >= 1.2 THEN 'Moderate Demand'
        ELSE 'Normal Demand'
    END as demand_intensity
FROM trips
GROUP BY pickup_borough, EXTRACT(HOUR FROM trip_datetime)
HAVING COUNT(*) >= 10
ORDER BY pickup_borough, hour;

-- =============================================
-- WAIT TIME AND ETA ANALYSIS
-- =============================================

-- Estimated wait time patterns (proxy using trip frequency)
WITH trip_intervals AS (
    SELECT 
        pickup_borough,
        trip_datetime,
        LAG(trip_datetime) OVER (
            PARTITION BY pickup_borough 
            ORDER BY trip_datetime
        ) as previous_trip_time,
        EXTRACT(EPOCH FROM (
            trip_datetime - LAG(trip_datetime) OVER (
                PARTITION BY pickup_borough 
                ORDER BY trip_datetime
            )
        )) / 60 as minutes_between_trips
    FROM trips
    WHERE trip_status = 'completed'
)
SELECT 
    pickup_borough,
    COUNT(*) as completed_trips,
    ROUND(AVG(minutes_between_trips), 2) as avg_minutes_between_trips,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY minutes_between_trips), 2) as median_wait_proxy,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY minutes_between_trips), 2) as p95_wait_proxy,
    
    -- Service frequency classification
    CASE 
        WHEN AVG(minutes_between_trips) <= 5 THEN 'High Frequency'
        WHEN AVG(minutes_between_trips) <= 15 THEN 'Medium Frequency'
        ELSE 'Low Frequency'
    END as service_frequency
FROM trip_intervals
WHERE minutes_between_trips IS NOT NULL
    AND minutes_between_trips BETWEEN 0 AND 120  -- Filter outliers
GROUP BY pickup_borough
ORDER BY avg_minutes_between_trips ASC;

-- Distance vs Duration efficiency analysis
SELECT 
    CASE 
        WHEN distance_miles <= 2 THEN 'Short (≤2 mi)'
        WHEN distance_miles <= 5 THEN 'Medium (2-5 mi)'
        WHEN distance_miles <= 10 THEN 'Long (5-10 mi)'
        ELSE 'Very Long (10+ mi)'
    END as distance_category,
    
    COUNT(*) as completed_trips,
    ROUND(AVG(distance_miles), 2) as avg_distance,
    ROUND(AVG(duration_minutes), 2) as avg_duration,
    ROUND(AVG(distance_miles / NULLIF(duration_minutes, 0) * 60), 2) as avg_speed_mph,
    ROUND(AVG(fare_amount), 2) as avg_fare,
    ROUND(AVG(fare_amount / NULLIF(distance_miles, 0)), 2) as fare_per_mile,
    
    -- Efficiency score (distance/time ratio)
    ROUND(AVG(
        CASE 
            WHEN duration_minutes > 0 
            THEN distance_miles / duration_minutes * 60 
            ELSE 0 
        END
    ), 2) as efficiency_mph
FROM trips
WHERE trip_status = 'completed' 
    AND distance_miles > 0 
    AND duration_minutes > 0
    AND duration_minutes <= 120  -- Filter outliers
GROUP BY 
    CASE 
        WHEN distance_miles <= 2 THEN 'Short (≤2 mi)'
        WHEN distance_miles <= 5 THEN 'Medium (2-5 mi)'
        WHEN distance_miles <= 10 THEN 'Long (5-10 mi)'
        ELSE 'Very Long (10+ mi)'
    END
ORDER BY avg_distance;

-- Cross-borough trip patterns (demand corridors)
SELECT 
    pickup_borough,
    dropoff_borough,
    COUNT(*) as trip_volume,
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN distance_miles END), 2) as avg_distance,
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN duration_minutes END), 1) as avg_duration,
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN fare_amount END), 2) as avg_fare,
    
    -- Route efficiency
    ROUND(
        AVG(CASE 
            WHEN trip_status = 'completed' AND duration_minutes > 0 
            THEN distance_miles / duration_minutes * 60 
            ELSE NULL 
        END), 2
    ) as avg_speed_mph,
    
    -- Completion rate for this route
    ROUND(
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as route_completion_rate
FROM trips
WHERE pickup_borough IS NOT NULL AND dropoff_borough IS NOT NULL
GROUP BY pickup_borough, dropoff_borough
HAVING COUNT(*) >= 50
ORDER BY trip_volume DESC
LIMIT 20;