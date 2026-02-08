create database quickbite_db;
use quickbite_db;


select * from dim_customer;
select * from dim_delivery_partner;
select * from dim_menu_item;
select * from dim_restaurant;
select * from fact_delivery_performance;
select * from fact_order_items;
select * from fact_orders where is_cancelled = "Y" limit 5;
select * from fact_ratings;

/*  Problem Statement :
 QuickBite Express is a Bengaluru-based food-tech startup (founded in 2020) that connects customers with nearby restaurants
 and cloud kitchens. In June 2025, QuickBite faced a major crisis. A viral social media incident involving food safety violations at partner restaurants, 
 combined with a week-long delivery outage during the monsoon season, triggered massive customer backlash.
 Competitors capitalized with aggressive campaigns, worsening the situation.
*/

 -- Compare total orders across pre-crisis (Jan–May 2025) vs crisis (Jun–Sep 2025). 
select 
sum(case when order_timestamp >= '2024-12-31' and order_timestamp <=  '2025-05-31'  then 1 else 0 end) as Pre_Crisis,
sum(case when order_timestamp > '2025-05-31' and order_timestamp <=  '2025-10-01'  then 1 else 0 end) as Crisis,
round( (sum(case when order_timestamp >= '2024-12-31' and order_timestamp <=  '2025-05-31'  then 1 else 0 end) 
 -sum(case when order_timestamp > '2025-05-31' and order_timestamp <=  '2025-10-01'  then 1 else 0 end) )
 / sum(case when order_timestamp <= '2025-06-01' then 1 else 0 end)*100 ,2)
 as `Declined_%`
from fact_orders;

-- Which top 5 city groups experienced the highest percentage decline in orders during the crisis period compared to the pre-crisis period?
select x.*, (Crisis - Pre_Crisis) / Pre_Crisis * 100 as `Declined %`
from (
select distinct dr.city,
sum(case when order_timestamp >= '2024-12-31' and order_timestamp <=  '2025-05-31'  then 1 else 0 end) as Pre_Crisis,
sum(case when order_timestamp > '2025-05-31' and order_timestamp <=  '2025-10-01'  then 1 else 0 end) as Crisis
from dim_restaurant dr left join fact_orders fo using (restaurant_id)
group by dr.city ) x
order by `Declined %` desc ;

--  Among restaurants with at least 50 pre-crisis orders, which top 10 high-volume restaurants experienced the largest percentage decline in 
-- order counts during the crisis period?
with pre_crisis as (
	select distinct restaurant_name, count(order_id) as total_order_pre_crisis
	from dim_restaurant dr left join fact_orders fo using (restaurant_id)
	where fo.order_timestamp between '2025-01-01' and '2025-05-31'
	group by restaurant_name
	having count(order_id) >= 50),
crisis as (
	 select distinct restaurant_name, count(order_id) as total_order_crisis
	from dim_restaurant dr left join fact_orders fo using (restaurant_id)
	where fo.order_timestamp between '2025-06-01' and '2025-09-30'
	group by restaurant_name
)
select *, (total_order_pre_crisis - total_order_crisis) / total_order_pre_crisis *100 as `Declined %`
from crisis c left join pre_crisis pc using (restaurant_name)
where (total_order_pre_crisis - total_order_crisis) / total_order_pre_crisis is not null
order by total_order_pre_crisis desc
limit 10;

-- What is the cancellation rate trend pre-crisis (Jan–May 2025) vs crisis (Jun–Sep 2025) and which cities are most affected? 
	/*Cancellation Rate formula:
cancelled_orders / total_orders * 100*/
    
with City_Phrases as (
	Select dr.city,
    case when order_timestamp >= '2025-01-01' and order_timestamp <= '2025-06-01' then 'Pre-Crisis'
	 when order_timestamp >= '2025-06-01' and order_timestamp <= '2025-10-01' then 'Crisis' end as Phrase,
	sum(case when is_cancelled = 'Y' then 1 else 0 end) as Cancelled_Orders,
	count(*) as Total_Orders
	from fact_orders fo inner join dim_restaurant dr using (restaurant_id)
	group by dr.city,Phrase) ,
    
