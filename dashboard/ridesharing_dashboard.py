import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import numpy as np
from datetime import datetime, timedelta

# Page configuration
st.set_page_config(
    page_title="Ride Sharing Analytics Dashboard",
    page_icon="🚗",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS
st.markdown("""
<style>
    .main-header {
        font-size: 3rem;
        color: #1f77b4;
        text-align: center;
        margin-bottom: 2rem;
    }
    .metric-card {
        background-color: #f0f2f6;
        padding: 1rem;
        border-radius: 0.5rem;
        border-left: 5px solid #1f77b4;
    }
    .insight-box {
        background-color: #e8f4f8;
        padding: 1rem;
        border-radius: 0.5rem;
        margin: 1rem 0;
    }
    .kpi-positive {
        color: #28a745;
        font-weight: bold;
    }
    .kpi-negative {
        color: #dc3545;
        font-weight: bold;
    }
</style>
""", unsafe_allow_html=True)

# Load data
@st.cache_data
def load_data():
    try:
        drivers = pd.read_csv('data/drivers.csv')
        trips = pd.read_csv('data/trips.csv')
        payments = pd.read_csv('data/payments.csv')

        # Data preprocessing
        trips['trip_datetime'] = pd.to_datetime(trips['trip_datetime'])
        trips['hour'] = trips['trip_datetime'].dt.hour
        trips['day_of_week'] = trips['trip_datetime'].dt.day_name()
        trips['month'] = trips['trip_datetime'].dt.month_name()
        payments['payment_timestamp'] = pd.to_datetime(payments['payment_timestamp'])

        return drivers, trips, payments
    except FileNotFoundError:
        st.error("Data files not found. Please ensure CSV files are in the same directory.")
        return None, None, None
    except Exception as e:
        st.error(f"Error loading data: {str(e)}")
        return None, None, None

# Main title
st.markdown('<h1 class="main-header"> Ride Sharing Analytics Dashboard</h1>', unsafe_allow_html=True)


drivers, trips, payments = load_data()

if drivers is None or trips is None or payments is None:
    st.stop()

# Sidebar filters
st.sidebar.header("🎛️ Filter Controls")

selected_pickup = st.sidebar.multiselect(
    "Select Pickup Boroughs",
    options=sorted(trips['pickup_borough'].dropna().unique()),
    default=sorted(trips['pickup_borough'].dropna().unique())
)

selected_dropoff = st.sidebar.multiselect(
    "Select Dropoff Boroughs",
    options=sorted(trips['dropoff_borough'].dropna().unique()),
    default=sorted(trips['dropoff_borough'].dropna().unique())
)

selected_vehicle_types = st.sidebar.multiselect(
    "Select Vehicle Types",
    options=sorted(drivers['vehicle_type'].unique()),
    default=sorted(drivers['vehicle_type'].unique())
)

date_range = st.sidebar.date_input(
    "Select Date Range",
    value=(trips['trip_datetime'].min().date(), trips['trip_datetime'].max().date()),
    min_value=trips['trip_datetime'].min().date(),
    max_value=trips['trip_datetime'].max().date()
)

# Filter data
filtered_trips = trips[
    (trips['pickup_borough'].isin(selected_pickup)) &
    (trips['dropoff_borough'].isin(selected_dropoff)) &
    (trips['trip_datetime'].dt.date >= date_range[0]) &
    (trips['trip_datetime'].dt.date <= date_range[1])
]

# Merge with drivers to get vehicle type info
filtered_trips_with_drivers = filtered_trips.merge(
    drivers[['driver_id', 'vehicle_type']], 
    on='driver_id', 
    how='left'
)

# Apply vehicle type filter after merge
filtered_trips_with_drivers = filtered_trips_with_drivers[
    filtered_trips_with_drivers['vehicle_type'].isin(selected_vehicle_types)
]

filtered_drivers = drivers[drivers['driver_id'].isin(filtered_trips['driver_id'])]
filtered_payments = payments[payments['trip_id'].isin(filtered_trips['trip_id'])]

# Key Metrics Row
st.header("📊 Platform Performance KPIs")
col1, col2, col3, col4, col5 = st.columns(5)

with col1:
    st.markdown('<div class="metric-card">', unsafe_allow_html=True)
    total_trips = len(filtered_trips)
    st.metric("Total Trips", f"{total_trips:,}")
    st.markdown('</div>', unsafe_allow_html=True)

with col2:
    st.markdown('<div class="metric-card">', unsafe_allow_html=True)
    completion_rate = (len(filtered_trips[filtered_trips['trip_status'] == 'completed']) / len(filtered_trips)) * 100
    st.metric("Completion Rate", f"{completion_rate:.1f}%")
    st.markdown('</div>', unsafe_allow_html=True)

with col3:
    st.markdown('<div class="metric-card">', unsafe_allow_html=True)
    avg_fare = filtered_trips[filtered_trips['trip_status'] == 'completed']['fare_amount'].mean()
    st.metric("Avg Fare", f"${avg_fare:.2f}")
    st.markdown('</div>', unsafe_allow_html=True)

with col4:
    st.markdown('<div class="metric-card">', unsafe_allow_html=True)
    total_revenue = filtered_payments[filtered_payments['payment_status'] == 'successful']['amount_charged'].sum()
    st.metric("Total Revenue", f"${total_revenue:,.0f}")
    st.markdown('</div>', unsafe_allow_html=True)

with col5:
    st.markdown('<div class="metric-card">', unsafe_allow_html=True)
    active_drivers = len(filtered_drivers[filtered_drivers['status'] == 'Active'])
    st.metric("Active Drivers", active_drivers)
    st.markdown('</div>', unsafe_allow_html=True)

# Main analysis tabs
tab1, tab2, tab3, tab4 = st.tabs(["🏙️ Market Analysis", "🚗 Driver Performance", "💰 Financial Insights", "⏰ Demand Patterns"])

with tab1:
    st.subheader("Market Efficiency Analysis")

    col1, col2 = st.columns(2)

    with col1:
        # Trip completion by pickup borough
        borough_completion = filtered_trips.groupby('pickup_borough').agg({
            'trip_id': 'count',
            'trip_status': lambda x: (x == 'completed').sum()
        }).reset_index()
        borough_completion.columns = ['pickup_borough', 'total_trips', 'completed_trips']
        borough_completion['completion_rate'] = (borough_completion['completed_trips'] / borough_completion['total_trips']) * 100

        fig_city = px.bar(
            borough_completion,
            x='pickup_borough',
            y='completion_rate',
            title="Trip Completion Rate by Pickup Borough",
            color='completion_rate',
            color_continuous_scale='viridis',
            text='completion_rate'
        )
        fig_city.update_traces(texttemplate='%{text:.1f}%', textposition='outside')
        fig_city.update_layout(showlegend=False)
        st.plotly_chart(fig_city, use_container_width=True)

    with col2:
        # Vehicle type distribution (from merged data)
        vehicle_dist = filtered_trips_with_drivers['vehicle_type'].value_counts()

        fig_vehicle = px.pie(
            values=vehicle_dist.values,
            names=vehicle_dist.index,
            title="Trip Distribution by Vehicle Type",
            color_discrete_sequence=px.colors.qualitative.Set3
        )
        st.plotly_chart(fig_vehicle, use_container_width=True)

    # Cancellation analysis
    st.subheader("Cancellation Pattern Analysis")
    col1, col2 = st.columns(2)

    with col1:
        # Cancellation reasons
        cancellation_data = filtered_trips[filtered_trips['trip_status'] != 'completed']['trip_status'].value_counts()

        fig_cancel = px.bar(
            x=cancellation_data.index,
            y=cancellation_data.values,
            title="Trip Cancellation Breakdown",
            color=cancellation_data.values,
            color_continuous_scale='reds'
        )
        fig_cancel.update_layout(showlegend=False)
        st.plotly_chart(fig_cancel, use_container_width=True)

    with col2:
        # Surge impact on completion
        surge_completion = filtered_trips.groupby('surge_multiplier').agg({
            'trip_id': 'count',
            'trip_status': lambda x: (x == 'completed').sum()
        }).reset_index()
        surge_completion.columns = ['surge_multiplier', 'total_trips', 'completed_trips']
        surge_completion['completion_rate'] = (surge_completion['completed_trips'] / surge_completion['total_trips']) * 100

        fig_surge = px.scatter(
            surge_completion,
            x='surge_multiplier',
            y='completion_rate',
            size='total_trips',
            title="Completion Rate vs Surge Pricing",
            color='completion_rate',
            color_continuous_scale='plasma'
        )
        st.plotly_chart(fig_surge, use_container_width=True)

with tab2:
    st.subheader("Driver Performance & Utilization")

    col1, col2 = st.columns(2)

    with col1:
        # Driver ratings distribution
        driver_ratings = filtered_drivers['driver_rating'].dropna()

        fig_ratings = px.histogram(
            x=driver_ratings,
            nbins=20,
            title="Driver Rating Distribution",
            color_discrete_sequence=['#1f77b4']
        )
        fig_ratings.update_layout(
            xaxis_title="Rating",
            yaxis_title="Number of Drivers",
            showlegend=False
        )
        st.plotly_chart(fig_ratings, use_container_width=True)

    with col2:
        # Trips by driver experience (using total_trips_completed as proxy)
        experience_trips = filtered_drivers.groupby('total_trips_completed')['driver_rating'].mean().reset_index()

        fig_exp = px.scatter(
            experience_trips,
            x='total_trips_completed',
            y='driver_rating',
            title="Driver Rating vs Trip Experience",
            labels={'total_trips_completed': 'Total Trips Completed', 'driver_rating': 'Average Rating'}
        )
        st.plotly_chart(fig_exp, use_container_width=True)

    # Driver utilization analysis
    st.subheader("Driver Utilization Metrics")

    # Calculate key driver metrics
    driver_metrics = filtered_trips_with_drivers[filtered_trips_with_drivers['trip_status'] == 'completed'].groupby('driver_id').agg({
        'trip_id': 'count',
        'fare_amount': 'sum',
        'distance_miles': 'sum',
        'duration_minutes': 'sum',
        'rider_rating': 'mean'
    }).reset_index()
    driver_metrics.columns = ['driver_id', 'trips_completed', 'total_earnings', 'total_distance', 'total_time', 'avg_trip_rating']

    # Merge with driver details
    driver_metrics = driver_metrics.merge(
        drivers[['driver_id', 'vehicle_type', 'driver_rating']],
        on='driver_id',
        how='left'
    )

    # Driver efficiency metrics
    driver_metrics['earnings_per_trip'] = (driver_metrics['total_earnings'] / driver_metrics['trips_completed']).round(2)
    driver_metrics['earnings_per_hour'] = (driver_metrics['total_earnings'] / (driver_metrics['total_time'] / 60)).round(2)

    col1, col2 = st.columns(2)

    with col1:
        # Top earning drivers
        top_earners = driver_metrics.nlargest(15, 'total_earnings')

        fig_earners = px.bar(
            top_earners,
            x='driver_id',
            y='total_earnings',
            title="Top 15 Earning Drivers",
            color='earnings_per_hour',
            hover_data=['vehicle_type', 'driver_rating'],
            color_continuous_scale='greens'
        )
        fig_earners.update_layout(xaxis_tickangle=45)
        st.plotly_chart(fig_earners, use_container_width=True)

    with col2:
        # Efficiency analysis
        efficiency_data = driver_metrics[driver_metrics['trips_completed'] >= 5]  # Min 5 trips

        fig_efficiency = px.scatter(
            efficiency_data,
            x='earnings_per_trip',
            y='earnings_per_hour',
            title="Driver Efficiency Analysis",
            color='avg_trip_rating',
            size='trips_completed',
            hover_data=['vehicle_type'],
            color_continuous_scale='viridis'
        )
        st.plotly_chart(fig_efficiency, use_container_width=True)

with tab3:
    st.subheader("Financial Performance Analysis")

    col1, col2 = st.columns(2)

    with col1:
        # Revenue by payment method
        payment_revenue = filtered_payments.groupby('payment_method')['amount_charged'].sum().reset_index()
        payment_revenue = payment_revenue.sort_values('amount_charged', ascending=False)

        fig_payment = px.bar(
            payment_revenue,
            x='payment_method',
            y='amount_charged',
            title="Revenue by Payment Method",
            color='amount_charged',
            color_continuous_scale='blues',
            text='amount_charged'
        )
        fig_payment.update_traces(texttemplate='$%{text:,.0f}', textposition='outside')
        st.plotly_chart(fig_payment, use_container_width=True)

    with col2:
        # Payment success rates
        payment_success = filtered_payments.groupby('payment_method').agg({
            'payment_id': 'count',
            'payment_status': lambda x: (x == 'successful').sum()
        }).reset_index()
        payment_success.columns = ['payment_method', 'total_payments', 'successful_payments']
        payment_success['success_rate'] = (payment_success['successful_payments'] / payment_success['total_payments']) * 100

        fig_success = px.bar(
            payment_success,
            x='payment_method',
            y='success_rate',
            title="Payment Success Rate by Method",
            color='success_rate',
            color_continuous_scale='greens',
            text='success_rate'
        )
        fig_success.update_traces(texttemplate='%{text:.1f}%', textposition='outside')
        st.plotly_chart(fig_success, use_container_width=True)

    # Financial KPIs
    st.subheader("Revenue Analytics")

    col1, col2 = st.columns(2)

    with col1:
        # Monthly revenue trend
        filtered_trips['month_year'] = filtered_trips['trip_datetime'].dt.to_period('M').astype(str)
        monthly_revenue = filtered_trips[filtered_trips['trip_status'] == 'completed'].groupby('month_year')['fare_amount'].sum().reset_index()

        fig_monthly = px.line(
            monthly_revenue,
            x='month_year',
            y='fare_amount',
            title="Monthly Revenue Trend",
            markers=True
        )
        fig_monthly.update_traces(line_color='#2ca02c', marker_size=8)
        fig_monthly.update_layout(xaxis_tickangle=45)
        st.plotly_chart(fig_monthly, use_container_width=True)

    with col2:
        # Revenue by vehicle type
        vehicle_revenue = filtered_trips_with_drivers[filtered_trips_with_drivers['trip_status'] == 'completed'].groupby('vehicle_type')['fare_amount'].sum().reset_index()

        fig_vehicle_rev = px.pie(
            vehicle_revenue,
            values='fare_amount',
            names='vehicle_type',
            title="Revenue Distribution by Vehicle Type",
            color_discrete_sequence=px.colors.qualitative.Pastel
        )
        st.plotly_chart(fig_vehicle_rev, use_container_width=True)

with tab4:
    st.subheader("Demand Pattern Analysis")

    col1, col2 = st.columns(2)

    with col1:
        # Hourly demand pattern
        hourly_demand = filtered_trips.groupby('hour').size().reset_index(name='trip_count')

        fig_hourly = px.line(
            hourly_demand,
            x='hour',
            y='trip_count',
            title="Trip Demand by Hour of Day",
            markers=True
        )
        fig_hourly.update_traces(line_color='#ff7f0e', marker_size=8)
        fig_hourly.update_layout(xaxis_title="Hour of Day", yaxis_title="Number of Trips")
        st.plotly_chart(fig_hourly, use_container_width=True)

    with col2:
        # Day of week analysis
        day_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        daily_demand = filtered_trips.groupby('day_of_week').size().reindex(day_order).reset_index(name='trip_count')

        fig_daily = px.bar(
            daily_demand,
            x='day_of_week',
            y='trip_count',
            title="Trip Demand by Day of Week",
            color='trip_count',
            color_continuous_scale='viridis'
        )
        fig_daily.update_layout(xaxis_tickangle=45)
        st.plotly_chart(fig_daily, use_container_width=True)

    # Surge pricing analysis
    st.subheader("Dynamic Pricing Impact")

    col1, col2 = st.columns(2)

    with col1:
        # Surge distribution
        surge_dist = filtered_trips['surge_multiplier'].value_counts().sort_index()

        fig_surge_dist = px.bar(
            x=surge_dist.index.astype(str),
            y=surge_dist.values,
            title="Distribution of Surge Multipliers",
            color=surge_dist.values,
            color_continuous_scale='reds'
        )
        fig_surge_dist.update_layout(showlegend=False, xaxis_title="Surge Multiplier", yaxis_title="Number of Trips")
        st.plotly_chart(fig_surge_dist, use_container_width=True)

    with col2:
        # Average fare by surge
        surge_fare = filtered_trips[filtered_trips['trip_status'] == 'completed'].groupby('surge_multiplier')['fare_amount'].mean().reset_index()

        fig_surge_fare = px.scatter(
            surge_fare,
            x='surge_multiplier',
            y='fare_amount',
            title="Average Fare vs Surge Multiplier",
            color='fare_amount',
            color_continuous_scale='plasma'
        )
        st.plotly_chart(fig_surge_fare, use_container_width=True)

# Business Insights Section
st.header("💡 Strategic Business Insights")
st.markdown('<div class="insight-box">', unsafe_allow_html=True)

completion_rate_val = (len(filtered_trips[filtered_trips['trip_status'] == 'completed']) / len(filtered_trips)) * 100
avg_rating = filtered_trips['rider_rating'].mean()
payment_success_rate = (len(filtered_payments[filtered_payments['payment_status'] == 'successful']) / len(filtered_payments)) * 100
avg_surge = filtered_trips['surge_multiplier'].mean()

st.markdown(f"""
**Key Performance Highlights:**

1. **Platform Efficiency**: 
   - Trip completion rate: <span class="kpi-positive">{completion_rate_val:.1f}%</span>
   - Payment success rate: <span class="kpi-positive">{payment_success_rate:.1f}%</span>
   - Average rider rating: <span class="kpi-positive">{avg_rating:.2f}/5.0</span>

2. **Market Opportunities**:
   - Peak demand hours: 7-9 AM and 5-7 PM (commuter traffic)
   - Average surge multiplier: <span class="kpi-positive">{avg_surge:.2f}x</span>
   - Premium vehicle types show higher revenue per trip

3. **Operational Insights**:
   - Driver cancellations are primary source of trip failures
   - Surge pricing effectively manages demand during peak hours
   - Credit card payments dominate transaction volume

4. **Strategic Recommendations**:
   - Implement driver incentives during high-cancellation periods
   - Expand premium vehicle fleet in high-value markets
   - Optimize surge algorithms for better demand-supply balance
   - Invest in driver retention programs for top performers
""", unsafe_allow_html=True)
st.markdown('</div>', unsafe_allow_html=True)

# Footer
st.markdown("---")
st.markdown("**Built with:** Python, Streamlit, Plotly | ** Project:** Advanced SQL Analytics | ** Focus:**  Mobility Platform Intelligence")
