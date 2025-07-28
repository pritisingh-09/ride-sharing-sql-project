-- Ride Sharing Growth KPIs & Business Intelligence
-- SQL queries for cohort analysis, customer acquisition, retention, and revenue growth

-- =============================================
-- RIDER COHORT ANALYSIS & RETENTION
-- =============================================

-- Monthly rider cohorts and retention rates
WITH rider_first_trip AS (
    SELECT 
        rider_id,
        DATE_TRUNC('month', MIN(trip_datetime)) as cohort_month,
        MIN(trip_datetime) as first_trip_date
    FROM trips
    WHERE trip_status = 'completed'
    GROUP BY rider_id
),
monthly_activity AS (
    SELECT 
        t.rider_id,
        DATE_TRUNC('month', t.trip_datetime) as activity_month,
        COUNT(*) as monthly_trips
    FROM trips t
    WHERE t.trip_status = 'completed'
    GROUP BY t.rider_id, DATE_TRUNC('month', t.trip_datetime)
),
cohort_data AS (
    SELECT 
        rf.cohort_month,
        ma.activity_month,
        (EXTRACT(YEAR FROM ma.activity_month) - EXTRACT(YEAR FROM rf.cohort_month)) * 12 + 
        (EXTRACT(MONTH FROM ma.activity_month) - EXTRACT(MONTH FROM rf.cohort_month)) as period_number,
        COUNT(DISTINCT rf.rider_id) as riders_in_cohort
    FROM rider_first_trip rf
    LEFT JOIN monthly_activity ma ON rf.rider_id = ma.rider_id
    WHERE ma.activity_month >= rf.cohort_month
    GROUP BY rf.cohort_month, ma.activity_month
)
SELECT 
    cohort_month,
    COUNT(DISTINCT CASE WHEN period_number = 0 THEN riders_in_cohort END) as cohort_size,
    
    -- Retention rates by month
    ROUND(
        COUNT(DISTINCT CASE WHEN period_number = 1 THEN riders_in_cohort END) * 100.0 / 
        NULLIF(COUNT(DISTINCT CASE WHEN period_number = 0 THEN riders_in_cohort END), 0), 2
    ) as month_1_retention,
    
    ROUND(
        COUNT(DISTINCT CASE WHEN period_number = 2 THEN riders_in_cohort END) * 100.0 / 
        NULLIF(COUNT(DISTINCT CASE WHEN period_number = 0 THEN riders_in_cohort END), 0), 2
    ) as month_2_retention,
    
    ROUND(
        COUNT(DISTINCT CASE WHEN period_number = 3 THEN riders_in_cohort END) * 100.0 / 
        NULLIF(COUNT(DISTINCT CASE WHEN period_number = 0 THEN riders_in_cohort END), 0), 2
    ) as month_3_retention,
    
    ROUND(
        COUNT(DISTINCT CASE WHEN period_number = 6 THEN riders_in_cohort END) * 100.0 / 
        NULLIF(COUNT(DISTINCT CASE WHEN period_number = 0 THEN riders_in_cohort END), 0), 2
    ) as month_6_retention
FROM cohort_data
GROUP BY cohort_month
HAVING COUNT(DISTINCT CASE WHEN period_number = 0 THEN riders_in_cohort END) >= 50
ORDER BY cohort_month;

