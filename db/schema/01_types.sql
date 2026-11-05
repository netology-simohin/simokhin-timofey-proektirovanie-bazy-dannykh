CREATE SCHEMA IF NOT EXISTS simokhin_food;

CREATE TYPE simokhin_food.restaurant_status AS ENUM ('активен', 'неактивен');
CREATE TYPE simokhin_food.product_status AS ENUM ('доступно', 'нет_в_наличии', 'архив');
CREATE TYPE simokhin_food.courier_status AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');
CREATE TYPE simokhin_food.order_status AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
CREATE TYPE simokhin_food.order_pay_status AS ENUM ('ожидает', 'оплачен', 'ошибка');
CREATE TYPE simokhin_food.payment_status AS ENUM ('успех', 'ошибка', 'в_обработке');
CREATE TYPE simokhin_food.payment_type AS ENUM ('карта', 'наличные', 'безнал');
CREATE TYPE simokhin_food.review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');
