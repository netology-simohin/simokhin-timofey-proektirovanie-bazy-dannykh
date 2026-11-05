CREATE OR REPLACE PROCEDURE simokhin_food.erase_test_data()
LANGUAGE plpgsql
SET search_path = simokhin_food, pg_temp
AS $$
BEGIN
    DELETE FROM simokhin_food.review;
    DELETE FROM simokhin_food.payment;
    DELETE FROM simokhin_food.order_structure;
    DELETE FROM simokhin_food.courier_pay;
    DELETE FROM simokhin_food."order";
    DELETE FROM simokhin_food.client_address;
    DELETE FROM simokhin_food.product;
    DELETE FROM simokhin_food.restaurant;
    DELETE FROM simokhin_food.client;
    DELETE FROM simokhin_food.courier;
    DELETE FROM simokhin_food.product_category;
    DELETE FROM simokhin_food.address;
END;
$$;

CREATE OR REPLACE PROCEDURE simokhin_food.insert_test_data(value integer)
LANGUAGE plpgsql
SET search_path = simokhin_food, exts, pg_temp
AS $$
DECLARE
    i integer;
    j integer;
    v_count integer;
    v_id uuid;
    v_client_idx integer;
    v_restaurant_idx integer;
    v_product_idx integer;
    v_month_offset integer;
    v_day integer;
    v_month timestamp;
    v_order_timestamp timestamp;
    v_coefficient numeric(2,1);
    v_new_coefficient numeric(2,1);
    v_deliveries integer;
    v_commission numeric(14,2);
    v_phone_base bigint := (extract(epoch FROM clock_timestamp()) * 1000000)::bigint % 10000000000;
    v_clients uuid[] := ARRAY[]::uuid[];
    v_couriers uuid[] := ARRAY[]::uuid[];
    v_restaurants uuid[] := ARRAY[]::uuid[];
    v_categories uuid[] := ARRAY[]::uuid[];
    v_addresses uuid[] := ARRAY[]::uuid[];
    v_products uuid[] := ARRAY[]::uuid[];
    v_restaurant_statuses simokhin_food.restaurant_status[] := enum_range(NULL::simokhin_food.restaurant_status);
    v_product_statuses simokhin_food.product_status[] := enum_range(NULL::simokhin_food.product_status);
    v_courier_statuses simokhin_food.courier_status[] := enum_range(NULL::simokhin_food.courier_status);
    v_order_statuses simokhin_food.order_status[] := enum_range(NULL::simokhin_food.order_status);
    v_order_pay_statuses simokhin_food.order_pay_status[] := enum_range(NULL::simokhin_food.order_pay_status);
    v_payment_statuses simokhin_food.payment_status[] := enum_range(NULL::simokhin_food.payment_status);
    v_payment_types simokhin_food.payment_type[] := enum_range(NULL::simokhin_food.payment_type);
    v_review_types simokhin_food.review_entity_type[] := enum_range(NULL::simokhin_food.review_entity_type);
