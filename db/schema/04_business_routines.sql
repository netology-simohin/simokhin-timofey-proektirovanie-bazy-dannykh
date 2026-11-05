CREATE OR REPLACE PROCEDURE simokhin_food.add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar,
    p_price numeric,
    p_rating numeric,
    p_status simokhin_food.product_status,
    p_description text,
    p_photo_url text DEFAULT NULL
)
LANGUAGE plpgsql
SET search_path = simokhin_food, exts, pg_temp
AS $$
BEGIN
    INSERT INTO simokhin_food.product
        (product_id, product_name, product_category_id, price, restaurant_id,
         photo_url, rating, status, description)
    VALUES
        (exts.uuid_generate_v4(), p_name, p_product_category_id, p_price,
         p_restaurant_id, p_photo_url, p_rating, p_status, p_description);
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Ресторан или категория блюда не существуют';
    WHEN check_violation OR not_null_violation THEN
        RAISE EXCEPTION 'Атрибуты блюда нарушают ограничения схемы';
END;
$$;

CREATE OR REPLACE FUNCTION simokhin_food.get_statistic()
RETURNS TABLE (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
LANGUAGE sql
SET search_path = simokhin_food, pg_temp
AS $$
    WITH delivered_orders AS MATERIALIZED (
        SELECT order_id, restaurant_id, client_id, total_amount
        FROM simokhin_food."order"
        WHERE status = 'доставлен'
    ),
    order_totals AS (
        SELECT restaurant_id, sum(total_amount) AS total_amount,
               avg(total_amount) AS avg_amount
        FROM delivered_orders
        GROUP BY restaurant_id
    ),
    product_sales AS (
        SELECT d.restaurant_id, p.product_id, p.product_name,
               sum(os.quantity) AS quantity_sold
        FROM delivered_orders d
        JOIN simokhin_food.order_structure os USING (order_id)
        JOIN simokhin_food.product p USING (product_id)
        GROUP BY d.restaurant_id, p.product_id, p.product_name
    ),
    best_products AS (
        SELECT DISTINCT ON (restaurant_id) restaurant_id, product_name
        FROM product_sales
        ORDER BY restaurant_id, quantity_sold DESC, random()
    ),
    client_orders AS (
        SELECT d.restaurant_id, c.client_id, c.login, count(*) AS order_count
        FROM delivered_orders d
        JOIN simokhin_food.client c USING (client_id)
        GROUP BY d.restaurant_id, c.client_id, c.login
    ),
    best_clients AS (
        SELECT DISTINCT ON (restaurant_id) restaurant_id, login
        FROM client_orders
        ORDER BY restaurant_id, order_count DESC, random()
    )
    SELECT r.restaurant_name, bp.product_name,
           ot.total_amount, ot.avg_amount, bc.login
    FROM simokhin_food.restaurant r
    LEFT JOIN order_totals ot USING (restaurant_id)
    LEFT JOIN best_products bp USING (restaurant_id)
    LEFT JOIN best_clients bc USING (restaurant_id)
    ORDER BY r.restaurant_name
$$;

CREATE OR REPLACE PROCEDURE simokhin_food.courier_salary()
LANGUAGE plpgsql
SET search_path = simokhin_food, pg_temp
AS $$
DECLARE
    v_month_start timestamp := date_trunc('month', localtimestamp);
    v_courier record;
    v_deliveries integer;
    v_commission numeric(14,2);
    v_new_coefficient numeric(2,1);
BEGIN
    FOR v_courier IN SELECT courier_id, status, coefficient FROM simokhin_food.courier LOOP
        SELECT count(*)::integer, coalesce(sum(commission), 0)
        INTO v_deliveries, v_commission
        FROM simokhin_food."order"
        WHERE courier_id = v_courier.courier_id
          AND status = 'доставлен'
          AND order_timestamp >= v_month_start
          AND order_timestamp < v_month_start + interval '1 month';

        INSERT INTO simokhin_food.courier_pay AS existing_pay
            (year, month, courier_id, amount, coefficient_used)
        VALUES (
            extract(year FROM v_month_start)::integer,
            extract(month FROM v_month_start)::integer,
            v_courier.courier_id,
            round(v_commission * v_courier.coefficient, 2),
            v_courier.coefficient
        )
        ON CONFLICT (year, month, courier_id) DO UPDATE
        SET amount = round(v_commission * existing_pay.coefficient_used, 2);

        IF v_courier.status <> 'уволен' THEN
            v_new_coefficient := CASE
                WHEN v_deliveries <= 150 THEN 0.1
                WHEN v_deliveries <= 250 THEN 0.2
                WHEN v_deliveries <= 500 THEN 0.3
                ELSE 0.5
            END;
            UPDATE simokhin_food.courier
            SET coefficient = v_new_coefficient
            WHERE courier_id = v_courier.courier_id;
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE VIEW simokhin_food.how_much_money AS
WITH RECURSIVE bounds AS (
    SELECT date_trunc('month', min(order_timestamp)) AS first_month,
           date_trunc('month', max(order_timestamp)) AS last_month
    FROM simokhin_food."order"
    WHERE status = 'доставлен'
), months(month_start, last_month) AS (
    SELECT first_month, last_month FROM bounds WHERE first_month IS NOT NULL
    UNION ALL
    SELECT month_start + interval '1 month', last_month
    FROM months WHERE month_start < last_month
), order_totals AS (
    SELECT date_trunc('month', order_timestamp) AS month_start,
           sum(order_amount) AS sum_no_commission,
           sum(total_amount) AS sum_with_commission
    FROM simokhin_food."order"
    WHERE status = 'доставлен'
    GROUP BY date_trunc('month', order_timestamp)
), pay_totals AS (
    SELECT make_date(year, month, 1)::timestamp AS month_start,
           sum(amount) AS courier_pay
    FROM simokhin_food.courier_pay
    GROUP BY year, month
), month_values AS (
    SELECT m.month_start,
           coalesce(ot.sum_no_commission, 0)::numeric AS sum_no_commission,
           coalesce(ot.sum_with_commission, 0)::numeric AS sum_with_commission,
           (coalesce(ot.sum_with_commission, 0) - coalesce(ot.sum_no_commission, 0))::numeric AS commission,
           coalesce(pt.courier_pay, 0)::numeric AS courier_pay
    FROM months m
    LEFT JOIN order_totals ot USING (month_start)
    LEFT JOIN pay_totals pt USING (month_start)
), lagged AS (
    SELECT month_start, sum_no_commission, sum_with_commission, commission,
           lag(commission) OVER (ORDER BY month_start) AS prev_commission,
           courier_pay
    FROM month_values
)
SELECT to_char(month_start, 'YYYY-MM')::text AS year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission - prev_commission AS commission_diff,
       courier_pay,
       commission - courier_pay AS net_profit
FROM lagged;
