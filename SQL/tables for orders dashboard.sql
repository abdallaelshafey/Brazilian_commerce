-- Since we don't have Tableau Desktop, we must query our relevant
-- questions, then export to individual csvs.

--------------------------------------------------------
--------------- Customer Experience ----------------

--* Does late delivery cause lower review scores?
--* Which states have the worst delivery times?
--* What percentage of orders arrive later than estimated?
create table customer_experience1 as
select 
	case customer_state
        WHEN 'SP' THEN 'São Paulo'
        WHEN 'RJ' THEN 'Rio de Janeiro'
        WHEN 'MG' THEN 'Minas Gerais'
        WHEN 'RS' THEN 'Rio Grande do Sul'
        WHEN 'PR' THEN 'Paraná'
        WHEN 'SC' THEN 'Santa Catarina'
        WHEN 'BA' THEN 'Bahia'
        WHEN 'GO' THEN 'Goiás'
        WHEN 'ES' THEN 'Espírito Santo'
        WHEN 'PE' THEN 'Pernambuco'
        WHEN 'CE' THEN 'Ceará'
        WHEN 'PA' THEN 'Pará'
        WHEN 'MT' THEN 'Mato Grosso'
        WHEN 'MA' THEN 'Maranhão'
        WHEN 'MS' THEN 'Mato Grosso do Sul'
        WHEN 'RO' THEN 'Rondônia'
        WHEN 'PB' THEN 'Paraíba'
        WHEN 'AM' THEN 'Amazonas'
        WHEN 'AL' THEN 'Alagoas'
        WHEN 'PI' THEN 'Piauí'
        WHEN 'RN' THEN 'Rio Grande do Norte'
        WHEN 'SE' THEN 'Sergipe'
        WHEN 'TO' THEN 'Tocantins'
        WHEN 'AC' THEN 'Acre'
        WHEN 'AP' THEN 'Amapá'
        WHEN 'RR' THEN 'Roraima'
        WHEN 'DF' THEN 'Distrito Federal'	
	end as state_name,
	customer_city,
	fo.order_id,
	avg(review_score) as review_score,
	order_approved_date,
	order_estimated_delivery_date as est_deliv_date,
	order_delivered_customer_date as deliv_date
from
	dim_customer dc
inner join
	fact_orders as fo on fo.customer_id = dc.customer_id
GROUP BY
    dc.customer_state,
	dc.customer_city,
    fo.order_id,
    fo.order_approved_date,
    fo.order_estimated_delivery_date,
    fo.order_delivered_customer_date; -- all non-aggregated selects
	--must appear in group by
	
--* Do higher value orders get better review scores?
create table customer_experience2 as 
SELECT
    distinct fo.order_id,
    avg(fo.review_score) as avg_review_score,
    SUM(foi.price) AS total_price
FROM fact_orders fo
JOIN fact_order_items foi ON foi.order_id = fo.order_id
WHERE fo.review_score IS NOT NULL
GROUP BY fo.order_id, fo.review_score;

select * from geolocation_tableau limit 10;

-- min and max of lat and lng are almost identical. Can average them 
-- to get city coordinates b/c tableau doesnt recognise many brazilian
-- city names
select 
	--geolocation_zip_code_perfix,
	min(geolocation_lat),
	max(geolocation_lat),
	geolocation_city
from
	geolocation_tableau
group by
	geolocation_city 

--------------------------------------------------------
--------------- Seller Performance ----------------

--* Which sellers have the highest revenue but lowest satisfaction scores?

-- inner join dc and do and foi
-- left join them all onto dc

SELECT
    ds.seller_id,
    ds.seller_state,
    round(SUM(foi.price)::numeric,2)          AS total_revenue,
    round(AVG(fo.review_score)::numeric,2)    AS avg_review_score
FROM fact_order_items foi
JOIN dim_seller ds  ON ds.seller_id  = foi.seller_id
JOIN fact_orders fo ON fo.order_id   = foi.order_id
GROUP BY  ds.seller_state, ds.seller_id
ORDER BY total_revenue DESC;

--* Which states have the most concentrated seller activity?
select * from dim_seller limit 10;
SELECT
    ds.seller_state,
    COUNT(DISTINCT ds.seller_id)    AS num_sellers,
    COUNT(DISTINCT foi.order_id)    AS num_orders,
    round(SUM(foi.price)::numeric,2)   AS total_revenue
FROM dim_seller ds
LEFT JOIN fact_order_items foi ON ds.seller_id = foi.seller_id
GROUP BY ds.seller_state
ORDER BY num_sellers DESC;


--* Is there a relationship between freight value and review score?

SELECT
    fo.order_id,
    round(AVG(fo.review_score)::numeric,2)  AS avg_review_score,
    SUM(foi.freight_value)      AS total_freight_value,
    SUM(foi.price)              AS total_order_value
FROM fact_orders fo
JOIN fact_order_items foi ON foi.order_id = fo.order_id
WHERE fo.review_score IS NOT NULL
GROUP BY fo.order_id;


--* Which sellers consistently deliver late?

--inner join dc, fo, foi left join onto sellers

    SELECT
        ds.seller_id,
        ds.seller_state,
        COUNT(*) FILTER (
            WHERE fo.order_delivered_customer_date 
                > fo.order_estimated_delivery_date
        ) AS num_late,
        COUNT(*) FILTER (
            WHERE fo.order_delivered_customer_date 
                <= fo.order_estimated_delivery_date
        ) AS num_on_time,
        COUNT(*) AS total_orders
    FROM fact_order_items foi
    JOIN dim_seller ds  ON ds.seller_id = foi.seller_id
    JOIN fact_orders fo ON fo.order_id  = foi.order_id
    WHERE fo.order_delivered_customer_date IS NOT NULL
    GROUP BY ds.seller_id, ds.seller_state


	


