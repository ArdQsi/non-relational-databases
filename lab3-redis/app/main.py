"""Каталог товаров: PostgreSQL + кэш Redis (cache-aside)

Приложение работает в нескольких процессах (uvicorn --workers), поэтому метрики
Prometheus собираются в multiprocess-режиме (PROMETHEUS_MULTIPROC_DIR)
"""
import json
import os
import random
import time
from contextlib import asynccontextmanager
from decimal import Decimal
import asyncpg
import redis.asyncio as aioredis
from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import (CONTENT_TYPE_LATEST, CollectorRegistry, Counter,
                               Histogram, generate_latest, multiprocess)
from pydantic import BaseModel

DATABASE_URL = os.getenv("DATABASE_URL")
REDIS_URL = os.getenv("REDIS_URL")
CACHE_TTL = int(os.getenv("CACHE_TTL", "60"))
NEGATIVE_TTL = int(os.getenv("NEGATIVE_TTL", "10"))
DB_POOL_MAX = int(os.getenv("DB_POOL_MAX", "5"))  # на один процесс
TTL_JITTER = 0.2  # ±20% — защита от массовой одновременной инвалидации

HTTP_REQUESTS = Counter("app_http_requests_total", "HTTP-запросы",
                        ["method", "endpoint", "status"])
HTTP_LATENCY = Histogram("app_http_request_duration_seconds", "Латентность HTTP",
                         ["endpoint"],
                         buckets=(.001, .0025, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10))
CACHE_HITS = Counter("app_cache_hits_total", "Попадания в кэш")
CACHE_MISSES = Counter("app_cache_misses_total", "Промахи кэша")
CACHE_ERRORS = Counter("app_cache_errors_total", "Ошибки Redis (fallback на БД)")
DB_LATENCY = Histogram("app_db_query_duration_seconds", "Время запроса к PostgreSQL (включая ожидание свободного соединения из пула)",
                       buckets=(.001, .0025, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10))

pool: asyncpg.Pool
rds: aioredis.Redis

@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool, rds
    pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=DB_POOL_MAX)
    rds = aioredis.from_url(REDIS_URL, decode_responses=True,
                            socket_timeout=0.5, socket_connect_timeout=0.5)
    yield
    await pool.close()
    await rds.aclose()

app = FastAPI(title="Product catalog with Redis cache", lifespan=lifespan)

class ProductUpdate(BaseModel):
    price: float

def _key(pid: int) -> str:
    return f"product:{pid}"

# Дорогой запрос: карточка товара + статистика отзывов + место товара в рейтинге своей категории
PRODUCT_SQL = """
SELECT p.id, p.name, p.category, p.price, p.description, p.updated_at,
       s.reviews_count,
       s.avg_rating,
       (SELECT count(*) + 1
          FROM (SELECT r2.product_id
                  FROM reviews r2
                  JOIN products p2 ON p2.id = r2.product_id
                 WHERE p2.category = p.category
                 GROUP BY r2.product_id
                HAVING avg(r2.rating) > s.avg_rating) t) AS category_rank
FROM products p
CROSS JOIN LATERAL (
    SELECT count(*) AS reviews_count,
           COALESCE(avg(rating), 0) AS avg_rating
      FROM reviews
     WHERE product_id = p.id
) s
WHERE p.id = $1
"""

async def _db_get(pid: int):
    start = time.perf_counter()
    try:
        row = await pool.fetchrow(PRODUCT_SQL, pid)
    finally:
        DB_LATENCY.observe(time.perf_counter() - start)
    if row is None:
        return None
    d = dict(row)
    for k, v in d.items():
        if isinstance(v, Decimal):
            d[k] = round(float(v), 2)
    d["updated_at"] = d["updated_at"].isoformat()
    return d


@app.middleware("http")
async def metrics_mw(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    route = request.scope.get("route")
    endpoint = route.path if route else request.url.path
    HTTP_LATENCY.labels(endpoint).observe(time.perf_counter() - start)
    HTTP_REQUESTS.labels(request.method, endpoint, response.status_code).inc()
    return response


@app.get("/products/{pid}")
async def get_product(pid: int, response: Response):
    """Cache-aside: Redis -> (miss) -> PostgreSQL -> запись в Redis"""
    key = _key(pid)
    try:
        cached = await rds.get(key)
    except Exception:
        CACHE_ERRORS.inc()
        cached = None

    if cached is not None:
        CACHE_HITS.inc()
        response.headers["X-Cache"] = "HIT"
        data = json.loads(cached)
        if data.get("_missing"):
            raise HTTPException(404, "Product not found")
        return data

    CACHE_MISSES.inc()
    response.headers["X-Cache"] = "MISS"
    data = await _db_get(pid)
    try:
        if data is None:
            # negative caching: защита от запросов к несуществующим id
            await rds.set(key, json.dumps({"_missing": True}), ex=NEGATIVE_TTL)
        else:
            ttl = int(CACHE_TTL * random.uniform(1 - TTL_JITTER, 1 + TTL_JITTER))
            await rds.set(key, json.dumps(data), ex=ttl)
    except Exception:
        CACHE_ERRORS.inc()
    if data is None:
        raise HTTPException(404, "Product not found")
    return data


@app.get("/products/nocache/{pid}")
async def get_product_nocache(pid: int):
    """Эталон для сравнения: всегда ходим в БД"""
    data = await _db_get(pid)
    if data is None:
        raise HTTPException(404, "Product not found")
    return data


@app.put("/products/{pid}")
async def update_product(pid: int, body: ProductUpdate):
    """Запись в БД + инвалидация кэша"""
    row = await pool.fetchrow(
        "UPDATE products SET price=$2, updated_at=now() WHERE id=$1 RETURNING id",
        pid, body.price)
    if row is None:
        raise HTTPException(404, "Product not found")
    try:
        await rds.delete(_key(pid))
    except Exception:
        CACHE_ERRORS.inc()
    return {"id": pid, "price": body.price, "cache": "invalidated"}


@app.get("/health")
async def health():
    status = {"postgres": "ok", "redis": "ok"}
    try:
        await pool.fetchval("SELECT 1")
    except Exception:
        status["postgres"] = "down"
    try:
        await rds.ping()
    except Exception:
        status["redis"] = "down"
    code = 200 if status["postgres"] == "ok" else 503
    return Response(json.dumps(status), status_code=code, media_type="application/json")


@app.get("/metrics")
async def metrics():
    registry = CollectorRegistry()
    multiprocess.MultiProcessCollector(registry)
    return Response(generate_latest(registry), media_type=CONTENT_TYPE_LATEST)
