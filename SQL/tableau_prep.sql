----------------Review score and timeliness bucket-------------
-- "At what delivery delay threshold does review score drop significantly 
-- and which states cross it most often?"

with 
lateness as
(select
	order_id,
	case
		when order_delivered_customer_date::text::date - order_estimated_delivery_date::text::date between 1 and 3 then '1-3 days late'
		when order_delivered_customer_date::text::date - order_estimated_delivery_date::text::date between 4 and 7 then '4-7 days late'
		when order_delivered_customer_date::text::date - order_estimated_delivery_date::text::date between 8 and 14 then '8-14 days late'
		when order_delivered_customer_date::text::date - order_estimated_delivery_date::text::date > 14  then '14+ days late'
		when order_delivered_customer_date::text::date = order_estimated_delivery_date::text::date then 'on-time'
		when order_estimated_delivery_date::text::date - order_delivered_customer_date::text::date between 1 and 3 then '1-3 days early'
		when order_estimated_delivery_date::text::date - order_delivered_customer_date::text::date between 4 and 7 then '4-7 days early'
		when order_estimated_delivery_date::text::date - order_delivered_customer_date::text::date between 8 and 14 then '8-14 days early'
		when order_estimated_delivery_date::text::date - order_delivered_customer_date::text::date > 14  then '14+ days early'
	end as timeliness
from
	fact_orders
where
	order_status = 'delivered'
	and
	review_score is not null
)
select
	fo.order_id,
	avg(review_score) as avg_review_score,
	timeliness
from
	fact_orders fo
inner join
	lateness on lateness.order_id = fo.order_id
group by
	fo.order_id, timeliness

------------lateness pct and order volume------------
-- "Which states have both high late rates AND high order volume; 
-- where is the business risk concentrated?"


select
	dc.customer_state,
	count(distinct fo.order_id) as num_orders,
	round(100*((count(distinct fo.order_id) filter(where order_delivered_customer_date > order_estimated_delivery_date))::numeric/count(distinct fo.order_id)::numeric),2) as pct_late
from
	dim_customer dc
left join
	fact_orders fo on dc.customer_id = fo.customer_id
where
    fo.order_status = 'delivered'
    and fo.order_delivered_customer_date is not null	
group by
	dc.customer_state
	

---------Lateness distribution------------
-- make a distribution of days late

select
	distinct 
	order_id,
	"year",
	"month",
	(order_delivered_carrier_date::text::date - order_approved_date::text::date) as seller_to_carrier,
	(order_delivered_customer_date::text::date - order_delivered_carrier_date::text::date) as carrier_to_customer,
	(order_estimated_delivery_date::text::date - order_approved_date::text::date) as estimated_delivery_days,
	(order_delivered_customer_date::text::date - order_estimated_delivery_date::text::date) as days_late
from
	fact_orders fo
inner join
	dim_date dd on fo.order_date_id = dd.date_id
where
	order_status = 'delivered'
order by 
	"year", "month"

----------- Monthly late pct-------------

-- "Is the late order rate improving or worsening month-over-month, 

with lateness_2 as
(select
	distinct 
	order_id,
	"year",
	"month",
	review_score,
	(order_delivered_carrier_date::text::date - order_approved_date::text::date) as seller_to_carrier,
	(order_delivered_customer_date::text::date - order_delivered_carrier_date::text::date) as carrier_to_customer,
	(order_estimated_delivery_date::text::date - order_approved_date::text::date) as estimated_delivery_days,
	(order_delivered_customer_date::text::date - order_estimated_delivery_date::text::date) as days_late,
	case
		when (order_delivered_customer_date::text::date - order_estimated_delivery_date::text::date) > 0 then 'late'
		else 'on-time'
	end as timeliness
from
	fact_orders fo
inner join
	dim_date dd on fo.order_date_id = dd.date_id
where
	order_status = 'delivered'
order by 
	"year", "month"
),
grouped_avg_days_late as
(select 
	"year",
	"month",
	count(order_id) as num_orders,
	round(avg(days_late)::numeric,2) as avg_late_days,
	100*round(((count(order_id) filter (where days_late >0))::numeric/ count(order_id)::numeric),4) as pct_late,
	round(avg(review_score)::numeric,2) as avg_review_score
from 
	lateness_2 l2
group by
	"year", "month")
select
	* from grouped_avg_days_late

---------------- Monthly delivery pipeline---------------------
SELECT
    "year",
    "month",
    ROUND(AVG(estimated_delivery_days)::NUMERIC, 2) AS avg_promised_days,
    ROUND(AVG(seller_to_carrier + carrier_to_customer)::NUMERIC, 2) AS avg_actual_days,
    ROUND(AVG(carrier_to_customer)::NUMERIC, 2) AS avg_last_mile_days
FROM (
    SELECT
        DISTINCT order_id,
        "year",
        "month",
        (order_delivered_carrier_date::text::date - order_approved_date::text::date) AS seller_to_carrier,
        (order_delivered_customer_date::text::date - order_delivered_carrier_date::text::date) AS carrier_to_customer,
        (order_estimated_delivery_date::text::date - order_approved_date::text::date) AS estimated_delivery_days
    FROM
        fact_orders fo
    INNER JOIN
        dim_date dd ON fo.order_date_id = dd.date_id
    WHERE
        order_status = 'delivered'
        AND order_delivered_carrier_date IS NOT NULL
) sub
GROUP BY
    "year", "month"
ORDER BY
    "year", "month"

	


---------Value tier x timeliness---------------

-- "Are high-value late orders disproportionately hurting 
--revenue-weighted satisfaction?"


with order_price as
(select
	fo.order_id,
	fo.review_score,
	order_estimated_delivery_date::text::date,
	order_delivered_customer_date::text::date,
	round(sum(price)::numeric,2) as "order value"
from
	fact_orders fo
inner join
	fact_order_items foi on foi.order_id = fo.order_id
group by
	fo.order_id, 
	fo.review_score,
	order_estimated_delivery_date,
	order_delivered_customer_date
),
percentiles as
( SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY "order value") AS p25,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY "order value") AS p50,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY "order value") AS p75
    FROM order_price)
SELECT
    op.*,
    CASE
        WHEN order_delivered_customer_date - order_estimated_delivery_date > 0 THEN 'late'
        ELSE 'on-time'
    END AS timeliness,
    CASE
        WHEN "order value" < p25                  THEN 'low (< $46)'
        WHEN "order value" BETWEEN p25 AND p50    THEN 'low-mid ($46–87)'
        WHEN "order value" BETWEEN p50 AND p75    THEN 'high-mid ($87–150)'
        ELSE                                           'premium ($150+)'
    END AS "price bucket"
FROM 
	order_price op
CROSS JOIN 
	percentiles

--------------- KPIS--------------

select distinct order_status from fact_orders 

SELECT
    COUNT(DISTINCT order_id)                                                        AS total_orders,
    ROUND(AVG(review_score)::NUMERIC, 2)                                            AS avg_review_score,
    ROUND(AVG(
        order_delivered_customer_date::text::date - order_approved_date::text::date
    )::NUMERIC, 2)                                                                  AS avg_delivery_days,
    ROUND(100 * COUNT(order_id) FILTER (
        WHERE order_delivered_customer_date > order_estimated_delivery_date
    )::NUMERIC / COUNT(order_id)::NUMERIC, 2)                                       AS pct_late
FROM
    fact_orders
WHERE
    order_status NOT IN ('canceled', 'unavailable')



	





