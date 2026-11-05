# Протокол самопроверки

## Окружение и статус

| Параметр | Значение |
|---|---|
| PostgreSQL | 15.19 (`postgres:15-alpine`) |
| Схема | `simokhin_food` |
| Аудитор | `inspector` |
| Дата прогона | 2026-11-05 |
| Статус прогона | Пройдено на временном PostgreSQL 15; результаты ниже |

Скрипты схемы применены на чистой БД с заранее созданной `exts` и расширением `uuid-ossp`. Функциональные сценарии запускались как `inspector`; развертывание и `grants.sql` — как администратор БД.

## Установка на чистую базу

Схема `exts` с `uuid-ossp` должна быть предварительно создана окружением, как требует BR-13.3. После этого применить файлы по порядку из корня репозитория:

```sh
psql -v ON_ERROR_STOP=1 -d foodexpress \
  -c 'CREATE SCHEMA exts; CREATE EXTENSION "uuid-ossp" WITH SCHEMA exts;'
for f in db/schema/01_types.sql db/schema/02_tables.sql db/schema/03_triggers.sql \
         db/schema/04_business_routines.sql db/schema/05_test_data.sql db/schema/grants.sql; do
  psql -v ON_ERROR_STOP=1 -d foodexpress -f "$f" || exit 1
done
```

Результат: все шесть файлов применены без ошибок на PostgreSQL 15.19.

## FOOD-101 — структура

Проверить наличие всех 12 ERD-таблиц, восьми enum-типов, UUID-полей идентификаторов, PK согласно ERD и не менее 15 FK:

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'simokhin_food' ORDER BY table_name;

SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder)
FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'simokhin_food' GROUP BY t.typname ORDER BY t.typname;

SELECT tc.table_name, array_agg(kcu.column_name ORDER BY kcu.ordinal_position) AS primary_key
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  USING (constraint_catalog, constraint_schema, constraint_name, table_name)
WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema = 'simokhin_food'
GROUP BY tc.table_name ORDER BY tc.table_name;

SELECT conname, conrelid::regclass, confrelid::regclass
FROM pg_constraint
WHERE contype = 'f' AND connamespace = 'simokhin_food'::regnamespace;
```

Факт/вердикт: **OK** — 12 таблиц, 8 enum и 15 FK обнаружены; все ID-поля UUID. `inspector` видит 13 объектов через `information_schema.tables` (12 таблиц + представление) и 12 таблиц через `pg_catalog.pg_tables`.

## FOOD-102/103 — генератор и очистка

Под `inspector` выполнить `CALL erase_test_data();` дважды, затем `CALL insert_test_data(10);`. Проверить ожидаемые количества `10/50` по BR-11.7, валидность всех FK, пароли MD5, адрес заказа клиента, принадлежность блюд ресторану заказа, суммы заказа, оплаты и выплаты за шесть месяцев. `NULL`, неположительные значения и значение выше 429496729 должны отклоняться до генерации данных. Запустить генератор повторно десять раз без очистки; не должно быть конфликтов уникальности или частичных записей.

Факт/вердикт: **OK** — две очистки подряд прошли; `insert_test_data(10)` и десять повторных вызовов прошли. Проверены количества на один вызов (10/50, 40 связей клиента с адресом, 60 записей выплат); десять вызовов добавили 600 выплат. Вызов со значением 429496730 отклонён до генерации. Проверены диапазон дат, адрес клиента, ресторан блюд, суммы строк, оплаты и выплаты. После очистки таблицы пусты.

## FOOD-104/105/106 — продукт, отзывы, статистика

- `add_product(...)`: счётчик блюд увеличивается на один; проверить несуществующие ресторан и категорию, отрицательную цену и успешную вставку.
- `rating_change`: вставить рейтинги 3, 4, 4.5 к одному блюду на соответствующих заказах; проверить среднее 3.83, после удаления оценки 3 — 4.25, после удаления всех — `NULL`. Проверить, что удаление/замена позиции заказа, на которую оставлен отзыв, отклоняется. Повторить для ресторана и проверить UPDATE переноса отзыва.
- `get_statistic()`: имена результата строго `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`; строка на ресторан, только доставленные заказы. Сверить суммы и средние с независимой агрегацией `order`.
- Перенести единственную позицию из заказа A в B с выравниванием суммы B; COMMIT должен отклониться, если A останется без позиций.
- Изменить `order_amount` и согласованно обновить платежи в одной транзакции; несогласованную сумму платежа или прямое изменение `pay_status` COMMIT/UPDATE должен отклонить.

Факт/вердикт: **OK** — `add_product` добавил строку; отсутствующие ресторан и категория, отрицательная цена отклонены. Дробная оценка `4.5` сохранилась, агрегатный рейтинг пересчитан; проверены удаление/замена позиции с отзывом (операции отклонены). Для блюда ранее проверены средние 4, 4.5 и `NULL`; для ресторана — INSERT, UPDATE среднего до 3.67 и удаление до `NULL`. `get_statistic()` вернул одну строку на ресторан; суммы и средние совпали с независимой агрегацией.

## FOOD-107/108 — зарплата и отчёт

- `CALL courier_salary();` дважды в одном месяце: одна запись на курьера и месяц, сумма по комиссии и применённому коэффициенту; коэффициент обновлён для работающих, не изменён для уволенных.
- Для курьера с 151 доставкой и ненулевой комиссией сохранить выплату после первого вызова, затем вызвать процедуру повторно: `amount` и `coefficient_used` за месяц должны остаться по ставке, действовавшей в этом месяце.
- `SELECT * FROM simokhin_food.how_much_money`: точные восемь колонок, непрерывные месяцы, пропуски имеют нулевые суммы, формулы `commission`, `commission_diff`, `net_profit` верны.

Факт/вердикт: **OK** — процедура вызвана повторно; проверки с 0, 150, 151, 250, 251, 500 и 501 доставкой подтвердили все переходы коэффициентов и выплату по действовавшей ставке. Отдельно подтверждены неизменность суммы/`coefficient_used` при повторе и неизменность коэффициента уволенного. Проверены восемь типов колонок представления, шесть непрерывных месяцев и нулевой месяц с нулевой выплатой/прибылью.

## FOOD-109/110 — права и архив

Скрипт `grants.sql` применён без ошибок. Под `inspector` проверены генератор, очистка, зарплатная процедура, `get_statistic()`, представление, `information_schema.tables` и `pg_catalog.pg_tables`.

Архив создаётся как schema-only custom archive без владельца и ACL (роль создаёт отдельный `grants.sql`):

```sh
pg_dump -Fc --schema-only --no-acl --no-owner -n simokhin_food \
  -f db/foodexpress_simokhin.backup foodexpress
```

Факт/вердикт: **OK** — `db/foodexpress_simokhin.backup` создан (66,168 байт, custom format, PostgreSQL 15.19), список TOC проверен; архив не содержит `TABLE DATA`. Актуальная схема восстановлена в пустую БД с заранее созданной `exts`/`uuid-ossp`; после `grants.sql` под `inspector` выполнены `insert_test_data(10)` и проверки генерации.
