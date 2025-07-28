-- Ride Sharing Analytics Database Schema Setup
-- This script creates tables and loads sample data for ride-sharing business analysis

-- Create database (uncomment if using PostgreSQL/MySQL)
-- CREATE DATABASE rideshare_analytics;
-- USE rideshare_analytics;

-- =============================================
-- DRIVERS TABLE
-- =============================================
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS trips;
DROP TABLE IF EXISTS drivers;

CREATE TABLE drivers (
    driver_id INTEGER PRIMARY KEY,
    signup_date DATE NOT NULL,
    city VARCHAR(50) NOT NULL,
    vehicle_type VARCHAR(20) NOT NULL,
    driver_rating DECIMAL(3,2),
    total_trips_completed INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================
-- TRIPS TABLE (Main fact table)
-- =============================================
CREATE TABLE trips (
    trip_id INTEGER PRIMARY KEY,
    rider_id INTEGER NOT NULL,
    driver_id INTEGER,
    trip_datetime TIMESTAMP NOT NULL,
    pickup_borough VARCHAR(50),
    dropoff_borough VARCHAR(50),
    pickup_latitude DECIMAL(10,6),
    pickup_longitude DECIMAL(10,6),
    dropoff_latitude DECIMAL(10,6),
    dropoff_longitude DECIMAL(10,6),
    distance_miles DECIMAL(8,2),
    duration_minutes INTEGER,
    fare_amount DECIMAL(10,2),
    surge_multiplier DECIMAL(3,2) DEFAULT 1.0,
    trip_status VARCHAR(20) NOT NULL,
    rider_rating DECIMAL(3,1),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (driver_id) REFERENCES drivers(driver_id)
);

-- =============================================
-- PAYMENTS TABLE
-- =============================================
CREATE TABLE payments (
    payment_id INTEGER PRIMARY KEY,
    trip_id INTEGER NOT NULL,
    rider_id INTEGER NOT NULL,
    driver_id INTEGER NOT NULL,
    payment_method VARCHAR(20) NOT NULL,
    amount_charged DECIMAL(10,2) NOT NULL,
    driver_payout DECIMAL(10,2) NOT NULL,
    platform_fee DECIMAL(10,2) NOT NULL,
    processing_fee DECIMAL(10,2) NOT NULL,
    payment_status VARCHAR(20) NOT NULL,
    payment_timestamp TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (trip_id) REFERENCES trips(trip_id),
    FOREIGN KEY (driver_id) REFERENCES drivers(driver_id)
);

-- =============================================
-- CREATE INDEXES FOR PERFORMANCE
-- =============================================

-- Indexes on drivers table
CREATE INDEX idx_drivers_city ON drivers(city);
CREATE INDEX idx_drivers_status ON drivers(status);
CREATE INDEX idx_drivers_signup_date ON drivers(signup_date);
CREATE INDEX idx_drivers_vehicle_type ON drivers(vehicle_type);

-- Indexes on trips table
CREATE INDEX idx_trips_driver_id ON trips(driver_id);
CREATE INDEX idx_trips_rider_id ON trips(rider_id);
CREATE INDEX idx_trips_datetime ON trips(trip_datetime);
CREATE INDEX idx_trips_status ON trips(trip_status);
CREATE INDEX idx_trips_pickup_borough ON trips(pickup_borough);
CREATE INDEX idx_trips_dropoff_borough ON trips(dropoff_borough);
CREATE INDEX idx_trips_date ON trips(DATE(trip_datetime));

-- Indexes on payments table
CREATE INDEX idx_payments_trip_id ON payments(trip_id);
CREATE INDEX idx_payments_driver_id ON payments(driver_id);
CREATE INDEX idx_payments_payment_method ON payments(payment_method);
CREATE INDEX idx_payments_status ON payments(payment_status);
CREATE INDEX idx_payments_timestamp ON payments(payment_timestamp);

-- =============================================
-- CREATE USEFUL VIEWS
-- =============================================

-- Daily metrics view
CREATE VIEW daily_metrics AS
SELECT 
    DATE(trip_datetime) as trip_date,
    COUNT(*) as total_trips,
    COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
    COUNT(CASE WHEN trip_status LIKE 'cancelled%' THEN 1 END) as cancelled_trips,
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN fare_amount END), 2) as avg_fare,
    ROUND(SUM(CASE WHEN trip_status = 'completed' THEN fare_amount END), 2) as total_revenue,
    COUNT(DISTINCT driver_id) as active_drivers,
    COUNT(DISTINCT rider_id) as active_riders
