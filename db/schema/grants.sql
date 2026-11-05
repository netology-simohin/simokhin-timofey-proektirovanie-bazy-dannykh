DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        EXECUTE 'CREATE ROLE inspector LOGIN PASSWORD ''NetoSQL2025''';
    ELSE
        EXECUTE 'ALTER ROLE inspector LOGIN PASSWORD ''NetoSQL2025''';
    END IF;
END;
$$;

GRANT ALL PRIVILEGES ON SCHEMA simokhin_food TO inspector;
GRANT USAGE ON SCHEMA exts TO inspector;
GRANT USAGE ON TYPE simokhin_food.restaurant_status TO inspector;
GRANT USAGE ON TYPE simokhin_food.product_status TO inspector;
GRANT USAGE ON TYPE simokhin_food.courier_status TO inspector;
GRANT USAGE ON TYPE simokhin_food.order_status TO inspector;
GRANT USAGE ON TYPE simokhin_food.order_pay_status TO inspector;
GRANT USAGE ON TYPE simokhin_food.payment_status TO inspector;
GRANT USAGE ON TYPE simokhin_food.payment_type TO inspector;
GRANT USAGE ON TYPE simokhin_food.review_entity_type TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA simokhin_food TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA simokhin_food TO inspector;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA simokhin_food TO inspector;
GRANT EXECUTE ON FUNCTION exts.uuid_generate_v4() TO inspector;

ALTER DEFAULT PRIVILEGES IN SCHEMA simokhin_food
    GRANT ALL PRIVILEGES ON TABLES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA simokhin_food
    GRANT USAGE ON TYPES TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA simokhin_food
    GRANT EXECUTE ON FUNCTIONS TO inspector;

DO $$
BEGIN
    IF NOT has_schema_privilege('inspector', 'information_schema', 'USAGE')
       OR NOT has_schema_privilege('inspector', 'pg_catalog', 'USAGE') THEN
        RAISE EXCEPTION 'inspector должен иметь USAGE на системные схемы';
    END IF;
END;
$$;
