-- Ride Sharing Driver Utilization Analysis
-- SQL queries for driver performance, earnings analysis, and utilization optimization

-- =============================================
-- DRIVER PERFORMANCE METRICS
-- =============================================

-- Overall driver performance scorecard
SELECT 
    d.driver_id,
    d.city,
    d.vehicle_type,
    d.driver_rating,
    DATEDIFF(CURRENT_DATE, d.signup_date) as days_since_signup,
    
    -- Trip metrics
    COUNT(t.trip_id) as total_trip_requests,
    COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) as completed_trips,
    COUNT(CASE WHEN t.trip_status = 'cancelled_driver' THEN 1 END) as driver_cancellations,
    
    -- Performance rates
    ROUND(
        COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 100.0 / 
        NULLIF(COUNT(t.trip_id), 0), 2
    ) as completion_rate,
    
    ROUND(
        COUNT(CASE WHEN t.trip_status = 'cancelled_driver' THEN 1 END) * 100.0 / 
        NULLIF(COUNT(t.trip_id), 0), 2
    ) as cancellation_rate,
    
    -- Financial metrics
    ROUND(SUM(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END), 2) as total_gross_earnings,
    ROUND(AVG(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END), 2) as avg_fare_per_trip,
    
    -- Productivity metrics
    ROUND(
        COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 1.0 / 
        NULLIF(DATEDIFF(CURRENT_DATE, d.signup_date), 0), 2
    ) as trips_per_day_average,
    
    -- Driver tier classification
    CASE 
        WHEN COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) >= 100 
             AND (COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 100.0 / 
                  NULLIF(COUNT(t.trip_id), 0)) >= 85
        THEN 'Top Performer'
        WHEN COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) >= 50 
             AND (COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 100.0 / 
                  NULLIF(COUNT(t.trip_id), 0)) >= 75
        THEN 'Good Performer'
        WHEN COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) >= 20
        THEN 'Average Performer'
        ELSE 'New/Low Activity'
    END as driver_tier
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
GROUP BY d.driver_id, d.city, d.vehicle_type, d.driver_rating, d.signup_date
ORDER BY total_gross_earnings DESC;

-- Driver earnings analysis by vehicle type and city
SELECT 
    d.city,
    d.vehicle_type,
    COUNT(DISTINCT d.driver_id) as driver_count,
    COUNT(t.trip_id) as total_trips_by_segment,
    
    -- Earnings metrics
    ROUND(AVG(
        CASE WHEN t.trip_status = 'completed' 
        THEN t.fare_amount 
        END
    ), 2) as avg_fare_per_trip,
    
    ROUND(SUM(
        CASE WHEN t.trip_status = 'completed' 
        THEN t.fare_amount 
        END
    ) / NULLIF(COUNT(DISTINCT d.driver_id), 0), 2) as avg_total_earnings_per_driver,
    
    -- Utilization metrics
    ROUND(AVG(
        COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 1.0
    ), 2) as avg_completed_trips_per_driver,
    
    ROUND(
        COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 100.0 / 
        NULLIF(COUNT(t.trip_id), 0), 2
    ) as overall_completion_rate,
    
    -- Market demand indicator
    ROUND(
        COUNT(t.trip_id) * 1.0 / NULLIF(COUNT(DISTINCT d.driver_id), 0), 2
    ) as trip_requests_per_driver
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
GROUP BY d.city, d.vehicle_type
HAVING COUNT(DISTINCT d.driver_id) >= 5
ORDER BY d.city, avg_total_earnings_per_driver DESC;

-- =============================================
-- HOURLY UTILIZATION PATTERNS
-- =============================================

-- Driver hourly activity and earnings
WITH driver_hourly_stats AS (
    SELECT 
        t.driver_id,
        EXTRACT(HOUR FROM t.trip_datetime) as hour_of_day,
        COUNT(*) as trip_requests,
        COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) as completed_trips,
        SUM(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END) as hourly_earnings
    FROM trips t
    GROUP BY t.driver_id, EXTRACT(HOUR FROM t.trip_datetime)
)
SELECT 
    hour_of_day,
    COUNT(DISTINCT driver_id) as active_drivers,
    ROUND(AVG(trip_requests), 2) as avg_requests_per_driver,
    ROUND(AVG(completed_trips), 2) as avg_completed_per_driver,
    ROUND(AVG(hourly_earnings), 2) as avg_hourly_earnings,
    
    -- Peak hour identification
    CASE 
        WHEN COUNT(DISTINCT driver_id) >= (
            SELECT AVG(hourly_drivers) * 1.3 FROM (
                SELECT hour_of_day, COUNT(DISTINCT driver_id) as hourly_drivers
                FROM driver_hourly_stats GROUP BY hour_of_day
            ) peak_calc
        ) THEN 'Peak Activity Hour'
        WHEN COUNT(DISTINCT driver_id) <= (
            SELECT AVG(hourly_drivers) * 0.7 FROM (
                SELECT hour_of_day, COUNT(DISTINCT driver_id) as hourly_drivers
                FROM driver_hourly_stats GROUP BY hour_of_day
            ) peak_calc
        ) THEN 'Low Activity Hour'
        ELSE 'Normal Activity'
    END as activity_level,
    
    -- Earnings tier for the hour
    CASE 
        WHEN AVG(hourly_earnings) >= 50 THEN 'High Earning Hour'
        WHEN AVG(hourly_earnings) >= 25 THEN 'Medium Earning Hour'
        WHEN AVG(hourly_earnings) >= 10 THEN 'Low Earning Hour'
        ELSE 'Very Low Earning Hour'
    END as earnings_tier
