CREATE DATABASE IF NOT EXISTS monitoring;

-- Основная таблица: одно событие = один обработанный HTTP-запрос (access-лог + метрики)
CREATE TABLE IF NOT EXISTS monitoring.service_events
(
    timestamp   DateTime64(3, 'UTC') CODEC(Delta, ZSTD(1)),
    service     LowCardinality(String),
    host        LowCardinality(String),
    method      LowCardinality(String),
    endpoint    LowCardinality(String),
    status      UInt16,
    duration_ms UInt32,
    bytes_sent  UInt32 CODEC(T64, ZSTD(1)),
    level       Enum8('INFO' = 1, 'WARN' = 2, 'ERROR' = 3),
    user_id     UInt32,
    trace_id    UUID,
    message     String CODEC(ZSTD(3)),

    INDEX idx_trace trace_id TYPE bloom_filter(0.01) GRANULARITY 4
)
ENGINE = MergeTree
PARTITION BY toDate(timestamp)
ORDER BY (service, endpoint, timestamp)
TTL toDateTime(timestamp) + INTERVAL 30 DAY DELETE
SETTINGS index_granularity = 8192;

-- Минутный агрегат: лёгкая таблица для длинных интервалов на дашборде
CREATE TABLE IF NOT EXISTS monitoring.service_stats_1m
(
    minute       DateTime('UTC'),
    service      LowCardinality(String),
    endpoint     LowCardinality(String),
    requests     UInt64,
    errors_5xx   UInt64,
    duration_sum UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(minute)
ORDER BY (service, endpoint, minute)
TTL minute + INTERVAL 180 DAY DELETE;

CREATE MATERIALIZED VIEW IF NOT EXISTS monitoring.service_stats_1m_mv
TO monitoring.service_stats_1m AS
SELECT
    toStartOfMinute(toDateTime(timestamp, 'UTC')) AS minute,
    service,
    endpoint,
    count()                  AS requests,
    countIf(status >= 500)   AS errors_5xx,
    sum(duration_ms)         AS duration_sum
FROM monitoring.service_events
GROUP BY minute, service, endpoint;
