-- ============================================================
-- Q1: For each customer state, calculate the total number of
--     orders, the percentage that were late, and the average
--     review score. Order by late order percentage descending.
-- ============================================================

WITH timeliness_tab AS
(SELECT
	distinct 
	customer_state,
	fo.order_id,
	CASE
		WHEN order_delivered_customer_date - order_estimated_delivery_date > 0 THEN 1 --'late'
		WHEN order_delivered_customer_date - order_estimated_delivery_date < 0 THEN 0 --'on-time'
	END AS timeliness	
FROM
	fact_orders fo
INNER JOIN
	fact_order_items foi ON fo.order_id = foi.order_id
RIGHT JOIN
	dim_customer dc ON dc.customer_id = fo.customer_id
WHERE
	fo.order_status != 'canceled')  -- we'll assume canceled orderes get refunded
SELECT
	customer_state,
	COUNT(DISTINCT fo.order_id) AS "order count",
	ROUND(AVG(review_score)::NUMERIC,2) AS "Avg review score",
	-- fraction of orders late
	(SELECT	
		ROUND(100*(COUNT(*) FILTER(WHERE timeliness=1)::numeric/ COUNT(*)::numeric),2)
	 FROM
		 timeliness_tab
	 WHERE
	 	timeliness_tab.customer_state = dc.customer_state
		) AS pct_late
FROM
	fact_orders fo
INNER JOIN
	fact_order_items foi ON fo.order_id = foi.order_id
RIGHT JOIN
	dim_customer dc ON dc.customer_id = fo.customer_id
WHERE
	fo.order_status != 'canceled'
GROUP BY
	customer_state
ORDER BY
	pct_late DESC


-- ============================================================
-- Q2: Find the top 10 sellers by total revenue. For each,
--     include their total number of orders and average review
--     score. (price used as proxy for revenue)
-- ============================================================

SELECT
	DS.SELLER_ID,
	ROUND(SUM(PRICE)::NUMERIC,2) AS REVENUE,
	COUNT(FO.ORDER_ID) AS NUM_ORDERS,
	ROUND(AVG(REVIEW_SCORE)::NUMERIC, 2) AS AVG_REVIEW_SCORE
FROM
	DIM_SELLER DS
	INNER JOIN FACT_ORDER_ITEMS FOI ON DS.SELLER_ID = FOI.SELLER_ID
	INNER JOIN FACT_ORDERS FO ON FO.ORDER_ID = FOI.ORDER_ID
WHERE
	fo.order_status != 'canceled'
GROUP BY
	DS.SELLER_ID
ORDER BY
	REVENUE desc
LIMIT
	10

-- ============================================================
-- Q3: What is the most common payment method for orders above
--     the average order value? 
-- ============================================================
WITH order_values AS (
    SELECT
        foi.order_id,
        SUM(foi.price) AS order_revenue
    FROM 
		fact_order_items foi
    GROUP BY 
		foi.order_id
),
avg_order_value AS (
    SELECT 
		AVG(order_revenue) AS avg_val 
	FROM 
		order_values
),
payment_above AS (
    SELECT 
		fp.payment_type, 'above' AS segment
    FROM 
		order_values ov
    JOIN 
		avg_order_value ON TRUE
    JOIN 
		fact_payments fp ON ov.order_id = fp.order_id
    WHERE 
		ov.order_revenue > avg_val
      AND 
	  	fp.payment_type IS NOT NULL
),
payment_below AS (
    SELECT 
		fp.payment_type, 'below' AS segment
    FROM 
		order_values ov
    JOIN 
		avg_order_value ON TRUE
    JOIN 
		fact_payments fp ON ov.order_id = fp.order_id
    WHERE 
		ov.order_revenue <= avg_val
      AND 
	  	fp.payment_type IS NOT NULL
)
SELECT 
	segment, 
	payment_type, 
	COUNT(*) AS freq
FROM 
	(SELECT 
		* 
	 FROM 
	 	payment_above 
	 UNION ALL SELECT 
	 	* 
	 FROM 
	 	payment_below) combined
GROUP BY 
	segment, payment_type
ORDER BY 
	segment, freq DESC;
	
 
-- ============================================================
-- Q4: Bucket orders into delivery time terciles (fast / medium
--     / slow). Show the average review score and late order
--     rate for each bucket.
--     fast: < 1 week | medium: 1-2 weeks | slow: 2+ weeks
-- ============================================================

WITH delivery_terciles AS
(SELECT
    DISTINCT order_id, -- recall from the R exploration that there are over 500 duplicates in fact_orders
	CASE
		WHEN (order_delivered_customer_date - order_approved_date) < 7 THEN 'fast'
		WHEN (order_delivered_customer_date - order_approved_date) BETWEEN 7 AND 14 THEN 'medium'
		WHEN (order_delivered_customer_date - order_approved_date) > 14 THEN 'slow'
	END AS delivery_speed
FROM 
	fact_orders
WHERE 
	order_delivered_customer_date IS NOT NULL)
SELECT
	delivery_speed,
	round(AVG(review_score)::numeric,2) AS avg_review_score,
	round((COUNT(*) FILTER(WHERE order_delivered_customer_date - order_estimated_delivery_date>0))::numeric/count(*)::numeric, 2)
		AS late_rate
