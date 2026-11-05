CREATE TABLE simokhin_food.client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(50) NOT NULL UNIQUE,
    password char(32) NOT NULL CHECK (password ~ '^[0-9a-f]{32}$'),
    phone_number char(11) NOT NULL UNIQUE
);

CREATE TABLE simokhin_food.address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(150) NOT NULL,
    house_number varchar(20) NOT NULL,
    apartment_office varchar(20)
);

CREATE TABLE simokhin_food.client_address (
    client_id uuid NOT NULL REFERENCES simokhin_food.client(client_id),
    address_id uuid NOT NULL REFERENCES simokhin_food.address(address_id),
    PRIMARY KEY (client_id, address_id)
);

CREATE TABLE simokhin_food.restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL,
    address_id uuid NOT NULL UNIQUE REFERENCES simokhin_food.address(address_id),
    description text NOT NULL,
    work_start time NOT NULL,
    work_end time NOT NULL,
    company_details text NOT NULL,
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    status simokhin_food.restaurant_status NOT NULL DEFAULT 'активен',
    CHECK (work_end > work_start)
);

CREATE TABLE simokhin_food.courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio varchar(150) NOT NULL,
    phone_number char(11) NOT NULL,
    status simokhin_food.courier_status NOT NULL DEFAULT 'свободен',
    hire_date date NOT NULL,
    dismissal_date date,
    coefficient numeric(2,1) NOT NULL DEFAULT 0.1,
    CHECK (coefficient BETWEEN 0.1 AND 0.5),
    CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date),
    CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL)
);

CREATE TABLE simokhin_food.courier_pay (
    year integer NOT NULL CHECK (year BETWEEN 2000 AND 9999),
    month integer NOT NULL CHECK (month BETWEEN 1 AND 12),
    courier_id uuid NOT NULL REFERENCES simokhin_food.courier(courier_id),
    amount numeric(14,2) NOT NULL CHECK (amount >= 0),
    coefficient_used numeric(2,1) NOT NULL CHECK (coefficient_used BETWEEN 0.1 AND 0.5),
    PRIMARY KEY (year, month, courier_id)
);

CREATE TABLE simokhin_food.product_category (
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(80) NOT NULL
);

CREATE TABLE simokhin_food.product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(100) NOT NULL,
    product_category_id uuid NOT NULL REFERENCES simokhin_food.product_category(product_category_id),
    price numeric(12,2) NOT NULL CHECK (price >= 0),
    restaurant_id uuid NOT NULL REFERENCES simokhin_food.restaurant(restaurant_id),
    photo_url text,
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    status simokhin_food.product_status NOT NULL DEFAULT 'доступно',
    description text NOT NULL
);

CREATE TABLE simokhin_food."order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL REFERENCES simokhin_food.courier(courier_id),
    client_id uuid NOT NULL REFERENCES simokhin_food.client(client_id),
    address_id uuid NOT NULL REFERENCES simokhin_food.address(address_id),
    restaurant_id uuid NOT NULL REFERENCES simokhin_food.restaurant(restaurant_id),
    order_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    delivery_timestamp timestamp,
    order_amount numeric(14,2) NOT NULL CHECK (order_amount >= 0),
    commission numeric(14,2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,
    total_amount numeric(14,2) GENERATED ALWAYS AS (round(order_amount + round(order_amount * 0.10, 2), 2)) STORED,
    status simokhin_food.order_status NOT NULL DEFAULT 'создан',
    pay_status simokhin_food.order_pay_status NOT NULL DEFAULT 'ожидает',
    description text NOT NULL,
    CHECK (total_amount >= 1000),
    CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CHECK ((status = 'доставлен') = (delivery_timestamp IS NOT NULL)),
    FOREIGN KEY (client_id, address_id)
        REFERENCES simokhin_food.client_address(client_id, address_id),
    UNIQUE (order_id, client_id)
);

CREATE TABLE simokhin_food.order_structure (
    order_id uuid NOT NULL REFERENCES simokhin_food."order"(order_id),
    product_id uuid NOT NULL REFERENCES simokhin_food.product(product_id),
    quantity numeric(10,3) NOT NULL CHECK (quantity > 0),
    unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE simokhin_food.payment (
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES simokhin_food."order"(order_id),
    type simokhin_food.payment_type NOT NULL,
    amount numeric(14,2) NOT NULL CHECK (amount >= 0),
    transaction_id varchar(100) NOT NULL UNIQUE,
    transaction_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    status simokhin_food.payment_status NOT NULL
);
CREATE UNIQUE INDEX payment_one_success_per_order
    ON simokhin_food.payment(order_id) WHERE status = 'успех';

CREATE TABLE simokhin_food.review (
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL,
    review_timestamp timestamp NOT NULL DEFAULT localtimestamp,
    entity_id uuid NOT NULL,
    entity_type simokhin_food.review_entity_type NOT NULL,
    order_id uuid NOT NULL,
    description text NOT NULL,
    photo_url text,
    rating numeric(2,1) NOT NULL CHECK (rating BETWEEN 1 AND 5),
    FOREIGN KEY (order_id, client_id)
        REFERENCES simokhin_food."order"(order_id, client_id),
    UNIQUE (order_id, entity_type, entity_id)
);