BEGIN
    IF value IS NULL OR value < 1 THEN
        RAISE EXCEPTION 'value должен быть положительным целым числом';
    END IF;
    IF value > 2147483647 / 5 THEN
        RAISE EXCEPTION 'value не должен превышать 429496729';
    END IF;

    v_count := value * 5;

    FOR i IN 1..value LOOP
        v_id := exts.uuid_generate_v4();
        INSERT INTO simokhin_food.client(client_id, login, password, phone_number)
        VALUES (
            v_id,
            'client_' || v_id::text,
            md5(random()::text),
            lpad((70000000000::bigint + (v_phone_base + i) % 10000000000)::text, 11, '0')
        );
        v_clients := array_append(v_clients, v_id);

        v_id := exts.uuid_generate_v4();
        INSERT INTO simokhin_food.courier
            (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
        VALUES (
            v_id,
            'Курьер ' || v_id::text,
            lpad((70000000000::bigint + (v_phone_base + 100000 + i) % 10000000000)::text, 11, '0'),
            CASE WHEN value > 1 AND i = value THEN v_courier_statuses[4]
                 ELSE v_courier_statuses[1] END,
            current_date - 180,
            CASE WHEN value > 1 AND i = value THEN current_date - 1 ELSE NULL END,
            0.1
        );
        v_couriers := array_append(v_couriers, v_id);

        v_id := exts.uuid_generate_v4();
        INSERT INTO simokhin_food.product_category(product_category_id, product_category_name)
        VALUES (v_id, 'Категория ' || v_id::text);
        v_categories := array_append(v_categories, v_id);
    END LOOP;

    FOR i IN 1..v_count LOOP
        v_id := exts.uuid_generate_v4();
        INSERT INTO simokhin_food.address(address_id, street, house_number, apartment_office)
        VALUES (
            v_id,
            'Улица ' || v_id::text,
            (1 + (i % 300))::text,
            CASE WHEN i % 4 = 0 THEN NULL ELSE (1 + (i % 200))::text END
        );
        v_addresses := array_append(v_addresses, v_id);
    END LOOP;

    FOR i IN 1..value LOOP
        v_id := exts.uuid_generate_v4();
        INSERT INTO simokhin_food.restaurant
            (restaurant_id, restaurant_name, address_id, description, work_start,
             work_end, company_details, rating, status)
        VALUES (
            v_id,
            'Ресторан ' || v_id::text,
            v_addresses[i],
            'Тестовое описание ресторана ' || i,
            time '09:00', time '22:00', 'Тестовые реквизиты ' || v_id::text,
            NULL, v_restaurant_statuses[1]
        );
        v_restaurants := array_append(v_restaurants, v_id);
    END LOOP;

    FOR i IN 1..(value * 4) LOOP
        v_client_idx := ((i - 1) % value) + 1;
        INSERT INTO simokhin_food.client_address(client_id, address_id)
        VALUES (v_clients[v_client_idx], v_addresses[value + i]);
    END LOOP;

    FOR i IN 1..v_count LOOP
        v_restaurant_idx := ((i - 1) / 5) + 1;
        v_id := exts.uuid_generate_v4();
        INSERT INTO simokhin_food.product
            (product_id, product_name, product_category_id, price, restaurant_id,
             photo_url, rating, status, description)
        VALUES (
            v_id,
            'Блюдо ' || v_id::text,
            v_categories[((i - 1) % value) + 1],
            1000 + (i % 10) * 100,
            v_restaurants[v_restaurant_idx],
            CASE WHEN i % 3 = 0 THEN NULL ELSE 'https://cdn.foodexpress.ru/' || v_id::text || '.jpg' END,
            NULL, v_product_statuses[1], 'Тестовое описание блюда ' || i
        );
        v_products := array_append(v_products, v_id);
    END LOOP;

    FOR i IN 1..v_count LOOP
        v_client_idx := ((i - 1) % value) + 1;
        v_restaurant_idx := (((i - 1) / 5) % value) + 1;
        v_product_idx := (v_restaurant_idx - 1) * 5 + ((i - 1) % 5) + 1;
        v_month_offset := (i - 1) % 6;
        v_month := date_trunc('month', localtimestamp) - (5 - v_month_offset) * interval '1 month';
        IF v_month_offset = 5 THEN
            v_day := least(1 + (i % 20), extract(day FROM current_date)::integer);
        ELSE
            v_day := 1 + (i % 20);
        END IF;
        v_order_timestamp := v_month + (v_day - 1) * interval '1 day' + interval '10 hours';
        IF v_month_offset = 5 THEN
            v_order_timestamp := greatest(v_month, least(v_order_timestamp, localtimestamp - interval '1 hour'));
        END IF;
        v_order_timestamp := greatest(v_order_timestamp, localtimestamp - interval '180 days');

        v_id := exts.uuid_generate_v4();
        INSERT INTO simokhin_food."order"
            (order_id, courier_id, client_id, address_id, restaurant_id,
             order_timestamp, delivery_timestamp, order_amount, status, pay_status, description)
        VALUES (
            v_id,
            v_couriers[v_client_idx],
            v_clients[v_client_idx],
            v_addresses[value + v_client_idx],
            v_restaurants[v_restaurant_idx],
            v_order_timestamp, v_order_timestamp + interval '30 minutes',
            (SELECT price FROM simokhin_food.product WHERE product_id = v_products[v_product_idx]),
            v_order_statuses[array_position(v_order_statuses, 'доставлен'::simokhin_food.order_status)],
            v_order_pay_statuses[array_position(v_order_pay_statuses, 'ожидает'::simokhin_food.order_pay_status)],
            'Тестовый заказ ' || i
        );
        INSERT INTO simokhin_food.order_structure(order_id, product_id, quantity, unit_price)
        SELECT v_id, p.product_id, 1, p.price
        FROM simokhin_food.product p WHERE p.product_id = v_products[v_product_idx];

        INSERT INTO simokhin_food.payment
            (payment_id, order_id, type, amount, transaction_id, transaction_timestamp, status)
        SELECT exts.uuid_generate_v4(), v_id, v_payment_types[1], o.total_amount,
               'test-' || exts.uuid_generate_v4()::text, v_order_timestamp,
               v_payment_statuses[array_position(v_payment_statuses, 'успех'::simokhin_food.payment_status)]
        FROM simokhin_food."order" o WHERE o.order_id = v_id;

        INSERT INTO simokhin_food.review
            (review_id, client_id, review_timestamp, entity_id, entity_type,
             order_id, description, photo_url, rating)
        VALUES (
            exts.uuid_generate_v4(), v_clients[v_client_idx], v_order_timestamp + interval '1 hour',
            CASE v_review_types[((i - 1) % 3) + 1]
                WHEN 'блюдо' THEN v_products[v_product_idx]
                WHEN 'ресторан' THEN v_restaurants[v_restaurant_idx]
                ELSE v_id
            END,
            v_review_types[((i - 1) % 3) + 1], v_id,
            'Тестовый отзыв ' || i,
            CASE WHEN i % 4 = 0 THEN NULL ELSE 'https://cdn.foodexpress.ru/reviews/' || v_id::text || '.jpg' END,
            (i % 5) + 1
        );
    END LOOP;

    FOR i IN 1..value LOOP
        v_coefficient := 0.1;
        FOR j IN REVERSE 5..0 LOOP
            v_month := date_trunc('month', localtimestamp) - j * interval '1 month';
            SELECT count(*)::integer, coalesce(sum(commission), 0)
            INTO v_deliveries, v_commission
            FROM simokhin_food."order"
            WHERE courier_id = v_couriers[i]
              AND status = 'доставлен'
              AND date_trunc('month', order_timestamp) = v_month;

            INSERT INTO simokhin_food.courier_pay(year, month, courier_id, amount, coefficient_used)
            VALUES (
                extract(year FROM v_month)::integer,
                extract(month FROM v_month)::integer,
                v_couriers[i], round(v_commission * v_coefficient, 2), v_coefficient
            )
            ON CONFLICT (year, month, courier_id) DO UPDATE
            SET amount = EXCLUDED.amount, coefficient_used = EXCLUDED.coefficient_used;

            v_new_coefficient := CASE
                WHEN v_deliveries <= 150 THEN 0.1
                WHEN v_deliveries <= 250 THEN 0.2
                WHEN v_deliveries <= 500 THEN 0.3
                ELSE 0.5
            END;
            v_coefficient := v_new_coefficient;
        END LOOP;
        UPDATE simokhin_food.courier
        SET coefficient = v_coefficient
        WHERE courier_id = v_couriers[i] AND status <> 'уволен';
    END LOOP;
END;
$$;