FROM
	delivery_terciles dt
INNER JOIN
	fact_orders fo ON fo.order_id = dt.order_id
WHERE
	delivery_speed IS NOT NULL
GROUP BY
	delivery_speed

-- ============================================================
-- Q5: Rank sellers within each state by total revenue using a
--     window function. Return the top 3 sellers per state.
-- ============================================================

WITH seller_revenue AS
		(SELECT
			seller_state,
			ds.seller_id,
			ROUND(SUM(price)::NUMERIC,2) AS total_revenue
		FROM
			dim_seller ds
		LEFT JOIN
			fact_order_items foi ON ds.seller_id = foi.seller_id
		 GROUP BY
		 	seller_state, ds.seller_id),
ranked AS
		(SELECT
			*,
			RANK() OVER(PARTITION BY seller_state ORDER BY total_revenue DESC) AS revenue_rank
		FROM
			seller_revenue)
SELECT
	*
FROM 
	ranked
WHERE
	revenue_rank <=3
ORDER BY
	seller_state, revenue_rank;



-- ============================================================
-- Q6: Identify sellers with above-average revenue and below-
--     average review scores ("high volume, low quality").
-- ===========================================================

-- average revenue
WITH 
seller_revenue AS
		(SELECT
			ds.seller_id,
			ROUND(SUM(price)::NUMERIC,2) AS revenue
		 FROM
		 	fact_orders fo
		 INNER JOIN
		 	fact_order_items foi ON fo.order_id = foi.order_id
		RIGHT JOIN
			dim_seller ds ON ds.seller_id = foi.seller_id
		GROUP BY
			ds.seller_id),
-- average review scores
seller_review AS 
		(SELECT
			ds.seller_id,
			ROUND(AVG(review_score)::NUMERIC,2) AS avg_review_score
		FROM
			fact_order_items foi
		INNER JOIN
			fact_orders fo ON foi.order_id = fo.order_id
		RIGHT JOIN
			dim_seller ds ON ds.seller_id = foi.seller_id
		GROUP BY
			ds.seller_id)
-- inner join both tables
SELECT 
	seller_revenue.seller_id,
	ROUND(revenue::NUMERIC,2) AS revenue,
	avg_review_score
FROM 
	seller_revenue 
INNER JOIN
	seller_review ON seller_revenue.seller_id = seller_review.seller_id
WHERE
	-- seller revenue above average revenue for sellers 
	revenue > (SELECT
			   		ROUND(AVG(revenue)::NUMERIC,2)
			   FROM seller_revenue)
AND
	-- seller review score below average review score of sellers
	avg_review_score < (SELECT
							AVG(avg_review_score)
						FROM
							seller_review)
							
-- ============================================================
-- Q7: For each product category, calculate the average
--     freight-to-price ratio and the average review score.
--     Which categories have a high freight burden?
-- ============================================================


SELECT
	product_category_name_english AS product_name,
	round((SUM(freight_value)/SUM(price))::numeric,2) AS freight_price_ratio,
	round(AVG(review_score)::numeric,2) AS avg_review_score
FROM
	fact_orders fo
INNER JOIN
	fact_order_items foi ON foi.order_id = fo.order_id
RIGHT JOIN
	dim_product dp ON foi.product_id = dp.product_id
WHERE
	product_category_name_english IS NOT NULL
GROUP BY
	product_category_name_english
ORDER BY
 	freight_price_ratio DESC
	
	
-- ============================================================
-- Q8: For each month, calculate the cumulative total revenue
--     across all orders using a running sum window function.
-- ============================================================

WITH 
monthly_revenue AS
		(SELECT 
			"month",
			ROUND(SUM(price)::NUMERIC,2) AS order_price
		FROM
			fact_orders fo
		INNER JOIN
			dim_date dd ON fo.order_date_id = dd.date_id
		INNER JOIN
			fact_order_items foi ON fo.order_id = foi.order_id
		GROUP BY
			"month")
SELECT 
	*,
	SUM(order_price) OVER(ORDER BY "month") AS rolling_revenue
FROM
	monthly_revenue


-- ============================================================
-- Q9: For each seller, calculate the 3-month rolling average
--     of their monthly revenue. Flag any seller whose most
--     recent month is more than 20% below their rolling
--     average (declining sellers).
-- ============================================================

WITH 
monthly_rev AS
		(SELECT
			ds.seller_id,
			"month",
			ROUND(SUM(price)::NUMERIC,2) AS monthly_rev
		FROM
			fact_orders fo
		INNER JOIN
			fact_order_items foi ON fo.order_id = foi.order_id
		INNER JOIN
			dim_date dd ON fo.order_date_id = dd.date_id
		RIGHT JOIN
			dim_seller ds ON foi.seller_id = ds.seller_id
		GROUP BY
			ds.seller_id, "month"
		ORDER BY
			ds.seller_id, "month"),
rolling_3m AS
		(SELECT
			*,
			ROUND((AVG(monthly_rev) OVER(PARTITION BY seller_id ORDER BY "month"
			ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING))::NUMERIC,2) rolling_quarter
		FROM
			monthly_rev)
SELECT
	*,
	CASE
		WHEN monthly_rev < 0.8*rolling_quarter THEN 'true' ELSE 'false'
	END AS "flag"
FROM
	rolling_3m