Cancelled_Rates as (
	select *,
   round( (Cancelled_Orders/Total_Orders) *100,2) as Cancelled_Pct
	from City_Phrases ),
    
City_wise_Cancelled_Pct as (
select city,
max(CASE WHEN phrase = 'Pre-Crisis' THEN Cancelled_Pct END) as Pre_Cancelled_Pct ,
max(CASE WHEN phrase = 'Crisis' THEN Cancelled_Pct END) as Crisis_Cancelled_Pct,
max(CASE WHEN phrase = 'Pre-Crisis' THEN Cancelled_Pct END) - max(CASE WHEN phrase = 'Crisis' THEN Cancelled_Pct END) as Decreased_Pct
from Cancelled_Rates 
group by city
order by Crisis_Cancelled_Pct desc  )

select * from City_wise_Cancelled_Pct;

/*INSIGHT : Cancellation rates increased significantly during the crisis, with cities like Ahmedabad, Pune, Hyderabad showing the sharpest rise, 
			indicating operational or supply-side stress concentrated in high-density markets.*/ 

--  Measure average delivery time across phases. Did SLA compliance worsen significantly in the crisis period? 
select x.*,
		round( (Delivered_On_Time / Total_Orders)*100,2) as SLA_Compliance_Rate 
from(Select  case when order_timestamp >= '2025-01-01' and order_timestamp <= '2025-06-01' then 'Pre-Crisis'
			 when order_timestamp >= '2025-06-01' and order_timestamp <= '2025-10-01' then 'Crisis' end as Phrase,
             round(avg(actual_delivery_time_mins),0) as Avg_Delivery_Time_Mins,
			sum(case when  actual_delivery_time_mins<=expected_delivery_time_mins then 1 else 0 end )as Delivered_On_Time,
			count(*) as Total_Orders
			from fact_orders fo inner join fact_delivery_performance using (order_id)
			where is_cancelled ="N"
			group by Phrase) x;
   /*INSIGHT : Average delivery time increased noticeably during the crisis, while SLA compliance dropped significantly. 
   This indicates operational strain, likely due to increased demand volatility, delivery partner shortages, or longer preparation times. 
   The crisis period clearly shows degraded service reliability.*/         
   
-- Track average customer rating month-by-month. Which months saw the sharpest drop?  
with Mom_Change as 
(select x.* ,
lag(Avg_Customer_Rating,1) over (order by Months) as Prev_Month
from (select date_format(review_timestamp,'%m-%y-01') as Months , round(avg(rating),1) as Avg_Customer_Rating
	  from fact_ratings
       group by Months
      order by Months  ) x ),
      
MOM_Pct_Change as (
select *, round ( (Avg_Customer_Rating - Prev_Month) / Avg_Customer_Rating , 2) as `Mom %`
from Mom_Change
)
select * from MOM_Pct_Change
order by `Mom %`;

/*INSIGHT : Customer ratings declined steadily over time, with the sharpest drop occurring in June 2025, coinciding with the onset of the crisis period. 
This suggests that service disruptions—likely driven by increased delivery delays and SLA breaches—directly impacted customer satisfaction.*/

-- During the crisis period, identify the most frequently occurring negative keywords in customer review texts. 

select x.review_text
from (
		select review_text, count(*) as Total_Keywords
		from fact_ratings fr inner join fact_orders fo using (order_id)
		where order_timestamp between '2025-06-01' and '2025-10-01' and sentiment_score <0
		group by review_text
		order by Total_Keywords desc) x;

