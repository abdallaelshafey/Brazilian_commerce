----------------------------------------
----- Creating date dimension table-----
----------------------------------------
CREATE TABLE dim_date (
    date_id     INT PRIMARY KEY,
    full_date   DATE,
    year        INT,
    quarter     INT,
    month       INT,
    month_name  VARCHAR,
    week        INT,
    day_of_week VARCHAR
);

	-- looking inside empty date table
	select * from dim_date;

-- Bulk Inserting values into date table
insert into dim_date(
    date_id, 
    full_date, 
    year, 
    quarter, 
    month, 
    month_name, 
    week, 
    day_of_week
)
select
	to_char(d, 'YYYYMMDD')::int,
	d, -- date itself
	extract(year from d)::int,
	extract(quarter from d)::int,
	extract(month from d)::int,
	to_char(d, 'Month'),
	extract(week from d)::int,
	to_char(d, 'Day')
from generate_series(
'2016-09-04'::DATE, 
'2018-10-14'::DATE, 
'1 day'
) as d;


--------------------------------------------
----- Creating customer dimension table-----
--------------------------------------------

CREATE TABLE dim_customer (
    customer_id             VARCHAR PRIMARY KEY,
    customer_unique_id      VARCHAR,
    customer_city           VARCHAR,
    customer_state          VARCHAR,
    customer_zip_code_prefix VARCHAR
);


------------------------------------------
----- Creating seller dimension table-----
------------------------------------------

CREATE TABLE dim_seller (
    seller_id               VARCHAR PRIMARY KEY,
    seller_city             VARCHAR,
    seller_state            VARCHAR,
    seller_zip_code_prefix  VARCHAR
);

select * from dim_seller limit 100;

------------------------------------------
----- Imported remaining tables from R----
------------------------------------------

select * from geolocation limit 50;
select * from order_items limit 50;
select * from order_payments limit 50;
select * from order_reviews limit 50;
select * from orders limit 50;
select * from products limit 50;

alter table dim_products rename to dim_product;



------------------------------------------
----- Creating fact_order_items table ----
------------------------------------------
select * from dim_customer limit 40;
select * from dim_date limit 40;
select * from orders limit 30;
select * from order_items limit 50;

create table fact_order_items as 
select
	-- row_number() over(order by orders.order_id) as order_item_sk, 
	orders.order_id,
	order_item_id,
	seller_id, -- from order_items
	product_id, -- from order_items
	customer_id, 
	to_char(order_purchase_timestamp::date, 'YYYYMMDD')::int as order_date_id,
	price,  -- from order_items
	freight_value  -- from order_items
from 
	order_items
left join orders on order_items.order_id = orders.order_id; -- 112650 is correct. parallels R table


	
------------------------------------------
----- Creating fact_orders fact table ----
------------------------------------------

create table fact_orders as
select 
	orders.order_id,
	customer_id,
	review_score, -- get from order_reviews
	review_id, -- get from order_reviews
	order_status,
	to_char(order_purchase_timestamp, 'YYYYMMDD')::int as order_date_id,
	to_char(order_approved_at, 'YYYYMMDD')::int as order_approved_date,
	to_char(order_estimated_delivery_date, 'YYYYMMDD')::int as order_estimated_delivery_date,
	to_char(order_delivered_carrier_date, 'YYYYMMDD')::int as order_delivered_carrier_date,
	to_char(order_delivered_customer_date, 'YYYYMMDD')::int as order_delivered_customer_date
from 
	orders left join order_reviews on
	order_reviews.order_id = orders.order_id;
	

------------------------------------------
---- Creating fact_payments fact table ---
------------------------------------------

create table fact_payments as
select 
	orders.order_id,
	payment_type,
	payment_sequential,
	payment_value,
	payment_installments,
	to_char(order_purchase_timestamp, 'YYYYMMDD')::int as order_date_id,
	customer_id
from 
	orders left join order_payments on
	orders.order_id = order_payments.order_id;
	
select * from fact_payments limit 10;