-- Customer Lifetime Value (CLV) analysis
WITH rider_metrics AS (
    SELECT 
        rider_id,
        MIN(trip_datetime) as first_trip_date,
        MAX(trip_datetime) as last_trip_date,
        COUNT(*) as total_trips,
        SUM(fare_amount) as total_spent,
        AVG(fare_amount) as avg_fare_per_trip,
        DATEDIFF(MAX(trip_datetime), MIN(trip_datetime)) + 1 as customer_lifespan_days
    FROM trips
    WHERE trip_status = 'completed'
    GROUP BY rider_id
)
SELECT 
    CASE 
        WHEN total_trips = 1 THEN 'One-time User'
        WHEN total_trips BETWEEN 2 AND 5 THEN 'Occasional User (2-5 trips)'
        WHEN total_trips BETWEEN 6 AND 20 THEN 'Regular User (6-20 trips)'
        WHEN total_trips BETWEEN 21 AND 50 THEN 'Frequent User (21-50 trips)'
        ELSE 'Power User (50+ trips)'
    END as user_segment,
    
    COUNT(*) as riders_count,
    ROUND(AVG(total_trips), 1) as avg_trips_per_rider,
    ROUND(AVG(total_spent), 2) as avg_total_spent,
    ROUND(AVG(avg_fare_per_trip), 2) as avg_fare_per_trip,
    ROUND(AVG(customer_lifespan_days), 1) as avg_lifespan_days,
    
    -- CLV calculation
    ROUND(
        AVG(total_spent) * 
        (AVG(customer_lifespan_days) / 30.0), 2  -- Monthly CLV estimate
    ) as estimated_monthly_clv,
    
    -- Revenue contribution
    ROUND(
        SUM(total_spent) * 100.0 / 
        SUM(SUM(total_spent)) OVER(), 2
    ) as revenue_contribution_pct
FROM rider_metrics
GROUP BY 
    CASE 
        WHEN total_trips = 1 THEN 'One-time User'
        WHEN total_trips BETWEEN 2 AND 5 THEN 'Occasional User (2-5 trips)'
        WHEN total_trips BETWEEN 6 AND 20 THEN 'Regular User (6-20 trips)'
        WHEN total_trips BETWEEN 21 AND 50 THEN 'Frequent User (21-50 trips)'
        ELSE 'Power User (50+ trips)'
    END
ORDER BY avg_total_spent DESC;

-- =============================================
-- ACQUISITION & GROWTH METRICS
-- =============================================

-- Monthly acquisition and growth trends
WITH monthly_metrics AS (
    SELECT 
        DATE_TRUNC('month', trip_datetime) as month,
        COUNT(DISTINCT rider_id) as active_riders,
        COUNT(DISTINCT driver_id) as active_drivers,
        COUNT(*) as total_trip_requests,
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
        SUM(CASE WHEN trip_status = 'completed' THEN fare_amount END) as total_revenue
    FROM trips
    GROUP BY DATE_TRUNC('month', trip_datetime)
),
new_riders_monthly AS (
    SELECT 
        DATE_TRUNC('month', MIN(trip_datetime)) as acquisition_month,
        COUNT(DISTINCT rider_id) as new_riders
    FROM trips
    WHERE trip_status = 'completed'
    GROUP BY DATE_TRUNC('month', MIN(trip_datetime))
),
new_drivers_monthly AS (
    SELECT 
        DATE_TRUNC('month', d.signup_date) as signup_month,
        COUNT(*) as new_drivers
    FROM drivers d
    GROUP BY DATE_TRUNC('month', d.signup_date)
)
SELECT 
    mm.month,
    mm.active_riders,
    mm.active_drivers,
    COALESCE(nr.new_riders, 0) as new_riders_acquired,
    COALESCE(nd.new_drivers, 0) as new_drivers_onboarded,
    mm.completed_trips,
    mm.total_revenue,
    
    -- Growth rates (month-over-month)
    ROUND(
        (mm.active_riders - LAG(mm.active_riders) OVER (ORDER BY mm.month)) * 100.0 / 
        NULLIF(LAG(mm.active_riders) OVER (ORDER BY mm.month), 0), 2
    ) as rider_growth_rate_mom,
    
    ROUND(
        (mm.total_revenue - LAG(mm.total_revenue) OVER (ORDER BY mm.month)) * 100.0 / 
        NULLIF(LAG(mm.total_revenue) OVER (ORDER BY mm.month), 0), 2
    ) as revenue_growth_rate_mom,
    
    -- Efficiency metrics
    ROUND(mm.total_revenue / NULLIF(mm.completed_trips, 0), 2) as revenue_per_trip,
    ROUND(mm.completed_trips * 1.0 / NULLIF(mm.active_drivers, 0), 2) as trips_per_driver
