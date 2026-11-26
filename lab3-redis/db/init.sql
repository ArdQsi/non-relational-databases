-- Каталог товаров + отзывы.
-- Карточка товара включает агрегаты по отзывам и рейтинг внутри категории

CREATE TABLE products (
    id          SERIAL PRIMARY KEY,
    name        TEXT        NOT NULL,
    category    TEXT        NOT NULL,
    price       NUMERIC(10,2) NOT NULL,
    description TEXT        NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO products (name, category, price, description)
SELECT
    'Product ' || g,
    (ARRAY['phones','laptops','books','toys','home'])[1 + g % 5],
    round((random() * 1000 + 1)::numeric, 2),
    repeat('Описание товара ' || g || '. ', 20)
FROM generate_series(1, 10000) AS g;

CREATE INDEX idx_products_category ON products(category);

CREATE TABLE reviews (
    id          BIGSERIAL PRIMARY KEY,
    product_id  INT         NOT NULL REFERENCES products(id),
    rating      SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 50 отзывов на товар => 500 000 строк; ~100 000 строк на категорию
INSERT INTO reviews (product_id, rating)
SELECT 1 + (g % 10000),
       1 + floor(random() * 5)::int
FROM generate_series(1, 500000) AS g;

CREATE INDEX idx_reviews_product ON reviews(product_id);

ANALYZE;