/*INSIGHT : During the crisis period, customer dissatisfaction was driven primarily by food quality and safety concerns, along with delivery-related issues. 
The most frequently occurring negative keywords included food quality not good, stale food served, bad taste, food safety issue, and terrible hygiene, 
indicating operational strain across both restaurant preparation and last-mile delivery.*/

-- Estimate revenue loss from pre-crisis vs crisis (based on subtotal, discount, and delivery fee). 
with Phrases_Revenue as (
select case when order_timestamp >= '2025-01-01' and order_timestamp <= '2025-06-01'  then 'Pre- Crisis'
			when order_timestamp >= '2025-06-01' and order_timestamp <= '2025-10-01'  then 'Crisis' end as Phrase,
        sum(total_amount) as Revenue
from fact_orders
where is_cancelled = 'N'
group by Phrase)

select 
max(case when Phrase = 'Pre- Crisis' then Revenue end) as Pre_Crisis_Revenue,
max(case when Phrase = 'Crisis' then Revenue end) as Crisis_Revenue,

round(( max(case when Phrase = 'Crisis' then Revenue end) - max(case when Phrase = 'Pre- Crisis' then Revenue end) ) / 
												max(case when Phrase = 'Pre- Crisis' then Revenue end)*100 ,1) as Revenue_Loss
from Phrases_Revenue;

/*INSIGHT :Net revenue declined sharply during the crisis period compared to pre-crisis levels.
This decline was likely driven by a drop in order volumes, as customer activity reduced during the crisis,
 combined with lower service reliability, including increased delivery delays, higher cancellation rates, and worsening SLA compliance.*/

-- Among customers who placed five or more orders before the crisis, determine how many stopped ordering during the crisis, and out of those, 
-- how many had an average rating above 4.5?

with before_crisis as (
select customer_id, count(*) as Pre_crisis_Orders
from fact_orders
where order_timestamp <= '2025-06-01'and is_cancelled = 'N'
group by customer_id
having count(*) >= 5 ),

crisis as (
select customer_id, count(*) as crisis_Orders
from fact_orders
where order_timestamp >= '2025-06-01' and order_timestamp <= '2025-10-01'and is_cancelled = 'N'
group by customer_id
),
stopped_order as (
select * 
from before_crisis left join crisis using (customer_id)
where coalesce(crisis_Orders,0) = 0
),
High_Rating_Cust as (
select customer_id , round (avg(rating),1) as Avg_Rating
from fact_ratings 
group by customer_id
having Avg_Rating >= 4.5
)
select *
from stopped_order so left join High_Rating_Cust ar using (customer_id)
where Avg_Rating is not null;
/*INSIGHT :A meaningful share of high-frequency customers who placed five or more orders before the crisis completely stopped ordering during the crisis period.
The loss of previously loyal and high-satisfaction customers highlights a breakdown in service continuity during the crisis. 
Retention strategies should focus on re-engaging these high-value customers and addressing operational pain points that triggered their churn*/


--  Which high-value customers (top 5% by total spend before the crisis) showed the largest drop in order frequency and ratings during the crisis? 
-- What common patterns (e.g., location, cuisine preference, -- delivery delays) do they share? 

with Cust_Spend_Before_Crisis as (
select customer_id , sum(total_amount) as Total_Spend
from fact_orders 
where order_timestamp <= '2025-05-31' and is_cancelled = 'N'
group by customer_id) ,

rank_cust as (
select *,
round (percent_rank() over (order by Total_Spend desc),1) as Cust_Rank
from Cust_Spend_Before_Crisis
),
top_5_pct as  (
select customer_id, Total_Spend
from rank_cust
where Cust_Rank <= 0.05),

order_frequency as (
select customer_id, 
sum(case when order_timestamp >= '2024-12-31' and order_timestamp <= '2025-06-01' then 1 else 0 end) as 'Pre_Crisis_Orders',
sum(case when order_timestamp >= '2025-05-31' and order_timestamp <= '2025-10-01' then 1 else 0 end) as 'Crisis_Orders'
from fact_orders fo
where is_cancelled = 'N'
group by customer_id
),