FROM monthly_metrics mm
LEFT JOIN new_riders_monthly nr ON mm.month = nr.acquisition_month
LEFT JOIN new_drivers_monthly nd ON mm.month = nd.signup_month
ORDER BY mm.month;

-- =============================================
-- PAYMENT SUCCESS & REVENUE OPTIMIZATION
-- =============================================

-- Payment method performance and revenue impact
SELECT 
    p.payment_method,
    COUNT(*) as total_payments,
    COUNT(CASE WHEN p.payment_status = 'successful' THEN 1 END) as successful_payments,
    COUNT(CASE WHEN p.payment_status = 'failed' THEN 1 END) as failed_payments,
    
    -- Success rates
    ROUND(
        COUNT(CASE WHEN p.payment_status = 'successful' THEN 1 END) * 100.0 / COUNT(*), 2
    ) as payment_success_rate,
    
    -- Financial impact
    ROUND(SUM(CASE WHEN p.payment_status = 'successful' THEN p.amount_charged END), 2) as total_revenue,
    ROUND(SUM(CASE WHEN p.payment_status = 'successful' THEN p.driver_payout END), 2) as total_driver_payout,
    ROUND(SUM(CASE WHEN p.payment_status = 'successful' THEN p.platform_fee END), 2) as total_platform_fees,
    ROUND(SUM(CASE WHEN p.payment_status = 'successful' THEN p.processing_fee END), 2) as total_processing_fees,
    
    -- Average transaction values
    ROUND(AVG(CASE WHEN p.payment_status = 'successful' THEN p.amount_charged END), 2) as avg_transaction_value,
    
    -- Market share
    ROUND(
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2
    ) as payment_method_market_share
FROM payments p
GROUP BY p.payment_method
ORDER BY total_revenue DESC;

-- Revenue breakdown and margin analysis
WITH revenue_analysis AS (
    SELECT 
        DATE_TRUNC('month', p.payment_timestamp) as month,
        SUM(CASE WHEN p.payment_status = 'successful' THEN p.amount_charged END) as gross_revenue,
        SUM(CASE WHEN p.payment_status = 'successful' THEN p.driver_payout END) as driver_payouts,
        SUM(CASE WHEN p.payment_status = 'successful' THEN p.platform_fee END) as platform_fees,
        SUM(CASE WHEN p.payment_status = 'successful' THEN p.processing_fee END) as processing_fees,
        COUNT(CASE WHEN p.payment_status = 'successful' THEN 1 END) as successful_transactions
    FROM payments p
    GROUP BY DATE_TRUNC('month', p.payment_timestamp)
)
SELECT 
    month,
    gross_revenue,
    driver_payouts,
    platform_fees,
    processing_fees,
    successful_transactions,
    
    -- Net revenue (platform fees - processing fees)
    ROUND(platform_fees - processing_fees, 2) as net_platform_revenue,
    
    -- Margin calculations
    ROUND(driver_payouts * 100.0 / NULLIF(gross_revenue, 0), 2) as driver_payout_percentage,
    ROUND(platform_fees * 100.0 / NULLIF(gross_revenue, 0), 2) as platform_fee_percentage,
    ROUND((platform_fees - processing_fees) * 100.0 / NULLIF(gross_revenue, 0), 2) as net_margin_percentage,
    
    -- Per-transaction metrics
    ROUND(gross_revenue / NULLIF(successful_transactions, 0), 2) as revenue_per_transaction,
    ROUND((platform_fees - processing_fees) / NULLIF(successful_transactions, 0), 2) as profit_per_transaction
FROM revenue_analysis
ORDER BY month;

-- =============================================
-- MARKET EXPANSION & OPPORTUNITY ANALYSIS
-- =============================================