FROM driver_hourly_stats
WHERE hourly_earnings IS NOT NULL
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- Driver consistency analysis (regular vs occasional drivers)
WITH driver_activity_patterns AS (
    SELECT 
        driver_id,
        COUNT(DISTINCT DATE(trip_datetime)) as active_days,
        COUNT(*) as total_trip_requests,
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
        MIN(DATE(trip_datetime)) as first_trip_date,
        MAX(DATE(trip_datetime)) as last_trip_date,
        DATEDIFF(MAX(DATE(trip_datetime)), MIN(DATE(trip_datetime))) + 1 as date_range_days
    FROM trips
    GROUP BY driver_id
)
SELECT 
    CASE 
        WHEN active_days >= 50 AND (active_days * 1.0 / NULLIF(date_range_days, 0)) >= 0.5 
        THEN 'Highly Active (Regular)'
        WHEN active_days >= 20 AND (active_days * 1.0 / NULLIF(date_range_days, 0)) >= 0.3
        THEN 'Moderately Active'
        WHEN active_days >= 10 
        THEN 'Occasionally Active'
        ELSE 'Low Activity'
    END as driver_activity_type,
    
    COUNT(*) as driver_count,
    ROUND(AVG(active_days), 1) as avg_active_days,
    ROUND(AVG(completed_trips), 1) as avg_completed_trips,
    ROUND(AVG(total_trip_requests), 1) as avg_total_requests,
    ROUND(AVG(completed_trips * 1.0 / NULLIF(total_trip_requests, 0) * 100), 2) as avg_completion_rate,
    ROUND(AVG(active_days * 1.0 / NULLIF(date_range_days, 0) * 100), 2) as avg_activity_consistency_pct
FROM driver_activity_patterns
GROUP BY 
    CASE 
        WHEN active_days >= 50 AND (active_days * 1.0 / NULLIF(date_range_days, 0)) >= 0.5 
        THEN 'Highly Active (Regular)'
        WHEN active_days >= 20 AND (active_days * 1.0 / NULLIF(date_range_days, 0)) >= 0.3
        THEN 'Moderately Active'
        WHEN active_days >= 10 
        THEN 'Occasionally Active'
        ELSE 'Low Activity'
    END
ORDER BY avg_completed_trips DESC;

-- =============================================
-- DRIVER EARNINGS OPTIMIZATION
-- =============================================

-- Peak earnings opportunities by driver location and time
SELECT 
    d.city,
    t.pickup_borough,
    EXTRACT(HOUR FROM t.trip_datetime) as optimal_hour,
    COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) as completed_trips,
    ROUND(AVG(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END), 2) as avg_fare,
    ROUND(SUM(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END), 2) as total_earnings,
    ROUND(AVG(t.surge_multiplier), 2) as avg_surge,
    
    -- Earnings per hour estimate (simplified)
    ROUND(
        SUM(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END) / 
        NULLIF(COUNT(DISTINCT t.driver_id), 0), 2
    ) as earnings_per_driver,
    
    -- Opportunity score
    ROUND(
        (AVG(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END) * 
         COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 
         AVG(t.surge_multiplier)) / 100, 2
    ) as opportunity_score
FROM drivers d
JOIN trips t ON d.driver_id = t.driver_id
WHERE t.trip_status = 'completed'
GROUP BY d.city, t.pickup_borough, EXTRACT(HOUR FROM t.trip_datetime)
HAVING COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) >= 5
ORDER BY opportunity_score DESC
LIMIT 20;