FROM trips
GROUP BY DATE(trip_datetime);

-- Driver performance view
CREATE VIEW driver_performance AS
SELECT 
    d.driver_id,
    d.city,
    d.vehicle_type,
    d.driver_rating,
    d.signup_date,
    COUNT(t.trip_id) as total_trip_requests,
    COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) as completed_trips,
    ROUND(
        COUNT(CASE WHEN t.trip_status = 'completed' THEN 1 END) * 100.0 / 
        NULLIF(COUNT(t.trip_id), 0), 2
    ) as completion_rate,
    ROUND(AVG(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END), 2) as avg_fare_per_trip,
    ROUND(SUM(CASE WHEN t.trip_status = 'completed' THEN t.fare_amount END), 2) as total_earnings
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
GROUP BY d.driver_id, d.city, d.vehicle_type, d.driver_rating, d.signup_date;

-- Borough demand view
CREATE VIEW borough_demand AS
SELECT 
    pickup_borough,
    DATE(trip_datetime) as trip_date,
    EXTRACT(HOUR FROM trip_datetime) as trip_hour,
    COUNT(*) as trip_requests,
    COUNT(CASE WHEN trip_status = 'completed' THEN 1 END) as completed_trips,
    ROUND(AVG(surge_multiplier), 2) as avg_surge,
    ROUND(AVG(CASE WHEN trip_status = 'completed' THEN fare_amount END), 2) as avg_fare
FROM trips
GROUP BY pickup_borough, DATE(trip_datetime), EXTRACT(HOUR FROM trip_datetime);

-- =============================================
-- LOAD DATA (Modify paths as needed)
-- =============================================

-- For PostgreSQL:
-- COPY drivers FROM '/path/to/drivers.csv' DELIMITER ',' CSV HEADER;
-- COPY trips FROM '/path/to/trips.csv' DELIMITER ',' CSV HEADER;
-- COPY payments FROM '/path/to/payments.csv' DELIMITER ',' CSV HEADER;

-- For MySQL:
-- LOAD DATA INFILE '/path/to/drivers.csv' 
-- INTO TABLE drivers 
-- FIELDS TERMINATED BY ',' 
-- ENCLOSED BY '"' 
-- LINES TERMINATED BY '\n' 
-- IGNORE 1 ROWS;

-- LOAD DATA INFILE '/path/to/trips.csv' 
-- INTO TABLE trips 
-- FIELDS TERMINATED BY ',' 
-- ENCLOSED BY '"' 
-- LINES TERMINATED BY '\n' 
-- IGNORE 1 ROWS;

-- LOAD DATA INFILE '/path/to/payments.csv' 
-- INTO TABLE payments 
-- FIELDS TERMINATED BY ',' 
-- ENCLOSED BY '"' 
-- LINES TERMINATED BY '\n' 
-- IGNORE 1 ROWS;

-- =============================================
-- DATA VALIDATION QUERIES
-- =============================================

-- Check total records loaded
SELECT 'drivers' as table_name, COUNT(*) as record_count FROM drivers
UNION ALL
SELECT 'trips' as table_name, COUNT(*) as record_count FROM trips
UNION ALL
SELECT 'payments' as table_name, COUNT(*) as record_count FROM payments;

-- Check data quality and relationships
SELECT 
    'Trip Status Distribution' as metric,
    trip_status,
    COUNT(*) as count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM trips
GROUP BY trip_status
ORDER BY count DESC;

-- Verify foreign key relationships
SELECT 
    'Drivers without trips' as check_type,
    COUNT(*) as count
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
WHERE t.driver_id IS NULL

UNION ALL

SELECT 
    'Trips without payments' as check_type,
    COUNT(*) as count
FROM trips t
LEFT JOIN payments p ON t.trip_id = p.trip_id
WHERE t.trip_status = 'completed' AND p.trip_id IS NULL;

-- Revenue summary
SELECT 
    'Total Revenue (Completed Trips)' as metric,
    ROUND(SUM(fare_amount), 2) as amount
FROM trips
WHERE trip_status = 'completed'

UNION ALL

SELECT 
    'Total Platform Fees' as metric,
    ROUND(SUM(platform_fee), 2) as amount
FROM payments
WHERE payment_status = 'successful';

SELECT 'Schema setup completed successfully!' as status;