-- Borough-level market penetration and growth opportunity
WITH borough_metrics AS (
    SELECT 
        pickup_borough,
        COUNT(DISTINCT rider_id) as unique_riders,
        COUNT(*) as total_trip_requests,
        COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
        SUM(CASE WHEN trip_status = 'completed' THEN fare_amount END) as total_revenue,
        COUNT(DISTINCT driver_id) as unique_drivers_served,
        
        -- Market efficiency
        ROUND(
            COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) * 100.0 / COUNT(*), 2
        ) as fulfillment_rate,
        ROUND(AVG(surge_multiplier), 2) as avg_surge_level
    FROM trips
    WHERE pickup_borough IS NOT NULL
    GROUP BY pickup_borough
)
SELECT 
    pickup_borough,
    unique_riders,
    total_trip_requests,
    completed_trips,
    total_revenue,
    unique_drivers_served,
    fulfillment_rate,
    avg_surge_level,
    
    -- Market size indicators
    ROUND(total_revenue / NULLIF(unique_riders, 0), 2) as revenue_per_rider,
    ROUND(completed_trips * 1.0 / NULLIF(unique_riders, 0), 2) as trips_per_rider,
    ROUND(total_trip_requests * 1.0 / NULLIF(unique_drivers_served, 0), 2) as demand_per_driver,
    
    -- Growth opportunity score
    ROUND(
        (total_revenue / 1000) * 0.4 + 
        (fulfillment_rate / 100) * 0.3 + 
        (avg_surge_level - 1) * 100 * 0.3, 2
    ) as market_opportunity_score,
    
    CASE 
        WHEN ROUND(
            (total_revenue / 1000) * 0.4 + 
            (fulfillment_rate / 100) * 0.3 + 
            (avg_surge_level - 1) * 100 * 0.3, 2
        ) >= 50 THEN 'High Growth Potential'
        WHEN ROUND(
            (total_revenue / 1000) * 0.4 + 
            (fulfillment_rate / 100) * 0.3 + 
            (avg_surge_level - 1) * 100 * 0.3, 2
        ) >= 25 THEN 'Moderate Growth Potential'
        ELSE 'Saturated/Low Growth'
    END as market_classification
FROM borough_metrics
ORDER BY market_opportunity_score DESC;

-- Churn prediction indicators
WITH rider_behavior AS (
    SELECT 
        rider_id,
        COUNT(*) as total_trips,
        MAX(trip_datetime) as last_trip_date,
        MIN(trip_datetime) as first_trip_date,
        SUM(fare_amount) as total_spent,
        AVG(fare_amount) as avg_fare,
        DATEDIFF(CURRENT_DATE, MAX(trip_datetime)) as days_since_last_trip,
        
        -- Behavioral patterns
        COUNT(CASE WHEN trip_status = 'cancelled_rider' THEN 1 END) as rider_cancellations,
        AVG(rider_rating) as avg_rating_given
    FROM trips
    GROUP BY rider_id
)
SELECT 
    CASE 
        WHEN days_since_last_trip <= 7 THEN 'Active (Last Week)'
        WHEN days_since_last_trip <= 30 THEN 'Recent (Last Month)'
        WHEN days_since_last_trip <= 90 THEN 'At Risk (1-3 Months)'
        ELSE 'Churned (3+ Months)'
    END as rider_status,
    
    COUNT(*) as rider_count,
    ROUND(AVG(total_trips), 1) as avg_lifetime_trips,
    ROUND(AVG(total_spent), 2) as avg_lifetime_value,
    ROUND(AVG(days_since_last_trip), 1) as avg_days_inactive,
    ROUND(AVG(rider_cancellations * 100.0 / NULLIF(total_trips, 0)), 2) as avg_cancellation_rate,
    
    -- Churn risk score
    ROUND(
        CASE 
            WHEN days_since_last_trip <= 7 THEN 0
            WHEN days_since_last_trip <= 30 THEN 25
            WHEN days_since_last_trip <= 90 THEN 75
            ELSE 100
        END, 2
    ) as churn_risk_score
FROM rider_behavior
GROUP BY 
    CASE 
        WHEN days_since_last_trip <= 7 THEN 'Active (Last Week)'
        WHEN days_since_last_trip <= 30 THEN 'Recent (Last Month)'
        WHEN days_since_last_trip <= 90 THEN 'At Risk (1-3 Months)'
        ELSE 'Churned (3+ Months)'
    END
ORDER BY churn_risk_score;