-- Driver churn risk analysis
WITH driver_recent_activity AS (
    SELECT 
        d.driver_id,
        d.signup_date,
        d.city,
        d.vehicle_type,
        d.status,
        MAX(t.trip_datetime) as last_trip_date,
        COUNT(t.trip_id) as total_trips,
        COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) as completed_trips,
        SUM(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END) as total_earnings,
        DATEDIFF(CURRENT_DATE, MAX(t.trip_datetime)) as days_since_last_trip
    FROM drivers d
    LEFT JOIN trips t ON d.driver_id = t.driver_id
    GROUP BY d.driver_id, d.signup_date, d.city, d.vehicle_type, d.status
)
SELECT 
    CASE 
        WHEN days_since_last_trip IS NULL THEN 'Never Active'
        WHEN days_since_last_trip <= 7 THEN 'Active (Last Week)'
        WHEN days_since_last_trip <= 30 THEN 'Recently Active (Last Month)'
        WHEN days_since_last_trip <= 90 THEN 'At Risk (1-3 Months)'
        ELSE 'Churned (3+ Months Inactive)'
    END as activity_status,
    
    COUNT(*) as driver_count,
    ROUND(AVG(total_trips), 1) as avg_lifetime_trips,
    ROUND(AVG(completed_trips), 1) as avg_completed_trips,
    ROUND(AVG(total_earnings), 2) as avg_lifetime_earnings,
    ROUND(AVG(days_since_last_trip), 1) as avg_days_inactive,
    
    -- Churn risk indicators
    ROUND(
        COUNT(CASE WHEN days_since_last_trip BETWEEN 30 AND 90 THEN 1 END) * 100.0 / 
        COUNT(*), 2
    ) as at_risk_percentage
FROM driver_recent_activity
GROUP BY 
    CASE 
        WHEN days_since_last_trip IS NULL THEN 'Never Active'
        WHEN days_since_last_trip <= 7 THEN 'Active (Last Week)'
        WHEN days_since_last_trip <= 30 THEN 'Recently Active (Last Month)'
        WHEN days_since_last_trip <= 90 THEN 'At Risk (1-3 Months)'
        ELSE 'Churned (3+ Months Inactive)'
    END
ORDER BY 
    CASE 
        WHEN activity_status = 'Active (Last Week)' THEN 1
        WHEN activity_status = 'Recently Active (Last Month)' THEN 2
        WHEN activity_status = 'At Risk (1-3 Months)' THEN 3
        WHEN activity_status = 'Churned (3+ Months Inactive)' THEN 4
        ELSE 5
    END;

-- Top performing drivers by efficiency metrics
WITH driver_efficiency AS (
    SELECT 
        d.driver_id,
        d.city,
        d.vehicle_type,
        d.driver_rating,
        COUNT(t.trip_id) as total_requests,
        COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) as completed_trips,
        SUM(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END) as total_earnings,
        
        -- Efficiency metrics
        ROUND(
            COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 100.0 / 
            NULLIF(COUNT(t.trip_id), 0), 2
        ) as completion_rate,
        
        ROUND(
            SUM(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END) / 
            NULLIF(COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END), 0), 2
        ) as avg_fare_per_completed_trip,
        
        ROUND(
            COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 1.0 / 
            NULLIF(COUNT(DISTINCT DATE(t.trip_datetime)), 0), 2
        ) as trips_per_active_day
    FROM drivers d
    JOIN trips t ON d.driver_id = t.driver_id
    GROUP BY d.driver_id, d.city, d.vehicle_type, d.driver_rating
    HAVING COUNT(t.trip_id) >= 20  -- Minimum activity threshold
)
SELECT 
    driver_id,
    city,
    vehicle_type,
    driver_rating,
    total_requests,
    completed_trips,
    total_earnings,
    completion_rate,
    avg_fare_per_completed_trip,
    trips_per_active_day,
    
    -- Composite efficiency score
    ROUND(
        (completion_rate * 0.4) + 
        (LEAST(avg_fare_per_completed_trip * 2, 100) * 0.3) + 
        (LEAST(trips_per_active_day * 10, 100) * 0.3), 2
    ) as efficiency_score,
    
    CASE 
        WHEN ROUND(
            (completion_rate * 0.4) + 
            (LEAST(avg_fare_per_completed_trip * 2, 100) * 0.3) + 
            (LEAST(trips_per_active_day * 10, 100) * 0.3), 2
        ) >= 80 THEN 'Elite Driver'
        WHEN ROUND(
            (completion_rate * 0.4) + 
            (LEAST(avg_fare_per_completed_trip * 2, 100) * 0.3) + 
            (LEAST(trips_per_active_day * 10, 100) * 0.3), 2
        ) >= 65 THEN 'High Performer'
        WHEN ROUND(
            (completion_rate * 0.4) + 
            (LEAST(avg_fare_per_completed_trip * 2, 100) * 0.3) + 
            (LEAST(trips_per_active_day * 10, 100) * 0.3), 2
        ) >= 50 THEN 'Good Performer'
        ELSE 'Needs Improvement'
    END as performance_tier
FROM driver_efficiency
ORDER BY efficiency_score DESC
LIMIT 50;