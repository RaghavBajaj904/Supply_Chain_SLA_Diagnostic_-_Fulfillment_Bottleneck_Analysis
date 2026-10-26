-- Supply Chain SLA Diagnostic & Fulfillment Bottleneck Analysis

CREATE DATABASE supply_chain;
USE supply_chain;

CREATE TABLE orders 
(
order_id VARCHAR(50) PRIMARY KEY,
customer_id VARCHAR(50),
order_status VARCHAR(20),
order_purchase_timestamp VARCHAR(50),
order_approved_at VARCHAR(50),
order_delivered_carrier_date VARCHAR(50),
order_delivered_customer_date VARCHAR(50),
order_estimated_delivery_date VARCHAR(50)
);

CREATE TABLE orders_items
(
order_id VARCHAR(50),
order_item_id INT,
product_id VARCHAR(50),
seller_id VARCHAR(50),
shipping_limit_date VARCHAR(50),
price DECIMAL(10, 2),
freight_value DECIMAL(10, 2),
PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE customers
(
customer_id VARCHAR(50) PRIMARY KEY,
customer_unique_id VARCHAR(50),
customer_zip_code_prefix VARCHAR(10),
customer_city VARCHAR(100),
customer_state VARCHAR(5)
);

CREATE TABLE sellers
(
seller_id VARCHAR(50) PRIMARY KEY,
seller_zip_code_prefix VARCHAR(10),
seller_city VARCHAR(100),
seller_state VARCHAR(5)
);

DROP TABLE IF EXISTS products;
CREATE TABLE products
(
product_id VARCHAR(50) PRIMARY KEY,
product_category_name VARCHAR(100),
product_name_lenght VARCHAR(10),
product_description_lenght VARCHAR(10),
product_photos_qty VARCHAR(10),
product_weight_g VARCHAR(10),
product_length_cm VARCHAR(10),
product_height_cm VARCHAR(10),
product_width_cm VARCHAR(10)
);

CREATE TABLE product_translation
(
product_category_name VARCHAR(100) PRIMARY KEY,
product_category_name_english VARCHAR(100)
);

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE "C:/Users/ragha/OneDrive/Desktop/Projects/Supply Chain SLA Diagnostic & Fulfillment Bottleneck Analysis/olist_orders_dataset.csv"
INTO TABLE orders
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE "C:/Users/ragha/OneDrive/Desktop/Projects/Supply Chain SLA Diagnostic & Fulfillment Bottleneck Analysis/olist_order_items_dataset.csv"
INTO TABLE orders_items
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE "C:/Users/ragha/OneDrive/Desktop/Projects/Supply Chain SLA Diagnostic & Fulfillment Bottleneck Analysis/olist_customers_dataset.csv"
INTO TABLE customers
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE "C:/Users/ragha/OneDrive/Desktop/Projects/Supply Chain SLA Diagnostic & Fulfillment Bottleneck Analysis/olist_sellers_dataset.csv"
INTO TABLE sellers
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE "C:/Users/ragha/OneDrive/Desktop/Projects/Supply Chain SLA Diagnostic & Fulfillment Bottleneck Analysis/olist_products_dataset.csv"
INTO TABLE products
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

LOAD DATA LOCAL INFILE "C:/Users/ragha/OneDrive/Desktop/Projects/Supply Chain SLA Diagnostic & Fulfillment Bottleneck Analysis/product_category_name_translation.csv"
INTO TABLE product_translation
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'orders_items', COUNT(*) FROM orders_items
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'product_translation', COUNT(*) FROM product_translation;





-- CREATE VIEW
DROP VIEW IF EXISTS delivery_sla_analysis;
CREATE VIEW delivery_sla_analysis AS
WITH cleaned_orders AS (
SELECT
	o.order_id,
    o.customer_id,
    o.order_status,
    STR_TO_DATE(order_purchase_timestamp, '%d-%m-%Y %H:%i') as purchase_timestamp,
    STR_TO_DATE(order_approved_at, '%d-%m-%Y %H:%i') as approved_timestamp,
    STR_TO_DATE(order_delivered_carrier_date, '%d-%m-%Y %H:%i') as carrier_handoff_date,
    STR_TO_DATE(order_delivered_customer_date, '%d-%m-%Y %H:%i') as customer_delivery_date,
    STR_TO_DATE(order_estimated_delivery_date, '%d-%m-%Y %H:%i') as estimated_delivery_date
FROM orders o
WHERE order_status = 'delivered'
	AND o.order_delivered_customer_date IS NOT NULL
	AND o.order_delivered_carrier_date IS NOT NULL
    AND o.order_approved_at IS NOT NULL
),
order_items_cleaned AS (
SELECT
	oi.order_id,
    oi.product_id,
    oi.seller_id,
    STR_TO_DATE(shipping_limit_date, '%d-%m-%Y %H:%i') as seller_shipping_limit_date,
    oi.price,
    oi.freight_value
    FROM orders_items oi
)
SELECT
	co.order_id,
    co.customer_id,
    oic.seller_id,
    oic.product_id,
    
    s.seller_city,
    s.seller_state as origin_state,
    c.customer_city,
    c.customer_state as destination_state,
    CONCAT(s.seller_state, '->', c.customer_state) as route_corridor,
    
    COALESCE(NULLIF(TRIM(pt.product_category_name_english), ''), NULLIF(TRIM(p.product_category_name),''), 'Other') as product_category,
    CAST(p.product_weight_g AS UNSIGNED) as product_weight_g,
    oic.price,
    oic.freight_value,
    
    co.purchase_timestamp,
    co.approved_timestamp,
    co.carrier_handoff_date,
    co.customer_delivery_date,
    co.estimated_delivery_date,
    oic.seller_shipping_limit_date,
    
    ROUND(TIMESTAMPDIFF(SECOND, co.approved_timestamp, co.carrier_handoff_date)/ 86400.0, 2) as seller_dispatch_days,
    ROUND(TIMESTAMPDIFF(SECOND, co.carrier_handoff_date, co.customer_delivery_date)/ 86400.0, 2) as carrier_transit_days,
    ROUND(TIMESTAMPDIFF(SECOND, co.approved_timestamp, co.customer_delivery_date)/ 86400.0, 2) as total_fulfillment_days,
    ROUND(TIMESTAMPDIFF(SECOND, co.estimated_delivery_date, co.customer_delivery_date)/ 86400.0, 2) as delivery_variance_days,
    
    CASE
		WHEN co.customer_delivery_date > co.estimated_delivery_date THEN 1 ELSE 0 END as is_customer_delivery_late,
	CASE
		WHEN co.carrier_handoff_date > oic.seller_shipping_limit_date THEN 1 ELSE 0 END as is_seller_dispatch_late,
	CASE
		WHEN co.carrier_handoff_date <= oic.seller_shipping_limit_date
        AND co.customer_delivery_date > co.estimated_delivery_date
        THEN 1 ELSE 0 END as is_carrier_transit_late,
        
	CASE
		WHEN co.customer_delivery_date <= co.estimated_delivery_date THEN 'On-Time Delivery'
        WHEN co.carrier_handoff_date > oic.seller_shipping_limit_date AND co.customer_delivery_date > co.estimated_delivery_date THEN 'Seller Dispatch Bottleneck'
        ELSE 'Carrier Transit Bottleneck' END as delay_distribution
FROM cleaned_orders co
JOIN order_items_cleaned oic ON co.order_id = oic.order_id
JOIN customers c ON co.customer_id = c.customer_id
JOIN sellers s ON oic.seller_id = s.seller_id
LEFT JOIN products p ON oic.product_id = p.product_id
LEFT JOIN product_translation pt ON p.product_category_name = pt.product_category_name;

SELECT
	COUNT(*) AS total_shipment_items,
    ROUND(AVG(is_customer_delivery_late) * 100,2) AS customer_delivery_breach_pct,
    ROUND(AVG(is_seller_dispatch_late) * 100, 2) AS seller_breach_pct,
    ROUND(AVG(is_carrier_transit_late) * 100, 2) AS carrier_breach_pct,
    ROUND(AVG(seller_dispatch_days), 2) AS avg_seller_dispatch_days,
    ROUND(AVG(carrier_transit_days), 2) AS avg_carrier_transit_days,
    ROUND(AVG(total_fulfillment_days), 2) AS avg_fulfillment_days
FROM delivery_sla_analysis;

SELECT 
    COUNT(*) AS qualifying_categories,
    SUM(total_orders) AS filtered_volume,
    (SELECT COUNT(*) FROM delivery_sla_analysis) AS total_dataset_volume,
    ROUND(
        SUM(total_orders) * 100.0 / (SELECT COUNT(*) FROM delivery_sla_analysis), 
        2
    ) AS total_coverage_pct
FROM (
    SELECT 
        product_category,
        COUNT(*) AS total_orders
    FROM delivery_sla_analysis
    GROUP BY product_category
    HAVING COUNT(*) >= 300
) t;

SELECT 
        route_corridor,
        COUNT(*) AS total_orders
    FROM delivery_sla_analysis
    GROUP BY route_corridor
    ORDER BY total_orders desc;
    
select
	count(*) as total_corridors_having_min_500_orders,
    sum(total_orders) as volume_covered,
    round(sum(total_orders) * 100 / (select count(*) from delivery_sla_analysis),2) as coverage_pct
from
	(select
	route_corridor,
    count(*) as total_orders
from delivery_sla_analysis
group by route_corridor
having count(*) >=500)t;