Cust_Ratings as (
select customer_id, 
round(avg(case when review_timestamp >= '2024-12-31' and review_timestamp <= '2025-06-01' then rating end),1) as 'Pre_Crisis_Ratings',
avg(case when review_timestamp >= '2025-05-31' and review_timestamp <= '2025-10-01' then rating end) as 'Crisis_Ratings'
from fact_ratings fr
group by customer_id
),
-- Delivery_Delays 
delivery_delays as (
select customer_id, round (avg(actual_delivery_time_mins - expected_delivery_time_mins),1) as delivery_delays_mins
from fact_delivery_performance dp inner join fact_orders fo using (order_id)
where fo.order_timestamp BETWEEN '2025-06-01' AND '2025-09-30' and is_cancelled = 'N'
group by customer_id
),

cuisine_preference as (
select customer_id,cuisine_type
from ( select customer_id,cuisine_type ,
		row_number() over (partition by customer_id order by count(*)) as rn
		from fact_orders fo inner join dim_restaurant dr using (restaurant_id)
		where fo.order_timestamp BETWEEN '2025-06-01' AND '2025-09-30' and is_cancelled = 'N'
		group by  customer_id, cuisine_type) x
where rn = 1 )

select  tp.customer_id,
    dm.city,
    cp.cuisine_type,
    ofq.Pre_Crisis_Orders,
    ofq.Crisis_Orders,
    (ofq.Pre_Crisis_Orders - ofq.Crisis_Orders) AS order_drop,
    cr.Pre_Crisis_Ratings,
    coalesce(cr.Crisis_Ratings, '-') as Crisis_Ratings,
    coalesce(ROUND(cr.Pre_Crisis_Ratings - cr.Crisis_Ratings, 1), '-') AS rating_drop,
  coalesce(dd.delivery_delays_mins , '-') as delivery_delays_mins
from top_5_pct tp inner join order_frequency ofq using (customer_id)
left join Cust_Ratings cr using (customer_id)
left join delivery_delays dd using (customer_id)
left join cuisine_preference cp using (customer_id)
left join dim_customer dm using (customer_id) ;

-- No crisis orders → No crisis ratings 

/* INSIGHT : Several top 5% high-value customers completely stopped ordering during the crisis. These customers had strong pre-crisis ratings but no crisis activity, 
indicating abrupt churn rather than gradual dissatisfaction. The absence of crisis ratings and delivery data confirms a total disengagement pattern*/

CREATE TABLE fact_orders (
    order_id                VARCHAR(20) PRIMARY KEY,
    customer_id             VARCHAR(20) NOT NULL,
    restaurant_id           VARCHAR(20) NOT NULL,
    delivery_partner_id     VARCHAR(20),
    order_timestamp         DATETIME NOT NULL,

    subtotal_amount         DECIMAL(10,2),
    discount_amount         DECIMAL(10,2),
    delivery_fee            DECIMAL(10,2),
    total_amount            DECIMAL(10,2),

    is_cod                  CHAR(1),
    is_cancelled            CHAR(1),

    -- Foreign Key Constraints
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES dim_customer(customer_id),

    CONSTRAINT fk_orders_restaurant
        FOREIGN KEY (restaurant_id) REFERENCES dim_restaurant(restaurant_id),

    CONSTRAINT fk_orders_delivery_partner
        FOREIGN KEY (delivery_partner_id) REFERENCES dim_delivery_partner(delivery_partner_id)
);

CREATE TABLE fact_delivery_performance (
    order_id                        VARCHAR(20) PRIMARY KEY,
    actual_delivery_time_mins       INT,
    expected_delivery_time_mins     INT,
    distance_km                     DECIMAL(6,2),

    -- Foreign Key Constraint
    CONSTRAINT fk_delivery_order
        FOREIGN KEY (order_id) REFERENCES fact_orders(order_id)
);
